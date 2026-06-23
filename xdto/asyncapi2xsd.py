import argparse
import warnings
import yaml
import re
from decimal import Decimal, InvalidOperation
warnings.filterwarnings("ignore", message=".*GIL.*", category=RuntimeWarning)
from lxml import etree

# ================== CONSTANTS ==================

XSD_NS = "http://www.w3.org/2001/XMLSchema"

UUID_PATTERN = (
    r"[0-9a-fA-F]{8}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{12}"
)

ROW_SUFFIX = "Row"
LOCAL_SCHEMA_REF_PREFIX = "#/components/schemas/"

ELEMENT_ATTRIBUTE_ORDER = (
    "name",
    "type",
    "minOccurs",
    "maxOccurs",
    "nillable",
)


# ================== HELPERS ==================

def extract_type_name_from_address(address: str, prefix: str, suffix: str) -> str:
    """1c.test-accumulation-register -> TestAccumulationRegister"""
    name = address
    if prefix and name.startswith(prefix):
        name = name[len(prefix):]
    if suffix and name.endswith(suffix):
        name = name[: -len(suffix)]
    return pascal_case(name)


def build_channel_type_map(spec: dict, prefix: str, suffix: str) -> dict[str, str]:
    """
    Строит словарь schema_name -> type_name, проходя цепочку:
    channel.address -> channel.messages.$ref -> components/messages -> payload.$ref -> schema_name
    """
    messages = spec.get("components", {}).get("messages", {})
    result = {}

    for channel_name, channel_data in spec.get("channels", {}).items():
        address = channel_data.get("address", "")
        if not address:
            continue

        type_name = extract_type_name_from_address(address, prefix, suffix)

        # Берём первое сообщение канала (обычно одно)
        channel_messages = channel_data.get("messages", {})
        if not channel_messages:
            continue

        first_msg = next(iter(channel_messages.values()))
        msg_ref = first_msg.get("$ref", "")
        if not msg_ref:
            continue

        # Резолвим $ref на components/messages
        msg_name = ref_name(msg_ref)
        msg = messages.get(msg_name, {})
        if not msg:
            continue

        # Берём schema_name из payload.$ref
        payload_ref = msg.get("payload", {}).get("$ref", "")
        if not payload_ref:
            continue

        schema_name = ref_name(payload_ref)
        result[schema_name] = type_name

    return result


def resolve_schema_type_name(schema_name: str, channel_map: dict[str, str]) -> str:
    """
    Резолвит имя типа для схемы:
    1. Ищет совпадение в channel_map (channel_name == schema_name)
    2. Иначе возвращает pascal_case от имени схемы
    """
    if schema_name in channel_map:
        return channel_map[schema_name]
    return pascal_case(schema_name)


def ref_name(ref: str) -> str:
    return ref.split("/")[-1]


def iter_schema_refs(value):
    """Обходит схему и возвращает все ссылки $ref."""
    if isinstance(value, dict):
        ref = value.get("$ref")
        if ref is not None:
            yield ref
        for key, nested_value in value.items():
            if key != "$ref":
                yield from iter_schema_refs(nested_value)
    elif isinstance(value, list):
        for nested_value in value:
            yield from iter_schema_refs(nested_value)


def build_type_dependency_graph(schemas: dict) -> dict[str, set[str]]:
    """Строит граф локальных зависимостей и проверяет ссылки на типы."""
    graph = {name: set() for name in schemas}

    for schema_name, schema in schemas.items():
        for ref in iter_schema_refs(schema):
            if not isinstance(ref, str) or not ref.startswith(LOCAL_SCHEMA_REF_PREFIX):
                raise ValueError(
                    f"Unsupported schema ref in '{schema_name}': {ref!r}; "
                    f"expected '{LOCAL_SCHEMA_REF_PREFIX}<name>'"
                )

            dependency_name = ref[len(LOCAL_SCHEMA_REF_PREFIX):]
            if not dependency_name or "/" in dependency_name:
                raise ValueError(f"Invalid schema ref in '{schema_name}': '{ref}'")
            if dependency_name not in schemas:
                raise ValueError(
                    f"Unknown schema ref in '{schema_name}': '{dependency_name}'"
                )
            graph[schema_name].add(dependency_name)

    return graph


