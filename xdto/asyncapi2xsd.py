import argparse
import yaml
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


# ================== HELPERS ==================

def extract_type_name_from_address(address: str, prefix: str, suffix: str) -> str:
    """crm.typesNonTargetActivities.changed -> TypesNonTargetActivities"""
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


def maybe_nillable(prop_name: str, required: list | None) -> dict:
    if not required or prop_name not in required:
        return {"nillable": "true"}
    return {}


def is_enum_schema(schema: dict) -> bool:
    return "enum" in schema and "properties" not in schema


def pascal_case(name: str) -> str:
    if not name:
        return name
    return name[0].upper() + name[1:]


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

    def nillable_if_optional(self, prop_name: str, required: list | None) -> "ElementBuilder":
        self._attrs.update(maybe_nillable(prop_name, required))
        return self

    def build(self):
        return etree.SubElement(
            self._parent,
            etree.QName(XSD_NS, "element"),
            **self._attrs
        )


def elem(parent, name: str) -> ElementBuilder:
    return ElementBuilder(parent, name)


# ================== SIMPLE TYPES ==================

def ensure_uuid_simple_type(root):
    if root.find(".//xs:simpleType[@name='UUID']", namespaces={"xs": XSD_NS}) is not None:
        return
    st = etree.SubElement(root, etree.QName(XSD_NS, "simpleType"), name="UUID")
    r = etree.SubElement(st, etree.QName(XSD_NS, "restriction"), base="xs:string")
    etree.SubElement(r, etree.QName(XSD_NS, "pattern"), value=UUID_PATTERN)


def create_enum_simple_type(root, name: str, values: list, base: str = "xs:string"):
    if root.find(f".//xs:simpleType[@name='{name}']", namespaces={"xs": XSD_NS}) is not None:
        return
    st = etree.SubElement(root, etree.QName(XSD_NS, "simpleType"), name=name)
    r = etree.SubElement(st, etree.QName(XSD_NS, "restriction"), base=base)
    for v in values:
        etree.SubElement(r, etree.QName(XSD_NS, "enumeration"), value=str(v))


# ================== TYPE MAPPING ==================

def map_primitive(prop: dict, context: str = "") -> str:
    t = prop.get("type")
    f = prop.get("format")
    min_len = prop.get("minLength")
    max_len = prop.get("maxLength")

    if t == "string":
        if f == "uuid":
            return "tns:UUID"
        if f == "date-time":
            return "xs:dateTime"
        if f == "date":
            return "xs:date"
        if f == "time":
            return "xs:time"
        if max_len == 36 or min_len == 36:
            return "tns:UUID"
        return "xs:string"
    if t == "integer":
        return "xs:int"
    if t == "number":
        return "xs:decimal"
    if t == "boolean":
        return "xs:boolean"

    raise ValueError(f"Unsupported primitive type: '{t}'" + (f" in {context}" if context else ""))


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
    create_enum_simple_type(root, enum_type, prop["enum"])
    (
        elem(seq, prop_name)
        .type(f"tns:{enum_type}")
        .min_occurs("0")
        .nillable_if_optional(prop_name, required)
        .build()
    )


def _process_ref_property(root, seq, prop_name: str, prop: dict, required: list, schemas: dict, channel_map: dict):
    ref_schema_name = ref_name(prop["$ref"])
    ref_schema = schemas.get(ref_schema_name)
    if not ref_schema:
        raise ValueError(f"Unknown schema ref: '{ref_schema_name}'")

    resolved_name = resolve_schema_type_name(ref_schema_name, channel_map)

    if is_enum_schema(ref_schema):
        create_enum_simple_type(root, resolved_name, ref_schema["enum"])
        (
            elem(seq, prop_name)
            .type(f"tns:{resolved_name}")
            .min_occurs("0")
            .nillable_if_optional(prop_name, required)
            .build()
        )
    else:
        (
            elem(seq, prop_name)
            .type(f"tns:{resolved_name}")
            .nillable_if_optional(prop_name, required)
            .build()
        )


