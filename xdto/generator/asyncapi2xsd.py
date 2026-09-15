"""Generate XSD for the supported Kafka adapter YAML profile.

The compiler keeps parsing, semantic types, XSD emission and file publication
separate within this single-file command-line tool.
"""

import argparse
import copy
import os
import re
import sys
import tempfile
import warnings
from collections import defaultdict, deque
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path

import yaml
from lxml import etree


# Validated model and input errors

class SchemaWarning(UserWarning):
    """A supported input setting overridden by the adapter profile."""


class SchemaError(ValueError):
    """An expected input error with a stable category and source path."""

    def __init__(self, category: str, path: str, message: str):
        self.category = category
        self.path = path
        self.message = message
        super().__init__(f"[{category}] {path}: {message}")


@dataclass(frozen=True)
class SimpleType:
    name: str
    base: str
    facets: tuple[tuple[str, str], ...]
    path: str
    description: str = ""


@dataclass(frozen=True)
class Property:
    name: str
    type_name: str
    lower: int
    upper: int | None
    path: str
    description: str = ""
    wrapped_array: bool = False
    repeated: bool = False
    nullable: bool = False


@dataclass(frozen=True)
class CollectionValue:
    item_type: str
    value: object
    path: str
    lower: int
    upper: int | None
    nullable: bool = False


@dataclass(frozen=True)
class SchemaValue:
    type_name: str
    value: object
    path: str
    nullable: bool = False


@dataclass(frozen=True)
class ObjectType:
    name: str
    properties: tuple[Property, ...]
    path: str
    description: str = ""
    array_value: bool = False


@dataclass(frozen=True)
class Model:
    namespace: str
    simple_types: tuple[SimpleType, ...]
    object_types: tuple[ObjectType, ...]

# Bounded YAML loading

MAX_BYTES = 10 * 1024 * 1024
MAX_DEPTH = 128
MAX_NODES = 100_000


class SchemaLoader(yaml.SafeLoader):
    pass