def order_schemas_by_dependencies(graph: dict[str, set[str]]) -> list[str]:
    """Возвращает зависимости перед потребителями, безопасно обходя циклы."""
    state = {}
    result = []

    def visit(schema_name: str):
        schema_state = state.get(schema_name, 0)
        if schema_state == 2:
            return
        if schema_state == 1:
            # Циклы типов внутри одного XSD допустимы и не требуют разворачивания.
            return

        state[schema_name] = 1
        for dependency_name in sorted(graph[schema_name]):
            visit(dependency_name)
        state[schema_name] = 2
        result.append(schema_name)

    for schema_name in sorted(graph):
        visit(schema_name)

    return result


def is_nullable(prop_name: str, required: list | None) -> bool:
    return not required or prop_name not in required


def array_occurs(schema: dict, context: str, allow_absent: bool = False) -> tuple[str, str]:
    """Преобразует стандартные minItems/maxItems в границы XSD."""
    min_items = schema.get("minItems", 0)
    max_items = schema.get("maxItems")

    for keyword, value in (("minItems", min_items), ("maxItems", max_items)):
        if value is not None and (
            isinstance(value, bool) or not isinstance(value, int) or value < 0
        ):
            raise ValueError(
                f"{keyword} должен быть неотрицательным целым: {context}"
            )

    if max_items is not None and min_items > max_items:
        raise ValueError(
            f"minItems ({min_items}) больше maxItems ({max_items}): {context}"
        )

    # Для плоского необязательного массива отсутствие свойства представляется нулём элементов.
    min_occurs = 0 if allow_absent else min_items
    max_occurs = "unbounded" if max_items is None else str(max_items)
    return str(min_occurs), max_occurs


def is_enum_schema(schema: dict) -> bool:
    return "enum" in schema and "properties" not in schema


def pascal_case(name: str) -> str:
    if not name:
        return name
    parts = re.split(r'[.\-_]', name)
    return ''.join(part[0].upper() + part[1:] for part in parts if part)


def order_element_attributes(element):
    """Устанавливает единый порядок атрибутов xs:element."""
    attributes = dict(element.attrib)
    element.attrib.clear()

    for name in ELEMENT_ATTRIBUTE_ORDER:
        if name in attributes:
            element.set(name, attributes.pop(name))

    for name, value in attributes.items():
        element.set(name, value)


def order_all_element_attributes(root):
    """Нормализует атрибуты всех элементов перед записью XSD."""
    element_tag = str(etree.QName(XSD_NS, "element"))
    for element in root.iter():
        if str(element.tag) == element_tag:
            order_element_attributes(element)


# ================== ELEMENT BUILDER ==================

class ElementBuilder:
    """Fluent-билдер для xs:element — убирает дублирование SubElement со словарями атрибутов."""

    def __init__(self, parent, name: str):
        self._parent = parent
        self._attrs: dict[str, str] = {"name": name}

    def type(self, t: str) -> "ElementBuilder":
        self._attrs["type"] = t
        return self

    def min_occurs(self, v: str) -> "ElementBuilder":
        self._attrs["minOccurs"] = v
        return self

    def max_occurs(self, v: str) -> "ElementBuilder":
        self._attrs["maxOccurs"] = v
        return self

    def nillable_if_nullable(self, prop_name: str, required: list | None) -> "ElementBuilder":
        if is_nullable(prop_name, required):
            self._attrs["nillable"] = "true"
        return self

    def min_occurs_if_not_required(self, prop_name: str, required: list | None) -> "ElementBuilder":
        if not required or prop_name not in required:
            self._attrs["minOccurs"] = "0"
        return self

    def build(self):
        element = etree.SubElement(
            self._parent,
            etree.QName(XSD_NS, "element"),
            **self._attrs
        )
        order_element_attributes(element)
        return element


def elem(parent, name: str) -> ElementBuilder:
    return ElementBuilder(parent, name)


# ================== SIMPLE TYPES ==================

