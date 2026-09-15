"""Contract regressions for the YAML profile and its XSD representation."""

import copy
import subprocess
import sys
import tempfile
import unittest
import warnings
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

from lxml import etree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asyncapi2xsd import SchemaWarning, SchemaError, convert_file, generate_xsd, load_document

NS = "urn:kafka:generator:test"
XS = {"xs": "http://www.w3.org/2001/XMLSchema"}
SCRIPT = Path(__file__).resolve().parent / "asyncapi2xsd.py"


def obj(fields, required=(), **annotations):
    return {"type": "object", "properties": fields, "required": list(required), **annotations}


def document(**schemas):
    return {"components": {"schemas": schemas}}


def ref(name):
    return {"$ref": "#/components/schemas/" + name}


def tree(spec, **options):
    return etree.fromstring(generate_xsd(spec, NS, **options))


def validator(spec, name="A"):
    root = tree(spec)
    etree.SubElement(root, "{" + XS["xs"] + "}element", name="Root", type="tns:" + name)
    return etree.XMLSchema(root)


def instance(text):
    return etree.fromstring((f'<Root xmlns="{NS}">' + text + '</Root>').encode())


def nil_field(name):
    return f'<{name} xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>'


class GeneratorTests(unittest.TestCase):
    def test_type_declaration_order(self):
        spec = document(
            Zulu={"type": "string"}, Alpha={"type": "integer"},
            ZObject=obj({"value": {"type": "string"}}),
            AObject=obj({"second": {"type": "string"}, "first": {"type": "string"},
                         "id": {"type": "string", "format": "uuid"}}))
        root = tree(spec)
        self.assertEqual(
            ["UUID", "Alpha", "Zulu", "AObject.First", "AObject.Second", "ZObject.Value", "AObject", "ZObject"],
            [element.get("name") for element in root])
        self.assertEqual(["second", "first", "id"], root.xpath(
            "//xs:complexType[@name='AObject']/xs:sequence/xs:element/@name", namespaces=XS))
        spec["components"]["schemas"] = dict(reversed(list(spec["components"]["schemas"].items())))
        self.assertEqual(etree.tostring(root), etree.tostring(tree(spec)))

    def rejects(self, spec, category=None):
        with self.assertRaises(SchemaError) as caught:
            generate_xsd(spec, NS)
        if category:
            self.assertEqual(category, caught.exception.category)
        return caught.exception

    def test_minimal_optional_and_required(self):
        spec = document(A=obj({"id": {"type": "integer"}, "comment": {"type": "string"}}, ["id"]))
        root = tree(spec)
        fields = root.xpath("//xs:complexType[@name='A']//xs:element", namespaces=XS)
        self.assertEqual(["1", "1"], [v.get("minOccurs", "1") for v in fields])
        self.assertEqual(["false", "true"], [v.get("nillable", "false") for v in fields])
        valid = validator(spec)
        self.assertFalse(valid.validate(instance("<id>0</id>")))
        self.assertTrue(valid.validate(instance("<id>0</id>" + nil_field("comment"))))
        self.assertFalse(valid.validate(instance("")))
        self.assertTrue(valid.validate(instance('<id>1</id><comment xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>')))

    def test_common_primitive_reference_preserves_facets(self):
        spec = document(Code={"type": "string", "minLength": 2}, A=obj({"code": ref("Code")}, ["code"]))
        root = tree(spec)
        self.assertEqual([], root.xpath("//xs:complexType[@name='Code']", namespaces=XS))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<code>AB</code>")))
        self.assertFalse(valid.validate(instance("<code>A</code>")))

    def test_alias_reuses_identity(self):
        root = tree(document(A={"type": "string"}, Alias=ref("A"), Consumer=obj({"value": ref("Alias")})))
        self.assertEqual([], root.xpath("//*[@name='Alias']"))
        self.assertEqual(["tns:A"], root.xpath("//xs:element[@name='value']/@type", namespaces=XS))

    def test_alias_cycle(self):
        self.rejects(document(A=ref("B"), B=ref("A")), "alias-cycle")

    def test_alias_in_optional_object_recursion(self):
        root = tree(document(Alias=ref("ОбщиеСвойстваNode"), ОбщиеСвойстваNode=obj({"parent": ref("Alias")})))
        self.assertEqual(1, len(root.xpath("//xs:complexType", namespaces=XS)))

    def test_channel_name_of_alias_is_applied_to_target(self):
        spec = document(Base=obj({}), Alias=ref("Base"))
        spec["channels"] = {"one": {"address": "crm.order.changed", "messages": {"inline": {"payload": ref("Alias")}}}}
        self.assertEqual(["Order"], tree(spec, prefix="crm.", suffix=".changed").xpath("//xs:complexType/@name", namespaces=XS))

    def test_required_containment_cycle(self):
        self.rejects(document(ОбщиеСвойстваA=obj({"next": ref("ОбщиеСвойстваA")}, ["next"])), "object-cycle")

    def test_reference_depth_limit(self):
        schemas = {f"ОбщиеСвойстваN{i}": obj({"next": ref(f"ОбщиеСвойстваN{i+1}")}) for i in range(110)}
        schemas["ОбщиеСвойстваN110"] = obj({})
        self.rejects({"components": {"schemas": schemas}}, "limit")

    def test_uuid_shared_type_and_strict_shape(self):
        spec = document(UUID={"type": "string", "format": "uuid"}, A=obj({"id": ref("UUID"), "other": {"type": "string", "format": "uuid"}}, ["id"]))
        root = tree(spec)
        self.assertEqual(1, len(root.xpath("//xs:simpleType[@name='UUID']", namespaces=XS)))
        valid = validator(spec)
        uuid = "11111111-1111-1111-1111-111111111111"
        self.assertTrue(valid.validate(instance(f"<id>{uuid}</id>" + nil_field("other"))))
        self.assertFalse(valid.validate(instance(f"<id>x{uuid}x</id>")))
        self.assertFalse(valid.validate(instance("<id>not-a-uuid</id>")))

    def test_uuid_name_collision(self):
        self.rejects(document(UUID={"type": "string"}, A=obj({"id": {"type": "string", "format": "uuid"}})), "name-conflict")

    def test_inline_group_gets_semantic_name(self):
        root = tree(document(A=obj({"address": obj({"city": {"type": "string"}, "zip": {"type": "string"}})})))
        self.assertEqual(["tns:A.Address"], root.xpath("//xs:element[@name='address']/@type", namespaces=XS))

    def test_referenced_plain_group_gets_shared_identity(self):
        root = tree(document(Address=obj({"city": {"type": "string"}}), A=obj({"address": ref("Address")})))
        self.assertEqual(["tns:Address"], root.xpath("//xs:element[@name='address']/@type", namespaces=XS))
        self.assertEqual(1, len(root.xpath("xs:complexType[@name='Address']", namespaces=XS)))

    def test_canonical_table_has_one_wrapper(self):
        spec = document(Lines=obj({"entry": {"type": "array", "items": ref("Line"), "maxItems": 3}}), Line=obj({"quantity": {"type": "number"}}, ["quantity"]), A=obj({"lines": ref("Lines")}))
        root = tree(spec)
        self.assertEqual(["tns:Line"], root.xpath("//xs:complexType[@name='Lines']//xs:element/@type", namespaces=XS))
        self.assertEqual([], root.xpath("//xs:complexType[@name='Lines.Row']", namespaces=XS))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<lines/>")))
        self.assertTrue(valid.validate(instance(nil_field("lines"))))
        self.assertTrue(valid.validate(instance("<lines><entry><quantity>1</quantity></entry></lines>")))
        self.assertFalse(valid.validate(instance("<lines><entry/></lines>")))
        self.assertFalse(valid.validate(instance("<lines>" + "<entry><quantity>1</quantity></entry>" * 4 + "</lines>")))

    def test_required_rows_cardinality(self):
        spec = document(A=obj({"row": {"type": "array", "minItems": 1, "maxItems": 2, "items": obj({"name": {"type": "string"}})}}, ["row"]))
        valid = validator(spec)
        self.assertFalse(valid.validate(instance("")))
        self.assertTrue(valid.validate(instance("<row><name>one</name></row>")))

    def test_unrepresentable_collections_rejected(self):
        for limit in (True, -1):
            with self.subTest(limit=limit):
                self.rejects(document(A=obj({"row": {"type": "array", "maxItems": limit, "items": obj({})}})))
        self.rejects(document(A={"type": "array", "items": {"type": "array", "items": obj({})}}), "representation")

    def test_inline_enum_in_table_row(self):
        spec = document(A=obj({"row": {"type": "array", "items": obj({"kind": {"type": "string", "enum": ["one", "two"]}}, ["kind"])}}))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<row><kind>one</kind></row>")))
        self.assertFalse(valid.validate(instance("<row><kind>other</kind></row>")))

    def test_simple_lists_among_properties(self):
        spec = document(A=obj({"id": {"type": "string"}, "tags": {"type": "array", "items": {"type": "string", "maxLength": 50}}, "fixedTags": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "string", "minLength": 2, "maxLength": 30}}}, ["fixedTags"]))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance(nil_field("id") + nil_field("tags") + "<fixedTags>ab</fixedTags>")))
        self.assertFalse(valid.validate(instance("")))
        self.assertFalse(valid.validate(instance("<fixedTags>a</fixedTags>")))
        self.assertFalse(valid.validate(instance("<fixedTags>ab</fixedTags>" * 4)))
        self.assertFalse(valid.validate(instance("<tags>" + "x" * 51 + "</tags><fixedTags>ab</fixedTags>")))

    def test_legacy_document_collection_definitions(self):
        legacy = load_document(SCRIPT.parent.parent / "examples" / "asyncapi_example.yaml")
        source = legacy["components"]["schemas"]["TestDocumentPayload"]
        fields = {key: source["properties"][key] for key in ("tags", "fixedTags", "lines")}
        spec = document(A=obj(fields, ["fixedTags", "lines"]), LineStatus=legacy["components"]["schemas"]["LineStatus"])
        root = etree.fromstring(generate_xsd(spec, NS))
        self.assertEqual(root.xpath("string(xs:complexType[@name='A']/xs:sequence/xs:element[@name='fixedTags']/@maxOccurs)", namespaces=XS), "3")
        self.assertEqual(root.xpath("string(xs:complexType[@name='A.Lines']/xs:sequence/xs:element[@name='row']/@maxOccurs)", namespaces=XS), "100")

    def test_table_among_properties_and_json_examples(self):
        spec = document(A=obj({"id": {"type": "string"}, "lines": {"type": "array", "minItems": 1, "maxItems": 2, "items": obj({"quantity": {"type": "integer"}}, ["quantity"]), "examples": [[{"quantity": 1}]]}}, ["lines"], examples=[{"lines": [{"quantity": 1}]}]))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance(nil_field("id") + "<lines><row><quantity>1</quantity></row></lines>")))
        self.assertFalse(valid.validate(instance("")))
        self.assertFalse(valid.validate(instance("<lines/>")))
        self.assertFalse(valid.validate(instance("<lines>" + "<row><quantity>1</quantity></row>" * 3 + "</lines>")))
        spec["components"]["schemas"]["A"]["examples"] = [{"lines": []}]
        self.rejects(spec, "value")

    def test_multiple_tables_have_distinct_row_types(self):
        spec = document(A=obj({"first": {"type": "array", "items": obj({"name": {"type": "string"}})}, "second": {"type": "array", "items": obj({"count": {"type": "integer"}})}}))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<first><row><name>a</name></row></first><second><row><count>2</count></row></second>")))

    def test_simple_enum_list_and_array_annotations(self):
        spec = document(Code={"type": "string", "enum": ["one", "two"]}, A=obj({"tags": {"type": "array", "items": ref("Code"), "default": ["one"], "examples": [["two"]]}}))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<tags>one</tags><tags>two</tags>")))
        self.assertFalse(valid.validate(instance("<tags>other</tags>")))
        spec["components"]["schemas"]["A"]["properties"]["tags"]["default"] = ["other"]
        self.rejects(spec, "value")

    def test_enum_and_annotations(self):
        root = tree(document(State={"type": "string", "enum": ["new", "done"], "x-enumNames": ["New", "Done"]}))
        self.assertEqual(["new", "done"], root.xpath("//xs:enumeration/@value", namespaces=XS))
        for schema in ({"type": "integer", "enum": ["wrong"]}, {"type": "string", "enum": []},
                       {"type": "string", "enum": ["a", "a"]}, {"type": "string", "enum": ["a"], "x-enumNames": []}):
            self.rejects(document(A=schema))

    def test_integer_accepts_integral_decimal_values(self):
        tree(document(A={"type": "integer", "enum": [Decimal("1.0"), 2], "default": Decimal("1.00")}))
        self.rejects(document(A={"type": "integer", "enum": [Decimal("1.1")]}), "value")

    def test_name_collisions(self):
        self.rejects({"components": {"schemas": {"order-details": obj({}), "order_details": obj({})}}}, "name-conflict")
        self.rejects(document(A=obj({"some-name": {"type": "string"}, "some_name": {"type": "integer"}})), "name-conflict")

    def test_unknown_keywords_formats_and_wrong_required(self):
        for schema in ({"allOf": [ref("A")]}, {"type": "string", "const": "fixed"},
                       {"type": "string", "format": "custom"}, {"type": ["string", "null"]},
                       {"type": "object", "properties": {}, "additionalProperties": True},
                       {"type": "string", "minimum": 1}):
            self.rejects(document(A=schema))
        for required in (["missing"], ["value", "value"], "value", [True]):
            self.rejects(document(A=obj({"value": {"type": "string"}}, required) if isinstance(required, list) else {"type": "object", "properties": {}, "required": required}), "required")

    def test_refs_in_annotations_are_not_dependencies(self):
        tree(document(A=obj({"literal": {"type": "string"}}, examples=[{"literal": "#/components/schemas/NotAType"}], **{"x-data": {"$ref": "https://example.invalid"}})))

    def test_unsupported_or_unknown_reference(self):
        for value in ("https://example.invalid/A", "#/components/messages/A", "#/components/schemas/missing"):
            self.rejects(document(A=obj({"value": {"$ref": value}})), "reference")

    def test_decimal_precision_and_integer_bounds(self):
        huge = Decimal("1234567890.123456789012")
        root = tree(document(A={"type": "number", "minimum": huge, "multipleOf": Decimal("0.0100")}))
        self.assertEqual([str(huge)], root.xpath("//xs:minInclusive/@value", namespaces=XS))
        self.assertEqual(["2"], root.xpath("//xs:fractionDigits/@value", namespaces=XS))
        spec = document(A={"type": "integer", "exclusiveMinimum": Decimal("1.5"), "maximum": Decimal("3.8")})
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("2")))
        self.assertFalse(valid.validate(instance("1")))
        self.rejects(document(A={"type": "integer", "minimum": Decimal("0.1"), "maximum": Decimal("0.9")}), "facet")

    def test_invalid_facets_and_nonexact_step(self):
        for schema in ({"type": "number", "minimum": True}, {"type": "number", "minimum": 2, "maximum": 1},
                       {"type": "string", "minLength": -1}, {"type": "string", "minLength": 2, "maxLength": 1},
                       {"type": "number", "multipleOf": Decimal("0.05")},
                       {"type": "integer", "minimum": 0, "exclusiveMinimum": 1}):
            self.rejects(document(A=schema))

    def test_portable_regex_preserves_search(self):
        spec = document(A={"type": "string", "pattern": "[A-Z]{2}"})
        valid = validator(spec)
        for value in ("AB", "zABz", "\nAB\n"):
            self.assertTrue(valid.validate(instance(value)), value)
        self.assertFalse(valid.validate(instance("Ab")))
        for pattern in (".+", "(a|b)", r"\w+", "[z-a]", "a+?"):
            self.rejects(document(A={"type": "string", "pattern": pattern}), "pattern")

    def test_anchored_patterns(self):
        valid = validator(document(A=obj({"code": {"type": "string", "pattern": "^[A-Z]{2}$"}})))
        for text in ("AB",):
            self.assertTrue(valid.validate(instance(f"<code>{text}</code>")))
        for text in ("xAB", "ABx", "A", "AB\n", "AB\u2028", "AB\n\n"):
            self.assertFalse(valid.validate(instance(f"<code>{text}</code>")))

    def test_closed_objects_and_email_annotation(self):
        spec = document(A=obj({"email": {"type": "string", "format": "email", "maxLength": 3}}, additionalProperties=False, examples=[{"email": "a@b"}]))
        root = tree(spec)
        self.assertIn("format: email", " ".join(root.xpath("//xs:documentation/text()", namespaces=XS)))
        spec["components"]["schemas"]["A"]["examples"] = [{"email": "a@b", "extra": 1}]
        self.rejects(spec, "value")

    def test_documentation_uses_trimmed_title(self):
        root = tree(document(A={"type": "string", "title": " Заголовок\n ", "description": " Описание\n\n  в несколько\nстрок "}))
        self.assertEqual(["Заголовок"], root.xpath("//xs:documentation/text()", namespaces=XS))

    def test_documentation_falls_back_to_trimmed_description(self):
        for title in ("", " \n\t "):
            root = tree(document(A={"type": "string", "title": title, "description": " Описание\n\n  в несколько\nстрок "}))
            self.assertEqual(["Описание в несколько строк"], root.xpath("//xs:documentation/text()", namespaces=XS))

    def test_matching_title_and_description_are_not_duplicated(self):
        root = tree(document(A={"type": "string", "title": "Дата", "description": "\n Дата\n\n"}))
        self.assertEqual(["Дата"], root.xpath("//xs:documentation/text()", namespaces=XS))

    def test_root_and_referenced_array_examples(self):
        spec = document(Values={"type": "array", "minItems": 1, "maxItems": 1, "items": {"type": "integer"}, "examples": [[1]]}, A=obj({"values": ref("Values")}, examples=[{"values": [1]}]))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<values><row>1</row></values>")))
        self.assertFalse(valid.validate(instance("<values/>")))
        self.assertFalse(valid.validate(instance("<values><row>1</row><row>2</row></values>")))
        spec["components"]["schemas"]["Values"]["examples"] = [[]]
        self.rejects(spec, "value")

    def test_zero_and_one_element_simple_arrays(self):
        spec = document(A=obj({"empty": {"type": "array", "minItems": 0, "maxItems": 0, "items": {"type": "string"}}, "single": {"type": "array", "minItems": 1, "maxItems": 1, "items": {"type": "string"}}}, ["single"], examples=[{"single": ["one"], "empty": []}]))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<single>one</single>")))
        self.assertFalse(valid.validate(instance("<single>one</single><single>two</single>")))

    def test_example_xsd_files_are_reproducible(self):
        examples = SCRIPT.parent.parent / "examples"
        cases = (("kfk-test", "http://v8.fsk.ru/kfk/test/1.0", "1c.", "", "TestCatalog"), ("asyncapi_example", "http://v8.fsk.ru/example/kfk/1.0", "1c.", ".changed", "TestDocument"), ("kfk-unit", "http://v8.fsk.ru/kfk/unit/1.0", "", "", "TestConversion"))
        for stem, namespace, prefix, suffix, expected_type in cases:
            with self.subTest(stem=stem):
                generated = generate_xsd(load_document(examples / (stem + ".yaml")), namespace, prefix=prefix, suffix=suffix)
                stored = (examples / (stem + ".xsd")).read_bytes()
                self.assertEqual(generated.replace(b"\r\n", b"\n"), stored.replace(b"\r\n", b"\n"))
                root = etree.fromstring(generated)
                self.assertTrue(root.xpath("xs:complexType[@name=$name]", namespaces=XS, name=expected_type))
                etree.XMLSchema(root)

    def test_required_zero_minimum_can_be_omitted_but_not_null(self):
        spec = document(A=obj({"name": {"type": "string", "minLength": 0}, "number": {"type": "number", "minimum": 0}, "tags": {"type": "array", "minItems": 0, "items": {"type": "string"}}}, ["name", "number", "tags"], examples=[{}]))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("")))
        spec["components"]["schemas"]["A"]["examples"] = [{"name": None}]
        self.rejects(spec, "value")

    def test_optional_positive_scalar_minimum_allows_null(self):
        spec = document(A=obj({"name": {"type": "string", "minLength": 3, "default": None}, "number": {"type": "number", "minimum": 10}}, examples=[{"name": None, "number": None}]))
        root = tree(spec)
        self.assertEqual(["true", "true"], root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element/@nillable", namespaces=XS))

    def test_array_default_minimum_is_zero_only_for_arrays(self):
        fields = {"text": {"type": "string"}, "integer": {"type": "integer"}, "number": {"type": "number"}, "boolean": {"type": "boolean"}, "date": {"type": "string", "format": "date"}, "group": obj({}), "array": {"type": "array", "items": {"type": "string"}}}
        root = tree(document(A=obj(fields, list(fields))))
        elements = root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element", namespaces=XS)
        self.assertEqual(["1"] * 6 + ["0"], [element.get("minOccurs", "1") for element in elements])
        self.assertTrue(all(element.get("nillable", "false") == "false" for element in elements))
        tree(document(A=obj({"array": fields["array"]}, ["array"], examples=[{"array": []}])))

    def test_working_yaml_profile(self):
        working = SCRIPT.parent.parents[2] / "AsyncAPI-4.15.1.yaml"
        if not working.exists():
            self.skipTest("external working YAML is not part of the tools repository")
        root = etree.fromstring(generate_xsd(load_document(working), NS, prefix="crm.", suffix=".changed"))
        etree.XMLSchema(root)
        guid = root.xpath("xs:complexType[@name='Property.Traits.Row']/xs:sequence/xs:element[@name='guid']", namespaces=XS)
        self.assertEqual(1, len(guid))
        self.assertEqual("0", guid[0].get("minOccurs", "1"))
        self.assertEqual("false", guid[0].get("nillable", "false"))

    def test_xsd_default_attributes_are_omitted(self):
        root = tree(document(A=obj({"required": {"type": "string"}, "nullable": {"type": "string"}, "many": {"type": "array", "minItems": 0, "items": {"type": "string"}}}, ["required", "many"])))
        self.assertEqual([], root.xpath("//xs:element[@minOccurs='1' or @maxOccurs='1' or @nillable='false']", namespaces=XS))
        self.assertTrue(root.xpath("//xs:element[@name='nullable' and @nillable='true']", namespaces=XS))
        self.assertTrue(root.xpath("//xs:element[@name='many' and @minOccurs='0' and @maxOccurs='unbounded']", namespaces=XS))
        self.assertIsNone(root.get("attributeFormDefault"))

    def test_required_does_not_change_minimum(self):
        fields = {"text": {"type": "string"}, "zero": {"type": "number", "minimum": 0}, "list": {"type": "array", "minItems": 2, "items": {"type": "string"}}}
        optional = tree(document(A=obj(fields)))
        required = tree(document(A=obj(fields, list(fields))))
        for root in (optional, required):
            elements = root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element", namespaces=XS)
            self.assertEqual(["1", "0", "2"], [element.get("minOccurs", "1") for element in elements])
        self.assertEqual(["true", "true", "false"], [element.get("nillable", "false") for element in optional.xpath("xs:complexType[@name='A']/xs:sequence/xs:element", namespaces=XS)])
        self.assertTrue(all(element.get("nillable") is None for element in required.xpath("xs:complexType[@name='A']/xs:sequence/xs:element", namespaces=XS)))

    def test_array_required_minimum_matrix(self):
        for rows in (False, True):
            for required in (False, True):
                for lower in (0, 2):
                    for referenced in (False, True):
                        with self.subTest(rows=rows, required=required, lower=lower, referenced=referenced):
                            item = obj({"value": {"type": "integer"}}, ["value"]) if rows else {"type": "integer"}
                            array = {"type": "array", "minItems": lower, "maxItems": 3, "items": item}
                            field = ref("Values") if referenced else array
                            fields = {"list": field, "other": {"type": "string"}}
                            schemas = {"A": obj(fields, ["list"] if required else [])}
                            if referenced:
                                schemas["Values"] = array
                            spec = document(**schemas)
                            filled = [{"value": 1}, {"value": 2}] if rows else [1, 2]
                            spec["components"]["schemas"]["A"]["examples"] = [{"list": filled}]
                            with warnings.catch_warnings(record=True) as caught:
                                warnings.simplefilter("always", SchemaWarning)
                                root = tree(spec)
                            self.assertEqual(1 if not required and lower > 0 else 0, len(caught))
                            element = root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element[@name='list']", namespaces=XS)[0]
                            self.assertEqual("true" if not required and lower == 0 else "false", element.get("nillable", "false"))
                            spec["components"]["schemas"]["A"]["examples"] = [{"list": None}]
                            if not required and lower == 0:
                                tree(spec)
                            else:
                                self.rejects(spec, "value")
                            spec["components"]["schemas"]["A"]["examples"] = [{"list": []}]
                            if lower == 0:
                                tree(spec)
                            else:
                                self.rejects(spec, "value")
                            spec["components"]["schemas"]["A"]["examples"] = [{"list": [None]}]
                            self.rejects(spec, "value")
                            spec["components"]["schemas"]["A"].pop("examples")
                            spec["components"]["schemas"]["A"]["properties"]["list"]["default"] = None
                            if not required and lower == 0:
                                tree(spec)
                            else:
                                self.rejects(spec, "value")

    def test_reference_zero_minimum_and_nullable_context(self):
        spec = document(Text={"type": "string", "minLength": 0}, A=obj({"text": ref("Text")}, ["text"], examples=[{}]))
        root = tree(spec)
        self.assertEqual(["0"], root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element/@minOccurs", namespaces=XS))
        spec["components"]["schemas"]["A"]["examples"] = [{"text": None}]
        self.rejects(spec, "value")

        for minimum in (Decimal("-0.5"), Decimal("0"), Decimal("0.5")):
            with self.subTest(minimum=minimum):
                number = {"type": "integer", "minimum": minimum}
                root = tree(document(Number=number, Alias=ref("Number"),
                                     A=obj({"direct": number, "linked": ref("Alias")}, ["direct", "linked"])))
                fields = root.xpath("xs:complexType[@name='A']/xs:sequence/xs:element", namespaces=XS)
                self.assertEqual([str(int(minimum != 0))] * 2,
                                 [field.get("minOccurs", "1") for field in fields])

    def test_integral_decimal_cardinality_and_invalid_enum_labels(self):
        tree(document(A=obj({"list": {"type": "array", "minItems": Decimal('1.0'), "maxItems": Decimal('2.0'), "items": {"type": "string"}}})))
        self.rejects(document(A={"type": "string", "enum": ["one"], "x-enumNames": None}), "annotation")

    def test_unrepresentable_xml_value_has_original_path(self):
        error = self.rejects(document(A={"type": "string", "examples": ["\x00"]}), "representation")
        self.assertEqual("$.components.schemas.A.examples[0]", error.path)

    def test_portable_regex_literal_escapes_and_digits(self):
        for pattern, good, bad in ((r"\^", "x^x", "xx"), (r"a\.", "xa.x", "xabx"), (r"\d{2}", "x12x", "x1x")):
            valid = validator(document(A={"type": "string", "pattern": pattern}))
            self.assertTrue(valid.validate(instance(good)))
            self.assertFalse(valid.validate(instance(bad)))

    def test_large_numeric_and_pattern_representations_are_bounded(self):
        self.rejects(document(A={"type": "number", "minimum": Decimal("1e100000")}), "limit")
        self.rejects(document(A={"type": "string", "pattern": "a{10000000000}"}), "limit")
        self.rejects(document(A={"type": "string", "pattern": "a" * 4097}), "limit")
        # A valid decimal beyond libxml's implementation capacity must fail,
        # rather than being truncated or published as a usable XSD.
        error = self.rejects(document(A={"type": "number", "minimum": Decimal("123456789012345678901234567890.123456789")}))
        self.assertEqual("$.components.schemas.A", error.path)

    def test_defaults_examples_and_enum_members_are_validated(self):
        tree(document(A={"type": "integer", "default": 0, "examples": [0, 1]}))
        for schema in ({"type": "integer", "minimum": 1, "default": 0},
                       {"type": "string", "minLength": 2, "enum": ["x"]},
                       {"type": "boolean", "examples": ["false"]},
                       obj({"name": {"type": "string"}}, ["name"], default={})):
            self.rejects(document(A=schema))

    def test_stable_schema_order_and_input_not_mutated(self):
        spec = document(B=obj({"name": {"type": "string"}}), A={"type": "string"})
        before = copy.deepcopy(spec)
        first = generate_xsd(spec, NS)
        second = generate_xsd(document(A={"type": "string"}, B=obj({"name": {"type": "string"}})), NS)
        self.assertEqual(first, second)
        self.assertEqual(before, spec)

    def test_optional_channel_naming_all_messages(self):
        spec = document(A=obj({}), B=obj({}))
        spec["components"]["messages"] = {"First": {"payload": ref("A")}, "Second": {"payload": ref("B")}}
        spec["channels"] = {"one": {"address": "crm.order.changed", "messages": {"a": {"$ref": "#/components/messages/First"}, "b": {"$ref": "#/components/messages/Second"}}}}
        # Both messages mapped to the same name would collide; the second cannot disappear.
        with self.assertRaises(SchemaError):
            generate_xsd(spec, NS, prefix="crm.", suffix=".changed")
        spec["channels"]["one"]["messages"].pop("b")
        root = tree(spec, prefix="crm.", suffix=".changed")
        self.assertEqual(["B", "Order"], root.xpath("//xs:complexType/@name", namespaces=XS))
        spec["channels"]["other"] = {"address": "crm.other.changed", "messages": {"a": {"$ref": "#/components/messages/First"}}}
        with self.assertRaises(SchemaError) as caught:
            generate_xsd(spec, NS, prefix="crm.", suffix=".changed")
        self.assertEqual("name-conflict", caught.exception.category)

    def test_namespace_and_shapes(self):
        for spec in ({}, {"components": {"schemas": {}}}, {"components": {"schemas": []}}):
            self.rejects(spec, "shape")
        for namespace in ("", ":bad", "relative", "http://www.w3.org/2001/XMLSchema", "http://v8.1c.ru/edi/edi_stnd/EnterpriseData/1.25", "urn:with space"):
            with self.assertRaises(SchemaError):
                generate_xsd(document(A=obj({})), namespace)


class FileTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="kafka-xdto-tests-")
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "input.yaml"
        self.output = Path(self.directory.name) / "output.xsd"

    def source_text(self, text):
        self.source.write_text(text, encoding="utf-8")

    def test_loader_duplicates_and_cycles(self):
        for text in ("a: 1\na: 2\n", "a: &cycle {next: *cycle}\n", "true: value\n", "a: &base {x: 1}\nb: {<<: *base}\n", "a: !!float .nan\n"):
            self.source_text(text)
            with self.assertRaises(SchemaError):
                load_document(self.source)

    def test_loader_bounds_alias_amplification_and_nesting(self):
        text = "a0: &a0 [x]\n" + "".join(f"a{i}: &a{i} [*a{i-1}, *a{i-1}]\n" for i in range(1, 20))
        self.source_text(text)
        with self.assertRaises(SchemaError) as caught:
            load_document(self.source)
        self.assertEqual("limit", caught.exception.category)
        self.source_text("a: " + "[" * 150 + "x" + "]" * 150)
        with self.assertRaises(SchemaError):
            load_document(self.source)

    def test_loader_json_scalars_and_decimal_precision(self):
        self.source_text("date: 2026-09-15\nyes: yes\nflag: false\nvalue: 1.23456789012345678901234567890\nexponent: 1e-30\n")
        value = load_document(self.source)
        self.assertEqual("2026-09-15", value["date"])
        self.assertEqual("yes", value["yes"])
        self.assertIs(False, value["flag"])
        self.assertEqual(Decimal("1.23456789012345678901234567890"), value["value"])
        self.assertEqual(Decimal("1e-30"), value["exponent"])

    def test_conversion_and_same_path(self):
        self.source_text("components:\n  schemas:\n    A: {type: string}\n")
        convert_file(self.source, self.output, NS)
        etree.XMLSchema(etree.parse(str(self.output)))
        with self.assertRaises(SchemaError):
            convert_file(self.source, self.source, NS)

    def test_documented_example_end_to_end(self):
        result = subprocess.run([sys.executable, str(SCRIPT), str(SCRIPT.parent / "supported-example.yaml"), str(self.output), "-n", NS], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        root = etree.parse(str(self.output))
        etree.XMLSchema(root)
        self.assertEqual(["tns:OrderLine"], root.xpath("//xs:complexType[@name='OrderLines']//xs:element/@type", namespaces=XS))
        self.assertEqual(["100"], root.xpath("//xs:complexType[@name='OrderLines']//xs:element/@maxOccurs", namespaces=XS))

    def test_failed_model_preserves_existing_output(self):
        self.output.write_bytes(b"previous")
        self.source_text("components:\n  schemas:\n    A: {type: integer, enum: [wrong]}\n")
        with self.assertRaises(SchemaError):
            convert_file(self.source, self.output, NS)
        self.assertEqual(b"previous", self.output.read_bytes())

    def test_failed_replace_preserves_output_and_cleans_temporary(self):
        self.output.write_bytes(b"previous")
        self.source_text("components:\n  schemas:\n    A: {type: string}\n")
        with patch("asyncapi2xsd.os.replace", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                convert_file(self.source, self.output, NS)
        self.assertEqual(b"previous", self.output.read_bytes())
        self.assertEqual({"input.yaml", "output.xsd"}, {p.name for p in self.output.parent.iterdir()})

    def test_cli_exit_code_and_clean_diagnostics(self):
        self.source_text("components:\n  schemas:\n    A: {type: integer, default: wrong}\n")
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.source), str(self.output), "-n", NS], capture_output=True, text=True)
        self.assertEqual(2, result.returncode)
        self.assertIn(".default", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())
        self.source_text("components:\n  schemas:\n    A: {type: string}\n")
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.source), str(self.output), "-n", NS], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(self.output.exists())


if __name__ == "__main__":
    unittest.main()