def _process_array_property(root, seq, prop_name: str, prop: dict, type_name: str, required: list, schemas: dict, channel_map: dict, created: set):
    items = prop.get("items")
    if not items:
        raise ValueError(f"Array '{type_name}.{prop_name}' has no items")

    context = f"{type_name}.{prop_name}"

    if items.get("type") != "object":
        (
            elem(seq, prop_name)
            .type(map_primitive(items, context=context))
            .min_occurs("0")
            .max_occurs("unbounded")
            .nillable_if_optional(prop_name, required)
            .build()
        )
        return

    table_type = f"{type_name}.{pascal_case(prop_name)}"
    row_type = f"{table_type}.{ROW_SUFFIX}"

    create_complex_type(root, row_type, items, schemas, channel_map, created)

    tct = etree.SubElement(root, etree.QName(XSD_NS, "complexType"), name=table_type)
    tseq = etree.SubElement(tct, etree.QName(XSD_NS, "sequence"))
    elem(tseq, "row").type(f"tns:{row_type}").max_occurs("unbounded").build()

    (
        elem(seq, prop_name)
        .type(f"tns:{table_type}")
        .min_occurs("0")
        .nillable_if_optional(prop_name, required)
        .build()
    )


def _process_object_property(root, seq, prop_name: str, prop: dict, type_name: str, required: list, schemas: dict, channel_map: dict, created: set):
    nested = f"{type_name}.{pascal_case(prop_name)}"
    create_complex_type(root, nested, prop, schemas, channel_map, created)
    (
        elem(seq, prop_name)
        .type(f"tns:{nested}")
        .nillable_if_optional(prop_name, required)
        .build()
    )


def _process_primitive_property(seq, prop_name: str, prop: dict, type_name: str, required: list):
    (
        elem(seq, prop_name)
        .type(map_primitive(prop, context=f"{type_name}.{prop_name}"))
        .nillable_if_optional(prop_name, required)
        .build()
    )


# ================== COMPLEX TYPES ==================

def create_complex_type(root, type_name: str, schema: dict, schemas: dict, channel_map: dict, created: set):
    if type_name in created or is_enum_schema(schema):
        return

    created.add(type_name)

    required = schema.get("required", [])
    ct = etree.SubElement(root, etree.QName(XSD_NS, "complexType"), name=type_name)
    seq = etree.SubElement(ct, etree.QName(XSD_NS, "sequence"))

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


# ================== MAIN ==================

def convert_schemas_to_xsd(asyncapi_yaml_path: str, target_ns: str, output_path: str,
                           prefix: str = "", suffix: str = ""):
    with open(asyncapi_yaml_path, encoding="utf-8") as f:
        spec = yaml.safe_load(f)

    schemas = spec.get("components", {}).get("schemas", {})
    if not schemas:
        raise ValueError("components.schemas is empty")

    channel_map = build_channel_type_map(spec, prefix, suffix)

    root = create_schema_root(target_ns)
    ensure_uuid_simple_type(root)

    # Сначала все enum'ы на верхнем уровне
    for name, schema in schemas.items():
        if is_enum_schema(schema):
            create_enum_simple_type(
                root,
                resolve_schema_type_name(name, channel_map),
                schema["enum"]
            )

    # Затем все complexType
    created = set()
    for name, schema in schemas.items():
        create_complex_type(
            root,
            resolve_schema_type_name(name, channel_map),
            schema,
            schemas,
            channel_map,
            created
        )

    etree.ElementTree(root).write(
        output_path,
        pretty_print=True,
        xml_declaration=True,
        encoding="utf-8"
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
            "--prefix crm. --suffix .changed"
        ),
    )
    parser.add_argument("input", help="Path to AsyncAPI YAML file")
    parser.add_argument("output", help="Path to output XSD file")
    parser.add_argument("-n", "--namespace", required=True, help="Target XML namespace (targetNamespace)")
    parser.add_argument("--prefix", default="", help="Channel address prefix to strip when deriving type names")
    parser.add_argument("--suffix", default="", help="Channel address suffix to strip when deriving type names")
    args = parser.parse_args()

    convert_schemas_to_xsd(args.input, args.namespace, args.output, args.prefix, args.suffix)