def ensure_uuid_simple_type(root):
    if root.find(".//xs:simpleType[@name='UUID']", namespaces={"xs": XSD_NS}) is not None:
        return
    st = etree.SubElement(root, etree.QName(XSD_NS, "simpleType"), name="UUID")
    r = etree.SubElement(st, etree.QName(XSD_NS, "restriction"), base="xs:string")
    etree.SubElement(r, etree.QName(XSD_NS, "pattern"), value=UUID_PATTERN)


def infer_enum_type(values: list, context: str) -> str:
    """Определяет примитивный тип enum по его значениям."""
    if not values:
        raise ValueError(f"Нельзя определить тип пустого enum: {context}")

    value_types = set()
    for value in values:
        if isinstance(value, bool):
            value_types.add("boolean")
        elif isinstance(value, int):
            value_types.add("integer")
        elif isinstance(value, float):
            value_types.add("number")
        elif isinstance(value, str):
            value_types.add("string")
        else:
            raise ValueError(
                f"Неподдерживаемое значение enum {value!r}: {context}"
            )

    if value_types <= {"integer", "number"}:
        return "number" if "number" in value_types else "integer"
    if len(value_types) == 1:
        return next(iter(value_types))
    raise ValueError(f"Смешанные типы значений enum {sorted(value_types)}: {context}")


def create_enum_simple_type(root, name: str, schema: dict):
    if root.find(f".//xs:simpleType[@name='{name}']", namespaces={"xs": XSD_NS}) is not None:
        return

    values = schema.get("enum")
    if not isinstance(values, list):
        raise ValueError(f"Enum должен быть списком: {name}")

    value_type = schema.get("type") or infer_enum_type(values, name)
    if value_type == "boolean":
        raise ValueError(f"Boolean enum не поддерживается XSD 1.0: {name}")
    base = map_primitive({**schema, "type": value_type}, context=name)
    st = etree.SubElement(root, etree.QName(XSD_NS, "simpleType"), name=name)
    r = etree.SubElement(st, etree.QName(XSD_NS, "restriction"), base=base)
    for facet_name, value in primitive_facets(schema, base, name):
        etree.SubElement(r, etree.QName(XSD_NS, facet_name), value=value)
    for v in values:
        lexical_value = str(v).lower() if isinstance(v, bool) else str(v)
        etree.SubElement(r, etree.QName(XSD_NS, "enumeration"), value=lexical_value)


def multiple_of_fraction_digits(value, base: str, context: str) -> int | None:
    """Преобразует десятичный шаг 10^-N в fractionDigits."""
    if isinstance(value, bool):
        raise ValueError(f"multipleOf должен быть положительным числом: {context}")
    try:
        decimal_value = Decimal(str(value)).normalize()
    except (InvalidOperation, ValueError):
        raise ValueError(f"Некорректный multipleOf {value!r}: {context}") from None

    if not decimal_value.is_finite() or decimal_value <= 0:
        raise ValueError(f"multipleOf должен быть положительным числом: {context}")

    if base in ("xs:integer", "xs:int", "xs:long") and decimal_value == 1:
        return None
    if base != "xs:decimal":
        raise ValueError(
            f"multipleOf нельзя точно представить для базового типа {base}: {context}"
        )

    digits = decimal_value.as_tuple().digits
    exponent = decimal_value.as_tuple().exponent
    if digits != (1,) or exponent > 0:
        raise ValueError(
            f"multipleOf={value!r} нельзя точно представить через fractionDigits: {context}"
        )
    return -exponent


def primitive_facets(prop: dict, base: str, context: str = "") -> list[tuple[str, str]]:
    """Возвращает поддерживаемые ограничения примитивного типа."""
    prop_type = prop.get("type")
    facets = []

    if prop_type == "string" and base in ("xs:string", "tns:UUID"):
        for yaml_name, xsd_name in (
            ("minLength", "minLength"),
            ("maxLength", "maxLength"),
            ("pattern", "pattern"),
        ):
            if yaml_name in prop:
                facets.append((xsd_name, str(prop[yaml_name])))
    elif prop_type in ("integer", "number"):
        for bound_name, exclusive_name, inclusive_facet, exclusive_facet in (
            ("minimum", "exclusiveMinimum", "minInclusive", "minExclusive"),
            ("maximum", "exclusiveMaximum", "maxInclusive", "maxExclusive"),
        ):
            bound = prop.get(bound_name)
            exclusive = prop.get(exclusive_name)

            if isinstance(exclusive, bool):
                if bound is None and exclusive:
                    raise ValueError(
                        f"{exclusive_name}=true требует {bound_name}: {context}"
                    )
                if bound is not None:
                    facet_name = exclusive_facet if exclusive else inclusive_facet
                    facets.append((facet_name, str(bound)))
            else:
                if bound is not None:
                    facets.append((inclusive_facet, str(bound)))
                if exclusive is not None:
                    facets.append((exclusive_facet, str(exclusive)))

        if "multipleOf" in prop:
            fraction_digits = multiple_of_fraction_digits(
                prop["multipleOf"],
                base,
                context,
            )
            if fraction_digits is not None:
                facets.append(("fractionDigits", str(fraction_digits)))

    return facets