# JSON scalar semantics: dates remain strings, yes/no remain strings and
# decimal/scientific values retain their original precision.
SchemaLoader.yaml_implicit_resolvers = {
    key: [(tag, regex) for tag, regex in values
          if tag not in {"tag:yaml.org,2002:bool", "tag:yaml.org,2002:timestamp",
                         "tag:yaml.org,2002:int", "tag:yaml.org,2002:float"}]
    for key, values in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
SchemaLoader.add_implicit_resolver(
    "tag:yaml.org,2002:bool", re.compile(r"^(?:true|false)$"), list("tf"))
SchemaLoader.add_implicit_resolver(
    "tag:yaml.org,2002:int", re.compile(r"^-?(?:0|[1-9][0-9]*)$"), list("-0123456789"))
SchemaLoader.add_implicit_resolver(
    "tag:yaml.org,2002:float",
    re.compile(r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+(?:[eE][+-]?[0-9]+)?|[eE][+-]?[0-9]+)$"),
    list("-0123456789"))


def _mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        if key_node.tag == "tag:yaml.org,2002:merge":
            raise SchemaError("yaml", str(key_node.start_mark), "YAML merge keys are not supported")
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str):
            raise SchemaError("yaml", str(key_node.start_mark), "mapping keys must be strings")
        if key in result:
            raise SchemaError("duplicate-key", str(key_node.start_mark), f"duplicate key {key!r}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


def _decimal(loader, node):
    try:
        value = Decimal(loader.construct_scalar(node))
    except InvalidOperation as exc:
        raise SchemaError("yaml", str(node.start_mark), "invalid decimal value") from exc
    if not value.is_finite():
        raise SchemaError("yaml", str(node.start_mark), "numbers must be finite")
    return value


SchemaLoader.add_constructor("tag:yaml.org,2002:map", _mapping)
SchemaLoader.add_constructor("tag:yaml.org,2002:float", _decimal)


def check_document(value):
    """Validate containers iteratively; repeated aliases cannot amplify work unboundedly."""
    stack = [(value, "$", 0, False)]
    active = set()
    count = 0
    while stack:
        current, path, depth, leaving = stack.pop()
        if leaving:
            active.remove(id(current))
            continue
        count += 1
        if count > MAX_NODES or depth > MAX_DEPTH:
            raise SchemaError("limit", path, "document exceeds nesting or node limit")
        if isinstance(current, (dict, list)):
            if id(current) in active:
                raise SchemaError("yaml-cycle", path, "recursive YAML aliases are not supported")
            active.add(id(current))
            stack.append((current, path, depth, True))
            if isinstance(current, dict):
                for key, child in current.items():
                    if not isinstance(key, str):
                        raise SchemaError("yaml", path, "mapping keys must be strings")
                    stack.append((child, f"{path}.{key}", depth + 1, False))
            else:
                stack.extend((child, f"{path}[{i}]", depth + 1, False)
                             for i, child in enumerate(current))
        elif current is not None and not isinstance(current, (str, bool, int, Decimal)):
            raise SchemaError("yaml", path, "only JSON-compatible scalar values are supported")
        elif isinstance(current, Decimal) and not current.is_finite():
            raise SchemaError("yaml", path, "numbers must be finite")


def load_document(path: Path):
    with path.open("rb") as stream:
        data = stream.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise SchemaError("limit", "$", f"input exceeds {MAX_BYTES} bytes")
    try:
        value = yaml.load(data.decode("utf-8-sig"), Loader=SchemaLoader)
    except (UnicodeError, yaml.YAMLError, RecursionError, ValueError) as exc:
        if isinstance(exc, SchemaError):
            raise
        raise SchemaError("yaml", "$", str(exc)) from exc
    check_document(value)
    if not isinstance(value, dict):
        raise SchemaError("shape", "$", "root must be a mapping")
    return value

# Primitive types and portable facets

UUID_PATTERN = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
BASES = {
    "string": {None: "xs:string", "uuid": "tns:UUID", "date": "xs:date",
               "time": "xs:time", "date-time": "xs:dateTime", "email": "xs:string"},
    "integer": {None: "xs:integer", "int32": "xs:int", "int64": "xs:long"},
    "number": {None: "xs:decimal", "float": "xs:float", "double": "xs:double"},
    "boolean": {None: "xs:boolean"},
}
STRING_KEYS = {"minLength", "maxLength", "pattern"}
NUMBER_KEYS = {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"}


def nonnegative(value, path):
    if isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value():
        number(value, path)
        value = int(value)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise SchemaError("value", path, "expected a nonnegative integer")
    return value


def number(value, path):
    if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
        raise SchemaError("value", path, "expected a finite number")
    result = Decimal(value)
    if not result.is_finite():
        raise SchemaError("value", path, "expected a finite number")
    if len(result.as_tuple().digits) > 1000 or abs(result.as_tuple().exponent) > 1000:
        raise SchemaError("limit", path, "numeric representation exceeds 1000 digits/exponent")
    return result


def lexical(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, Decimal):
        return format(value, "f")
    return str(value)


def scalar_lexical(kind, value):
    return str(int(value)) if kind == "integer" else lexical(value)


def portable_pattern(pattern, path):
    """Translate ASCII atoms/classes and greedy repetitions from search to XSD match.

    Leading ^ and trailing $ are translated as assertions, not XSD literals.
    Wildcard dots, user groups, alternation and non-ASCII classes are outside
    the profile.
    """
    if not isinstance(pattern, str) or not pattern:
        raise SchemaError("pattern", path, "expected a nonempty portable expression")
    if len(pattern) > 4096:
        raise SchemaError("limit", path, "pattern exceeds 4096 characters")
    original_pattern = pattern
    anchored_start = pattern.startswith("^")
    if anchored_start:
        pattern = pattern[1:]
    backslashes_before_end = len(pattern[:-1]) - len(pattern[:-1].rstrip("\\"))
    anchored_end = pattern.endswith("$") and backslashes_before_end % 2 == 0
    if anchored_end:
        pattern = pattern[:-1]
    result = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "[":
            end = pattern.find("]", i + 1)
            body = pattern[i + 1:end] if end >= 0 else ""
            if not body or not re.fullmatch(r"[A-Za-z0-9 _\-]+", body):
                raise SchemaError("pattern", path, "only positive ASCII character classes are supported")
            result.append(pattern[i:end + 1])
            i = end + 1
        elif c == "\\" and i + 1 < len(pattern):
            escaped = pattern[i + 1]
            if escaped == "d":
                result.append("[0-9]")
            elif escaped in r"\.?*+{}()|[]^$-":
                result.append(escaped if escaped in "^$" else "\\" + escaped)
            else:
                raise SchemaError("pattern", path, "unsupported escape")
            i += 2
        elif c.isascii() and (c.isalnum() or c in " _-:/,@%"):
            result.append(c)
            i += 1
        else:
            raise SchemaError("pattern", path, "unsupported atom; anchors, groups and wildcard dots are not supported")
        if i < len(pattern) and pattern[i] in "?*+":
            result.append(pattern[i])
            i += 1
        elif i < len(pattern) and pattern[i] == "{":
            match = re.match(r"\{([0-9]+)(?:,([0-9]*))?\}", pattern[i:])
            if not match:
                raise SchemaError("pattern", path, "invalid repetition")
            lower, upper = match.groups()
            if int(lower) > 1000 or (upper and int(upper) > 1000):
                raise SchemaError("limit", path, "explicit repetition exceeds 1000")
            if upper and int(lower) > int(upper):
                raise SchemaError("pattern", path, "invalid repetition bounds")
            result.append(match.group())
            i += len(match.group())
    try:
        re.compile(original_pattern, re.ASCII)
    except re.error as exc:
        raise SchemaError("pattern", path, str(exc)) from exc
    prefix = "" if anchored_start else r"[\s\S]*"
    # JSON Schema patterns have no multiline flag: $ requires the input end.
    suffix = "" if anchored_end else r"[\s\S]*"
    return prefix + "(" + "".join(result) + ")" + suffix


def primitive(schema, path):
    kind = schema["type"]
    fmt = schema.get("format")
    if fmt is not None and not isinstance(fmt, str):
        raise SchemaError("format", path + ".format", "expected a string")
    if fmt not in BASES[kind]:
        raise SchemaError("format", path + ".format", f"unsupported format {fmt!r} for {kind}")
    base = BASES[kind][fmt]
    allowed = STRING_KEYS if kind == "string" and fmt in {None, "email"} else NUMBER_KEYS if kind in {"integer", "number"} else set()
    invalid = (STRING_KEYS | NUMBER_KEYS).intersection(schema).difference(allowed)
    if invalid:
        raise SchemaError("facet", path, f"constraints incompatible with type/format: {sorted(invalid)}")
    facets = []
    if kind == "string" and fmt in {None, "email"}:
        for key in ("minLength", "maxLength"):
            if key in schema:
                facets.append((key, str(nonnegative(schema[key], path + "." + key))))
        if schema.get("minLength", 0) > schema.get("maxLength", schema.get("minLength", 0)):
            raise SchemaError("facet", path, "minLength exceeds maxLength")
        if "pattern" in schema:
            facets.append(("pattern", portable_pattern(schema["pattern"], path + ".pattern")))
    if kind in {"integer", "number"}:
        bounds = []
        for inclusive, exclusive, inc_facet, exc_facet in (
                ("minimum", "exclusiveMinimum", "minInclusive", "minExclusive"),
                ("maximum", "exclusiveMaximum", "maxInclusive", "maxExclusive")):
            if inclusive in schema and exclusive in schema:
                raise SchemaError("facet", path, f"use either {inclusive} or {exclusive}, not both")
            key = exclusive if exclusive in schema else inclusive
            if key in schema:
                value = number(schema[key], path + "." + key)
                if kind == "integer":
                    if inclusive == "minimum":
                        bound = int(value.to_integral_value(rounding="ROUND_CEILING"))
                        if key == exclusive and Decimal(bound) == value:
                            bound += 1
                    else:
                        bound = int(value.to_integral_value(rounding="ROUND_FLOOR"))
                        if key == exclusive and Decimal(bound) == value:
                            bound -= 1
                    facets.append((inc_facet, str(bound)))
                else:
                    facets.append((exc_facet if key == exclusive else inc_facet, lexical(value)))
                bounds.append((value, key == exclusive))
            else:
                bounds.append(None)
        lower, upper = bounds
        if lower and upper and (lower[0] > upper[0] or
                               (lower[0] == upper[0] and (lower[1] or upper[1]))):
            raise SchemaError("facet", path, "numeric range is empty")
        if kind == "integer":
            # Detect intervals containing no integer, even when decimal bounds differ.
            if lower and upper:
                lo = int(lower[0].to_integral_value(rounding="ROUND_CEILING"))
                hi = int(upper[0].to_integral_value(rounding="ROUND_FLOOR"))
                if lower[1] and lo == lower[0]:
                    lo += 1
                if upper[1] and hi == upper[0]:
                    hi -= 1
                if lo > hi:
                    raise SchemaError("facet", path, "range contains no integer")
        if "multipleOf" in schema:
            step = number(schema["multipleOf"], path + ".multipleOf")
            if step <= 0:
                raise SchemaError("facet", path + ".multipleOf", "step must be positive")
            digits = list(step.as_tuple().digits)
            exponent = step.as_tuple().exponent
            while len(digits) > 1 and digits[-1] == 0:
                digits.pop()
                exponent += 1
            if kind == "integer" and step == 1:
                pass
            elif base == "xs:decimal" and digits == [1] and exponent <= 0:
                facets.append(("fractionDigits", str(-exponent)))
            else:
                raise SchemaError("representation", path + ".multipleOf", "step cannot be represented exactly by this type")
    if "enum" in schema:
        values = schema["enum"]
        if not isinstance(values, list) or not values:
            raise SchemaError("enum", path + ".enum", "expected a nonempty list")
        if kind == "boolean" or fmt == "uuid":
            raise SchemaError("representation", path + ".enum", "enum is not supported for this type/format")
        seen = set()
        for index, value in enumerate(values):
            value_path = f"{path}.enum[{index}]"
            check_scalar(kind, value, value_path)
            if value in seen:
                raise SchemaError("enum", value_path, "duplicate value")
            seen.add(value)
            facets.append(("enumeration", scalar_lexical(kind, value)))
        names = schema.get("x-enumNames")
        if "x-enumNames" in schema and (not isinstance(names, list) or len(names) != len(values)
                                  or any(not isinstance(v, str) for v in names)):
            raise SchemaError("annotation", path + ".x-enumNames", "expected one string label per enum value")
    elif "x-enumNames" in schema:
        raise SchemaError("annotation", path + ".x-enumNames", "requires enum")
    return base, tuple(facets)


def check_scalar(kind, value, path):
    valid = {"string": isinstance(value, str), "boolean": isinstance(value, bool),
             "integer": (isinstance(value, int) and not isinstance(value, bool)) or
                        (isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value()),
             "number": isinstance(value, (int, Decimal)) and not isinstance(value, bool)}[kind]
    if not valid:
        raise SchemaError("value", path, f"value does not match {kind}")
    if kind in {"integer", "number"}:
        number(value, path)

# Schema resolution and adapter profile

SCHEMA_REF = "#/components/schemas/"
ANNOTATIONS = {"title", "description", "deprecated", "default", "examples", "$comment"}
STRUCTURE = {"type", "$ref", "properties", "required", "items", "minItems", "maxItems", "format", "enum", "additionalProperties"}


def mapping(value, path):
    if not isinstance(value, dict):
        raise SchemaError("shape", path, "expected a mapping")
    return value


def xml_name(name, path):
    if not isinstance(name, str) or not name or not (name[0].isalpha() or name[0] == "_"):
        raise SchemaError("name", path, "name must start with a letter or underscore")
    if any(not (c.isalnum() or c in "_.-") for c in name):
        raise SchemaError("name", path, "only letters, digits, underscore, dot and hyphen are supported")
    return name


def type_name(name, path):
    xml_name(name, path)
    result = "".join(part[0].upper() + part[1:] for part in re.split(r"[._-]", name) if part)
    return xml_name(result, path)


def local_reference(ref, prefix, definitions, path):
    if not isinstance(ref, str) or not ref.startswith(prefix):
        raise SchemaError("reference", path, f"expected {prefix}<name>")
    name = ref[len(prefix):]
    if not name or "/" in name or "~" in name or name not in definitions:
        raise SchemaError("reference", path, f"unknown or unsupported reference {ref!r}")
    return name


def channel_names(document, schemas, prefix, suffix):
    channels = document.get("channels", {})
    if not isinstance(channels, dict):
        raise SchemaError("shape", "$.channels", "expected a mapping")
    messages = document.get("components", {}).get("messages", {})
    result = {}
    for channel_key, raw in sorted(channels.items()):
        path = f"$.channels.{channel_key}"
        channel = mapping(raw, path)
        address = channel.get("address")
        if address is None:
            continue
        if not isinstance(address, str) or not address:
            raise SchemaError("name", path + ".address", "expected a nonempty address")
        entries = mapping(channel.get("messages", {}), path + ".messages")
        for key, entry in sorted(entries.items()):
            entry_path = path + ".messages." + key
            message = mapping(entry, entry_path)
            if "$ref" in message:
                definitions = mapping(messages, "$.components.messages")
                message_key = local_reference(message["$ref"], "#/components/messages/", definitions, entry_path + ".$ref")
                message = mapping(definitions[message_key], "$.components.messages." + message_key)
            payload = message.get("payload")
            # Only named schema links contribute to naming. Inline payloads do
            # not replace components.schemas and are irrelevant to compilation.
            if not isinstance(payload, dict) or "$ref" not in payload:
                continue
            schema_key = local_reference(payload["$ref"], SCHEMA_REF, schemas, entry_path + ".payload.$ref")
            stem = address
            if prefix and stem.startswith(prefix):
                stem = stem[len(prefix):]
            if suffix and stem.endswith(suffix):
                stem = stem[:-len(suffix)]
            proposed = type_name(stem, path + ".address")
            if schema_key in result and result[schema_key] != proposed:
                raise SchemaError("name-conflict", path, f"schema {schema_key!r} has conflicting channel names")
            result[schema_key] = proposed
    return result


class Compiler:
    def __init__(self, document, namespace, prefix, suffix):
        check_document(document)
        mapping(document, "$")
        components = mapping(document.get("components"), "$.components")
        self.schemas = mapping(components.get("schemas"), "$.components.schemas")
        if not self.schemas:
            raise SchemaError("shape", "$.components.schemas", "at least one schema is required")
        if not isinstance(namespace, str) or any(c.isspace() for c in namespace) or not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", namespace):
            raise SchemaError("namespace", "$", "namespace must be a nonempty absolute URI without whitespace")
        if namespace.lower().startswith("http://v8.1c.ru/edi/edi_stnd/enterprisedata/"):
            raise SchemaError("namespace", "$", "use a custom namespace, not the EnterpriseData namespace")
        if namespace in {"http://www.w3.org/2001/XMLSchema", "http://www.w3.org/XML/1998/namespace", "http://www.w3.org/2000/xmlns/"}:
            raise SchemaError("namespace", "$", "reserved XML namespaces cannot own this model")
        if not isinstance(prefix, str) or not isinstance(suffix, str):
            raise SchemaError("name", "$", "prefix and suffix must be strings")
        self.namespace = namespace
        for key in self.schemas:
            xml_name(key, "$.components.schemas." + key)
        channels = channel_names(document, self.schemas, prefix, suffix)
        canonical_channels = {}
        for key, proposed in channels.items():
            seen = set()
            while isinstance(self.schemas[key], dict) and "$ref" in self.schemas[key]:
                if key in seen:
                    raise SchemaError("alias-cycle", "$.components.schemas." + key, "cyclic type aliases")
                seen.add(key)
                key = local_reference(self.schemas[key]["$ref"], SCHEMA_REF, self.schemas, "$.components.schemas." + key + ".$ref")
            if key in canonical_channels and canonical_channels[key] != proposed:
                raise SchemaError("name-conflict", "$.components.schemas." + key, "aliases/channels propose conflicting names for one type")
            canonical_channels[key] = proposed
        self.names = {key: canonical_channels.get(key, type_name(key, "$.components.schemas." + key)) for key in self.schemas}
        self.types = {}
        self.owners = {}
        self.resolved = {}
        self.active_definitions = set()
        self.pending_values = []

    def schema(self, raw, path):
        schema = mapping(raw, path)
        unknown = set(schema).difference(STRUCTURE | ANNOTATIONS | STRING_KEYS | NUMBER_KEYS)
        unknown = {key for key in unknown if not key.startswith("x-")}
        if unknown:
            raise SchemaError("unsupported", path, f"unsupported schema keywords: {sorted(unknown)}")
        for key in ("title", "description", "$comment"):
            if key in schema and not isinstance(schema[key], str):
                raise SchemaError("annotation", path + "." + key, "expected a string")
        if "deprecated" in schema and not isinstance(schema["deprecated"], bool):
            raise SchemaError("annotation", path + ".deprecated", "expected a boolean")
        if "x-topics" in schema and (not isinstance(schema["x-topics"], list) or
                                     any(not isinstance(v, str) or not v for v in schema["x-topics"])):
            raise SchemaError("annotation", path + ".x-topics", "expected a list of nonempty addresses")
        if "$ref" in schema:
            siblings = set(schema).difference(ANNOTATIONS | {"$ref"})
            siblings = {key for key in siblings if not key.startswith("x-")}
            if siblings:
                raise SchemaError("unsupported", path, "structural siblings of $ref are not supported")
            local_reference(schema["$ref"], SCHEMA_REF, self.schemas, path + ".$ref")
        else:
            kind = schema.get("type")
            if not isinstance(kind, str) or kind not in set(BASES) | {"object", "array"}:
                raise SchemaError("type", path + ".type", "expected an explicit supported type; null/unions are outside the profile")
            applicable = {"properties", "required", "additionalProperties"} if kind == "object" else {"items", "minItems", "maxItems"} if kind == "array" else {"format", "enum"} | STRING_KEYS | NUMBER_KEYS
            if "additionalProperties" in schema and schema["additionalProperties"] is not False:
                raise SchemaError("unsupported", path + ".additionalProperties", "only false is supported; dictionaries require a separate representation")
            wrong = set(schema).intersection(STRUCTURE | STRING_KEYS | NUMBER_KEYS).difference(applicable | {"type"})
            if wrong:
                raise SchemaError("keyword", path, f"keywords incompatible with {kind}: {sorted(wrong)}")
        return schema

    def register(self, name, path):
        if name in self.owners and self.owners[name] != path:
            raise SchemaError("name-conflict", path, f"type {name!r} conflicts with {self.owners[name]}")
        self.owners[name] = path

    def description(self, schema):
        title = compact_text(schema.get("title", ""))
        description = compact_text(schema.get("description", ""))
        text = title or description
        if schema.get("format") == "email":
            text += " format: email (JSON Schema annotation; XSD string constraints apply)"
        return text.strip()

    def remember_values(self, schema, name, path, nullable=False, collection=None):
        """Record annotations after their occurrence's value context is resolved."""
        entries = []
        if "default" in schema:
            entries.append((schema["default"], path + ".default"))
        if "examples" in schema:
            if not isinstance(schema["examples"], list):
                raise SchemaError("annotation", path + ".examples", "expected a list")
            entries.extend((value, f"{path}.examples[{index}]")
                           for index, value in enumerate(schema["examples"]))
        for value, value_path in entries:
            if collection is None:
                entry = SchemaValue(name, value, value_path, nullable)
            else:
                lower, upper = collection
                entry = CollectionValue(name, value, value_path, lower, upper, nullable)
            self.pending_values.append(entry)

    def resolve_schema(self, schema, path):
        """Resolve structural aliases while retaining the original YAML constraints."""
        seen = set()
        while "$ref" in schema:
            key = local_reference(schema["$ref"], SCHEMA_REF, self.schemas, path + ".$ref")
            if key in seen:
                raise SchemaError("alias-cycle", path, "cyclic type aliases")
            seen.add(key)
            path = "$.components.schemas." + key
            schema = self.schema(self.schemas[key], path)
        return schema

    def named(self, key):
        if key in self.resolved:
            return self.resolved[key]
        aliases = []
        seen = set()
        while True:
            if key in self.resolved:
                name = self.resolved[key]
                break
            if key in seen:
                raise SchemaError("alias-cycle", "$.components.schemas." + key, "cyclic type aliases")
            seen.add(key)
            path = "$.components.schemas." + key
            schema = self.schema(self.schemas[key], path)
            if "$ref" not in schema:
                name = "UUID" if schema.get("format") == "uuid" else self.names[key]
                break
            aliases.append((key, schema, path))
            key = local_reference(schema["$ref"], SCHEMA_REF, self.schemas, path + ".$ref")
        for alias, schema, path in aliases:
            self.resolved[alias] = name
            self.remember_values(schema, name, path)
        if key in self.resolved:
            return name
        path = "$.components.schemas." + key
        schema = self.schema(self.schemas[key], path)
        if len(self.active_definitions) >= 100:
            raise SchemaError("limit", path, "reference expansion exceeds 100 nested definitions")
        self.resolved[key] = name  # Object recursion refers to an already allocated identity.
        self.active_definitions.add(key)
        try:
            name = self.define(schema, name, path)
            self.remember_values(schema, name, path)
            return name
        finally:
            self.active_definitions.remove(key)

    def define(self, schema, name, path):
        if schema["type"] == "array":
            self.register(name, path)
            lower, upper, item_name = self.array_items(schema, name + ".Row", path)
            self.types[name] = ObjectType(name, (Property("row", item_name, lower, upper, path, repeated=True),), path, self.description(schema), array_value=True)
            return name
        if schema["type"] in BASES:
            base, facets = primitive(schema, path)
            if base == "tns:UUID":
                self.register("UUID", "<UUID>")
                self.types["UUID"] = SimpleType("UUID", "xs:string", (("length", "36"), ("pattern", UUID_PATTERN)), "<UUID>", "UUID identifier")
                name = "UUID"
            else:
                self.register(name, path)
                self.types[name] = SimpleType(name, base, facets, path, self.description(schema))
            return name
        self.register(name, path)
        properties = mapping(schema.get("properties"), path + ".properties")
        required = schema.get("required", [])
        if not isinstance(required, list) or any(not isinstance(v, str) for v in required):
            raise SchemaError("required", path + ".required", "expected a list of field names")
        if len(set(required)) != len(required) or set(required).difference(properties):
            raise SchemaError("required", path + ".required", "duplicate or unknown field names")
        fields = []
        for field, raw in properties.items():
            field_path = path + ".properties." + field
            xml_name(field, field_path)
            if field == "AdditionalInfo":
                raise SchemaError("representation", field_path, "AdditionalInfo requires a separate platform serialization contract")
            child = self.schema(raw, field_path)
            if child.get("type") == "array":
                proposed_item = name + "." + type_name(field, field_path) + ".Row" if len(properties) > 1 else name + ".Row"
                lower, upper, item_name = self.array_items(child, proposed_item, field_path)
                object_rows = not isinstance(self.types.get(item_name), SimpleType)
                wrapped = object_rows and len(properties) > 1
                is_required = field in required
                nullable = self.array_nullable(is_required, lower, field_path)
                if wrapped:
                    table_name = name + "." + type_name(field, field_path)
                    self.register(table_name, field_path)
                    self.types[table_name] = ObjectType(table_name, (Property("row", item_name, lower, upper, field_path, repeated=True),), field_path, self.description(child))
                    fields.append(Property(field, table_name, 1, 1, field_path, self.description(child), wrapped_array=True, nullable=nullable))
                else:
                    fields.append(Property(field, item_name, lower, upper, field_path, self.description(child), repeated=True, nullable=nullable))
                self.remember_values(child, item_name, field_path, nullable, (lower, upper))
            else:
                proposed = name + "." + type_name(field, field_path)
                child_name = self.child_type(child, proposed, field_path)
                minimum = self.field_minimum(child, field_path)
                target = self.types.get(child_name)
                nullable = field not in required
                is_array = isinstance(target, ObjectType) and target.array_value
                if is_array:
                    nullable = self.array_nullable(field in required, target.properties[0].lower, field_path)
                lower = 1 if is_array else int(minimum != 0)
                fields.append(Property(field, child_name, lower, 1, field_path, self.description(child), nullable=nullable))
                self.remember_values(child, child_name, field_path, nullable)
        self.types[name] = ObjectType(name, tuple(fields), path, self.description(schema))
        return name

    @staticmethod
    def array_nullable(is_required, lower, path):
        if not is_required and lower > 0:
            warnings.warn(f"[array-nullable] {path}: nullable ignored because minItems={lower} is positive", SchemaWarning, stacklevel=3)
        return not is_required and lower == 0

    def array_items(self, schema, proposed, path):
        lower = nonnegative(schema.get("minItems", 0), path + ".minItems")
        upper = nonnegative(schema["maxItems"], path + ".maxItems") if "maxItems" in schema else None
        if upper is not None and lower > upper:
            raise SchemaError("representation", path, "inconsistent array bounds")
        item_path = path + ".items"
        item = self.schema(schema.get("items"), item_path)
        target = self.resolve_schema(item, item_path)
        if target.get("type") == "array":
            raise SchemaError("representation", item_path, "nested arrays are unsupported")
        item_name = self.child_type(item, proposed, item_path)
        self.remember_values(item, item_name, item_path)
        return lower, upper, item_name

    def field_minimum(self, schema, path):
        """Presence derives from YAML, not rounded or exclusive XSD facets."""
        schema = self.resolve_schema(schema, path)
        key = {"array": "minItems", "string": "minLength", "integer": "minimum", "number": "minimum"}.get(schema.get("type"))
        return schema.get(key, 0 if key == "minItems" else 1) if key else 1

    def child_type(self, schema, proposed, path):
        """Compile a field/item type; its caller owns occurrence annotations."""
        if "$ref" in schema:
            key = local_reference(schema["$ref"], SCHEMA_REF, self.schemas, path + ".$ref")
            return self.named(key)
        return self.define(schema, proposed, path)

    def finish(self):
        for key in sorted(self.schemas):
            self.named(key)
        objects = [v for v in self.types.values() if isinstance(v, ObjectType)]
        # Required containment cycles have no finite object instance. Optional
        # edges and zero-row tables provide valid termination points.
        finite = {name for name, value in self.types.items() if isinstance(value, SimpleType)}
        dependencies = {v.name: {p.type_name for p in v.properties if p.lower > 0 and not p.nullable and p.type_name not in finite} for v in objects}
        parents = defaultdict(set)
        for name, children in dependencies.items():
            for child in children:
                parents[child].add(name)
        queue = deque(name for name, children in dependencies.items() if not children)
        while queue:
            name = queue.popleft()
            finite.add(name)
            for parent in parents[name]:
                dependencies[parent].discard(name)
                if not dependencies[parent]:
                    queue.append(parent)
        for target in objects:
            if target.name not in finite:
                raise SchemaError("object-cycle", target.path, "required containment has no finite instance")
        return Model(self.namespace,
                     tuple(sorted((v for v in self.types.values() if isinstance(v, SimpleType)),
                                  key=lambda v: (0 if v.name == "UUID" else 1 if "." not in v.name else 2, v.name))),
                     tuple(sorted(objects, key=lambda v: v.name)))


def compile_document(document, namespace, prefix="", suffix=""):
    compiler = Compiler(document, namespace, prefix, suffix)
    return compiler.finish(), tuple(compiler.pending_values)

# XSD validation and atomic publication

XSD_NS = "http://www.w3.org/2001/XMLSchema"


def node(parent, tag, **attributes):
    return etree.SubElement(parent, etree.QName(XSD_NS, tag), **attributes)


def compact_text(text):
    return " ".join(text.split())


def documentation(parent, text):
    if text:
        node(node(parent, "annotation"), "documentation").text = compact_text(text)


def build_schema(model):
    root = etree.Element(etree.QName(XSD_NS, "schema"), nsmap={"xs": XSD_NS, "tns": model.namespace},
                         targetNamespace=model.namespace, elementFormDefault="qualified")
    for target in model.simple_types:
        simple = node(root, "simpleType", name=target.name)
        documentation(simple, target.description)
        restriction = node(simple, "restriction", base=target.base)
        for facet, value in target.facets:
            node(restriction, facet, value=value)
    for target in model.object_types:
        complex_type = node(root, "complexType", name=target.name)
        documentation(complex_type, target.description)
        sequence = node(complex_type, "sequence")
        for field in target.properties:
            attributes = {"name": field.name, "type": "tns:" + field.type_name}
            if field.lower != 1:
                attributes["minOccurs"] = str(field.lower)
            if field.upper != 1:
                attributes["maxOccurs"] = "unbounded" if field.upper is None else str(field.upper)
            if field.nullable:
                attributes["nillable"] = "true"
            element = node(sequence, "element", **attributes)
            documentation(element, field.description)
    return root


def compile_xsd(root, paths=None):
    try:
        return etree.XMLSchema(root)
    except etree.XMLSchemaParseError as exc:
        path = "$"
        error = exc.error_log.last_error
        if paths and error and error.line:
            # Reparsed XSD carries line numbers. Locate the containing type and
            # translate its generated name back to the original YAML definition.
            for child in root:
                if child.sourceline and child.sourceline <= error.line:
                    path = paths.get(child.get("name"), path)
        raise SchemaError("xsd", path, str(exc)) from exc


def primitive_kind(target):
    if target.base in {"xs:integer", "xs:int", "xs:long"}:
        return "integer"
    if target.base in {"xs:decimal", "xs:float", "xs:double"}:
        return "number"
    if target.base == "xs:boolean":
        return "boolean"
    return "string"


def validate_values(model, root, values):
    """Validate JSON/XDTO values; use XMLSchema for primitive facets only.

    The compiler resolves nullability for each value occurrence. Validate JSON
    presence and collection cardinality directly; XMLSchema checks scalar facets.
    No whole-object XML is manufactured to emulate JSON collections.
    """
    types = {target.name: target for target in (*model.simple_types, *model.object_types)}
    probes = copy.deepcopy(root)
    tags = {}
    for index, target in enumerate(model.simple_types):
        tag = "Probe" + str(index)
        tags[target.name] = tag
        node(probes, "element", name=tag, type="tns:" + target.name)
    validator = compile_xsd(probes)

    def validate_simple(name, value, path):
        element = etree.Element(etree.QName(model.namespace, tags[name]))
        try:
            element.text = value
        except ValueError as exc:
            raise SchemaError("representation", path, "value cannot be represented in XML 1.0: " + str(exc)) from exc
        if not validator.validate(element):
            raise SchemaError("value", path, str(validator.error_log.last_error))

    def validate_array(item_type, value, lower, upper, path, depth):
        if not isinstance(value, list):
            raise SchemaError("value", path, "expected an array")
        if len(value) < lower or (upper is not None and len(value) > upper):
            raise SchemaError("value", path, "array length violates minItems/maxItems")
        for index, item in enumerate(value):
            validate_value(item_type, item, f"{path}[{index}]", depth + 1)

    def validate_value(name, value, path, depth=0, nullable=False):
        if depth > MAX_DEPTH:
            raise SchemaError("limit", path, "example/default nesting exceeds limit")
        target = types[name]
        if value is None:
            if not nullable:
                raise SchemaError("value", path, "null is not allowed in this value context")
            return
        if isinstance(target, SimpleType):
            kind = primitive_kind(target)
            check_scalar(kind, value, path)
            validate_simple(name, scalar_lexical(kind, value), path)
            return
        if target.array_value:
            row = target.properties[0]
            validate_array(row.type_name, value, row.lower, row.upper, path, depth)
            return
        if not isinstance(value, dict):
            raise SchemaError("value", path, "expected an object")
        unknown = set(value).difference(field.name for field in target.properties)
        if unknown:
            raise SchemaError("value", path, f"undeclared fields cannot be represented: {sorted(unknown)}")
        for field in target.properties:
            field_path = path + "." + field.name
            if field.name not in value:
                if field.lower > 0 and not field.nullable:
                    raise SchemaError("value", field_path, "required field is missing")
                continue
            child = value[field.name]
            if child is None:
                validate_value(field.type_name, child, field_path, depth + 1, field.nullable)
            elif field.wrapped_array:
                row = types[field.type_name].properties[0]
                validate_array(row.type_name, child, row.lower, row.upper, field_path, depth)
            elif field.repeated:
                validate_array(field.type_name, child, field.lower, field.upper, field_path, depth)
            else:
                validate_value(field.type_name, child, field_path, depth + 1, field.nullable)

    for target in model.simple_types:
        for index, (_, value) in enumerate(facet for facet in target.facets if facet[0] == "enumeration"):
            try:
                validate_simple(target.name, value, target.path + f".enum[{index}]")
            except SchemaError as exc:
                raise SchemaError("enum", exc.path, exc.message) from exc
    for entry in values:
        if isinstance(entry, CollectionValue):
            if entry.value is None and entry.nullable:
                continue
            validate_array(entry.item_type, entry.value, entry.lower, entry.upper, entry.path, 0)
        else:
            validate_value(entry.type_name, entry.value, entry.path, nullable=entry.nullable)


def render(model, values=()):
    try:
        root = build_schema(model)
        data = etree.tostring(root, encoding="UTF-8", xml_declaration=True, pretty_print=True)
        root = etree.fromstring(data)
        paths = {v.name: v.path for v in (*model.simple_types, *model.object_types)}
        compile_xsd(root, paths)
        validate_values(model, root, values)
        return data
    except (ValueError, TypeError) as exc:
        if isinstance(exc, SchemaError):
            raise
        raise SchemaError("xml", "$", str(exc)) from exc


def atomic_write(path: Path, data: bytes):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=path.parent, prefix="." + path.name + ".", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

# Public conversion interface

__all__ = ["SchemaError", "generate_xsd", "convert_file"]


def generate_xsd(document, namespace, *, prefix="", suffix=""):
    """Return validated UTF-8 XSD bytes without touching the filesystem."""
    model, values = compile_document(document, namespace, prefix, suffix)
    return render(model, values)


def convert_file(input_path, output_path, namespace, *, prefix="", suffix=""):
    source = Path(input_path)
    destination = Path(output_path)
    if source.resolve() == destination.resolve() or (destination.exists() and source.samefile(destination)):
        raise SchemaError("path", "$", "input and output must be different files")
    data = generate_xsd(load_document(source), namespace, prefix=prefix, suffix=suffix)
    atomic_write(destination, data)

# Command-line interface

def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate validated XSD from components.schemas in YAML")
    parser.add_argument("input", help="Input YAML file")
    parser.add_argument("output", help="Output XSD file")
    parser.add_argument("-n", "--namespace", required=True, help="Custom XDTO package namespace URI")
    parser.add_argument("--prefix", default="", help="Leading topic address prefix to remove for type naming")
    parser.add_argument("--suffix", default="", help="Trailing topic address suffix to remove for type naming")
    args = parser.parse_args(argv)
    try:
        convert_file(args.input, args.output, args.namespace, prefix=args.prefix, suffix=args.suffix)
    except SchemaError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"[io] {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
