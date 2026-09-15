"""Contract regressions for the YAML profile and its XSD representation."""

import copy
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

from lxml import etree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asyncapi2xsd import SchemaError, convert_file, generate_xsd, load_document

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


class GeneratorTests(unittest.TestCase):
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
        self.assertEqual(["1", "0"], [v.get("minOccurs") for v in fields])
        self.assertEqual(["false", "false"], [v.get("nillable") for v in fields])
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<id>0</id>")))
        self.assertFalse(valid.validate(instance("")))
        self.assertFalse(valid.validate(instance('<id>1</id><comment xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>')))

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
        self.assertTrue(valid.validate(instance(f"<id>{uuid}</id>")))
        self.assertFalse(valid.validate(instance(f"<id>x{uuid}x</id>")))
        self.assertFalse(valid.validate(instance("<id>not-a-uuid</id>")))

    def test_uuid_name_collision(self):
        self.rejects(document(UUID={"type": "string"}, A=obj({"id": {"type": "string", "format": "uuid"}})), "name-conflict")

    def test_inline_group_gets_semantic_name(self):
        root = tree(document(A=obj({"address": obj({"city": {"type": "string"}, "zip": {"type": "string"}})})))
        self.assertIn("ОбщиеСвойства", root.xpath("//xs:element[@name='address']/@type", namespaces=XS)[0])

    def test_referenced_plain_group_is_rejected(self):
        self.rejects(document(Address=obj({"city": {"type": "string"}}), A=obj({"address": ref("Address")})), "representation")

    def test_canonical_table_has_one_wrapper(self):
        spec = document(Lines=obj({"entry": {"type": "array", "items": ref("Line"), "maxItems": 3}}), Line=obj({"quantity": {"type": "number"}}, ["quantity"]), A=obj({"lines": ref("Lines")}))
        root = tree(spec)
        self.assertEqual(["tns:Line"], root.xpath("//xs:complexType[@name='Lines']//xs:element/@type", namespaces=XS))
        self.assertEqual([], root.xpath("//xs:complexType[@name='Lines.Row']", namespaces=XS))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<lines/>")))
        self.assertTrue(valid.validate(instance("<lines><entry><quantity>1</quantity></entry></lines>")))
        self.assertFalse(valid.validate(instance("<lines><entry/></lines>")))
        self.assertFalse(valid.validate(instance("<lines>" + "<entry><quantity>1</quantity></entry>" * 4 + "</lines>")))

    def test_required_rows_cardinality(self):
        spec = document(A=obj({"row": {"type": "array", "minItems": 1, "maxItems": 2, "items": obj({"name": {"type": "string"}})}}, ["row"]))
        valid = validator(spec)
        self.assertFalse(valid.validate(instance("")))
        self.assertTrue(valid.validate(instance("<row><name>one</name></row>")))

    def test_unrepresentable_collections_rejected(self):
        for limit in (0, 1, True, -1):
            with self.subTest(limit=limit):
                self.rejects(document(A=obj({"row": {"type": "array", "maxItems": limit, "items": obj({})}})))
        self.rejects(document(A=obj({"row": {"type": "array", "items": obj({})}}, ["row"])), "representation")
        self.rejects(document(A=obj({"row": {"type": "array", "minItems": 1, "items": obj({})}})), "representation")
        self.rejects(document(A=obj({"values": {"type": "array", "items": {"type": "string", "enum": ["one"]}}})), "representation")
        self.rejects(document(A={"type": "array", "items": obj({})}), "representation")

    def test_inline_enum_in_table_row(self):
        spec = document(A=obj({"row": {"type": "array", "items": obj({"kind": {"type": "string", "enum": ["one", "two"]}}, ["kind"])}}))
        valid = validator(spec)
        self.assertTrue(valid.validate(instance("<row><kind>one</kind></row>")))
        self.assertFalse(valid.validate(instance("<row><kind>other</kind></row>")))

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
                       {"type": "object", "properties": {}, "additionalProperties": False},
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
        for pattern in ("^[A-Z]+$", ".+", "(a|b)", r"\w+", "[z-a]", "a+?"):
            self.rejects(document(A={"type": "string", "pattern": pattern}), "pattern")

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