def append_primitive_type(element, prop: dict, context: str):
    """Задаёт встроенный тип или локальный simpleType с ограничениями из YAML."""
    base = map_primitive(prop, context=context)
    facets = primitive_facets(prop, base, context)

    if not facets:
        element.set("type", base)
        order_element_attributes(element)
        return

    simple_type = etree.SubElement(element, etree.QName(XSD_NS, "simpleType"))
    restriction = etree.SubElement(
        simple_type,
        etree.QName(XSD_NS, "restriction"),
        base=base,
    )
    for facet_name, value in facets:
        etree.SubElement(
            restriction,
            etree.QName(XSD_NS, facet_name),
            value=value,
        )


# ================== TYPE MAPPING ==================

def map_primitive(prop: dict, context: str = "") -> str:
    """Сопоставляет примитив AsyncAPI со встроенным типом XSD."""
    t = prop.get("type")
    f = prop.get("format")

    if t == "string":
        return {
            "uuid": "tns:UUID",
            "date-time": "xs:dateTime",
            "date": "xs:date",
            "time": "xs:time",
        }.get(f, "xs:string")
    if t == "integer":
        return {
            "int32": "xs:int",
            "int64": "xs:long",
        }.get(f, "xs:integer")
    if t == "number":
        return {
            "float": "xs:float",
            "double": "xs:double",
        }.get(f, "xs:decimal")
    if t == "boolean":
        return "xs:boolean"

    raise ValueError(
        f"Неподдерживаемый примитивный тип {t!r}"
        + (f": {context}" if context else "")
    )


# ================== SCHEMA ROOT ==================

def create_schema_root(target_ns: str):
    return etree.Element(
        etree.QName(XSD_NS, "schema"),
        nsmap={"xs": XSD_NS, "tns": target_ns},
        attrib={
            "targetNamespace": target_ns,
            "elementFormDefault": "qualified",
            "attributeFormDefault": "unqualified",
        }
    )


# ================== PROPERTY PROCESSORS ==================

def _process_enum_property(root, seq, prop_name: str, prop: dict, type_name: str, required: list):
    enum_type = f"{type_name}.{pascal_case(prop_name)}"
    create_enum_simple_type(root, enum_type, prop)
    (
        elem(seq, prop_name)
        .type(f"tns:{enum_type}")
        .nillable_if_nullable(prop_name, required)
        .build()
    )


def _process_ref_property(root, seq, prop_name: str, prop: dict, required: list, schemas: dict, channel_map: dict):
    ref_schema_name = ref_name(prop["$ref"])
    ref_schema = schemas.get(ref_schema_name)
    if not ref_schema:
        raise ValueError(f"Unknown schema ref: '{ref_schema_name}'")

    resolved_name = resolve_schema_type_name(ref_schema_name, channel_map)

    if is_enum_schema(ref_schema):
        create_enum_simple_type(root, resolved_name, ref_schema)
        (
            elem(seq, prop_name)
            .type(f"tns:{resolved_name}")
            .nillable_if_nullable(prop_name, required)
            .build()
        )
    else:
        (
            elem(seq, prop_name)
            .type(f"tns:{resolved_name}")
            .nillable_if_nullable(prop_name, required)
            .build()
        )


def _process_array_property(root, seq, prop_name: str, prop: dict, type_name: str, required: list, schemas: dict, channel_map: dict, created: set):
    items = prop.get("items")
    if not items:
        raise ValueError(f"Array '{type_name}.{prop_name}' has no items")

    context = f"{type_name}.{prop_name}"
    min_occurs, max_occurs = array_occurs(
        prop,
        context,
        allow_absent=is_nullable(prop_name, required),
    )

    if "$ref" in items:
        ref_schema_name = ref_name(items["$ref"])
        ref_schema = schemas.get(ref_schema_name)
        if not ref_schema:
            raise ValueError(f"Unknown array item schema ref: '{ref_schema_name}'")

        resolved_name = resolve_schema_type_name(ref_schema_name, channel_map)
        if is_enum_schema(ref_schema):
            create_enum_simple_type(root, resolved_name, ref_schema)

        (
            elem(seq, prop_name)
            .type(f"tns:{resolved_name}")
            .min_occurs(min_occurs)
            .max_occurs(max_occurs)
            .build()
        )
        return

    if items.get("type") != "object":
        array_element = (
            elem(seq, prop_name)
            .min_occurs(min_occurs)
            .max_occurs(max_occurs)
            .build()
        )
        append_primitive_type(array_element, items, context)
        return

    table_type = f"{type_name}.{pascal_case(prop_name)}"
    row_type = f"{table_type}.{ROW_SUFFIX}"

    create_complex_type(root, row_type, items, schemas, channel_map, created)

    tct = etree.SubElement(root, etree.QName(XSD_NS, "complexType"), name=table_type)
    tseq = etree.SubElement(tct, etree.QName(XSD_NS, "sequence"))
    row_min_occurs, row_max_occurs = array_occurs(prop, context)
    (
        elem(tseq, "row")
        .type(f"tns:{row_type}")
        .min_occurs(row_min_occurs)
        .max_occurs(row_max_occurs)
        .build()
    )

    (
        elem(seq, prop_name)
        .type(f"tns:{table_type}")
        .min_occurs_if_not_required(prop_name, required)
        .build()
    )


def _process_object_property(root, seq, prop_name: str, prop: dict, type_name: str, required: list, schemas: dict, channel_map: dict, created: set):
    nested = f"{type_name}.{pascal_case(prop_name)}"
    create_complex_type(root, nested, prop, schemas, channel_map, created)
    (
        elem(seq, prop_name)
        .type(f"tns:{nested}")
        .nillable_if_nullable(prop_name, required)
        .build()
    )


def _process_primitive_property(seq, prop_name: str, prop: dict, type_name: str, required: list):
    context = f"{type_name}.{prop_name}"
    builder = (
        elem(seq, prop_name)
        .nillable_if_nullable(prop_name, required)
    )
    primitive_element = builder.build()
    append_primitive_type(primitive_element, prop, context)


# ================== COMPLEX TYPES ==================

def create_complex_type(root, type_name: str, schema: dict, schemas: dict, channel_map: dict, created: set):
    if type_name in created or is_enum_schema(schema):
        return

    created.add(type_name)

    ct = etree.SubElement(root, etree.QName(XSD_NS, "complexType"), name=type_name)
    seq = etree.SubElement(ct, etree.QName(XSD_NS, "sequence"))

    if schema.get("type") == "array":
        items = schema.get("items")
        if not items:
            raise ValueError(f"Array '{type_name}' has no items")

        context = f"{type_name}.row"
        min_occurs, max_occurs = array_occurs(schema, type_name)
        if "$ref" in items:
            ref_schema_name = ref_name(items["$ref"])
            ref_schema = schemas.get(ref_schema_name)
            if not ref_schema:
                raise ValueError(f"Unknown array item schema ref: '{ref_schema_name}'")

            resolved_name = resolve_schema_type_name(ref_schema_name, channel_map)
            if is_enum_schema(ref_schema):
                create_enum_simple_type(root, resolved_name, ref_schema)
            (
                elem(seq, "row")
                .type(f"tns:{resolved_name}")
                .min_occurs(min_occurs)
                .max_occurs(max_occurs)
                .build()
            )
        elif items.get("type") == "object":
            row_type = f"{type_name}.{ROW_SUFFIX}"
            create_complex_type(root, row_type, items, schemas, channel_map, created)
            (
                elem(seq, "row")
                .type(f"tns:{row_type}")
                .min_occurs(min_occurs)
                .max_occurs(max_occurs)
                .build()
            )
        else:
            row_element = (
                elem(seq, "row")
                .min_occurs(min_occurs)
                .max_occurs(max_occurs)
                .build()
            )
            append_primitive_type(row_element, items, context)
        return

    required = schema.get("required", [])

    for prop_name, prop in schema.get("properties", {}).items():
        try:
            if "enum" in prop:
                _process_enum_property(root, seq, prop_name, prop, type_name, required)
            elif "$ref" in prop:
                _process_ref_property(root, seq, prop_name, prop, required, schemas, channel_map)
            elif prop.get("type") == "array":
                _process_array_property(root, seq, prop_name, prop, type_name, required, schemas, channel_map, created)
            elif prop.get("type") == "object":
                _process_object_property(root, seq, prop_name, prop, type_name, required, schemas, channel_map, created)
            else:
                _process_primitive_property(seq, prop_name, prop, type_name, required)
        except ValueError as e:
            raise ValueError(f"[{type_name}.{prop_name}] {e}") from e


def order_type_declarations(root):
    """Сортирует общие и персональные simpleType, затем complexType."""
    order = {
        str(etree.QName(XSD_NS, "simpleType")): 0,
        str(etree.QName(XSD_NS, "complexType")): 1,
    }
    indexed_nodes = list(enumerate(root))

    def sort_key(indexed_node):
        index, node = indexed_node
        type_order = order.get(str(node.tag), 2)
        name = node.get("name", "")
        if type_order == 0:
            if name == "UUID":
                simple_type_order = 0
            elif "." not in name:
                simple_type_order = 1
            else:
                simple_type_order = 2
            return type_order, simple_type_order, name, index
        if type_order == 1:
            return type_order, 0, name, index
        return type_order, 0, "", index

    root[:] = [node for _, node in sorted(indexed_nodes, key=sort_key)]


# ================== MAIN ==================

def convert_schemas_to_xsd(asyncapi_yaml_path: str, target_ns: str, output_path: str,
                           prefix: str = "", suffix: str = ""):
    with open(asyncapi_yaml_path, encoding="utf-8") as f:
        spec = yaml.safe_load(f)

    schemas = spec.get("components", {}).get("schemas", {})
    if not schemas:
        raise ValueError("components.schemas is empty")

    channel_map = build_channel_type_map(spec, prefix, suffix)
    dependency_graph = build_type_dependency_graph(schemas)
    schema_order = order_schemas_by_dependencies(dependency_graph)

    root = create_schema_root(target_ns)
    ensure_uuid_simple_type(root)

    # Сначала все enum'ы на верхнем уровне
    for name in schema_order:
        schema = schemas[name]
        if is_enum_schema(schema):
            create_enum_simple_type(
                root,
                resolve_schema_type_name(name, channel_map),
                schema
            )

    # Затем все complexType
    created = set()
    for name in schema_order:
        schema = schemas[name]
        create_complex_type(
            root,
            resolve_schema_type_name(name, channel_map),
            schema,
            schemas,
            channel_map,
            created
        )

    order_type_declarations(root)

    order_all_element_attributes(root)
    etree.ElementTree(root).write(
        output_path,
        pretty_print=True,
        xml_declaration=True,
        encoding="UTF-8"
    )


# ================== ENTRYPOINT ==================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert AsyncAPI YAML to XSD schema",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python asyncapi2xsd_v5.py spec.yaml out.xsd -n http://example.com/ns\n"
            "  python asyncapi2xsd_v5.py spec.yaml out.xsd -n http://example.com/ns "
            "--prefix 1c. --suffix .changed"
        ),
    )
    parser.add_argument("input", help="Path to AsyncAPI YAML file")
    parser.add_argument("output", help="Path to output XSD file")
    parser.add_argument("-n", "--namespace", required=True, help="Target XML namespace (targetNamespace)")
    parser.add_argument("--prefix", default="", help="Channel address prefix to strip when deriving type names")
    parser.add_argument("--suffix", default="", help="Channel address suffix to strip when deriving type names")
    args = parser.parse_args()

    convert_schemas_to_xsd(args.input, args.namespace, args.output, args.prefix, args.suffix)
