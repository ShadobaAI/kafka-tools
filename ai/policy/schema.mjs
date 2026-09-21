// Shared JSON Schema and runtime checks. Only keywords used below are supported;
// do not treat this small validator as a general JSON Schema implementation.
import { criticalMechanisms } from "./detector.mjs";
export const policyProtocolVersion = "2.0.0";
export const nonblank = { type: "string", minLength: 1, pattern: "\\S" };
export const assessmentSchema = { type: "object", additionalProperties: false,
  properties: { status: { enum: ["present", "absent", "unknown"] }, evidence: nonblank },
  required: ["status", "evidence"] };
export const assessmentsSchema = { type: "object",
  propertyNames: { enum: criticalMechanisms }, additionalProperties: assessmentSchema };
const mechanismList = { type: "array", items: { type: "string", enum: criticalMechanisms } };
export const detectionSchema = { oneOf: [
  { type: "object", additionalProperties: false,
    properties: { sourceRef: nonblank, coverage: { ...assessmentsSchema, required: criticalMechanisms },
      detectedMechanisms: mechanismList, unknownMechanisms: mechanismList },
    required: ["sourceRef", "coverage", "detectedMechanisms", "unknownMechanisms"] },
  { type: "object", additionalProperties: false,
    properties: { format: { const: "compact-v1" }, sourceRef: nonblank,
      coverage: { type: "array", minItems: criticalMechanisms.length, maxItems: criticalMechanisms.length,
        items: { type: "array", minItems: 3, maxItems: 3,
          prefixItems: [{ enum: criticalMechanisms }, { enum: ["present", "absent", "unknown"] }, nonblank] } } },
    required: ["format", "sourceRef", "coverage"] },
] };
export const ledgerItemSchema = {
  type: "object", additionalProperties: false,
  properties: {
    rule_id: nonblank, selection_digest: nonblank, target: nonblank,
    status: { type: "string", enum: ["passed", "deviated"] }, evidence: nonblank, reason: nonblank,
  },
  required: ["rule_id", "selection_digest", "target", "status", "evidence"],
  if: { properties: { status: { const: "deviated" } }, required: ["status"] },
  then: { required: ["reason"] },
};

export function validateSchema(schema, value, at = "arguments") {
  const fail = (message) => { throw new Error(`${at}: ${message}`); };
  if (schema.oneOf) {
    const matches = schema.oneOf.filter((branch) => {
      try { validateSchema(branch, value, at); return true; } catch { return false; }
    });
    if (matches.length !== 1) fail("expected exactly one documented schema variant");
  }
  if (schema.type) {
    const matches = schema.type === "object" ? value !== null && typeof value === "object" && !Array.isArray(value)
      : schema.type === "array" ? Array.isArray(value) : typeof value === schema.type;
    if (!matches) fail(`expected ${schema.type}`);
  }
  if (schema.enum && !schema.enum.includes(value)) fail(`expected one of ${schema.enum.join(", ")}`);
  if (Object.hasOwn(schema, "const") && value !== schema.const) fail(`expected ${schema.const}`);
  if (typeof value === "string") {
    if (schema.minLength && value.length < schema.minLength) fail("empty string");
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail("nonblank value required");
  }
  if (Array.isArray(value) && schema.items) value.forEach((item, i) => validateSchema(schema.items, item, `${at}[${i}]`));
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) fail("too few items");
    if (schema.maxItems !== undefined && value.length > schema.maxItems) fail("too many items");
    (schema.prefixItems ?? []).forEach((item, i) => { if (i < value.length) validateSchema(item, value[i], `${at}[${i}]`); });
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    for (const key of schema.required ?? []) if (!Object.hasOwn(value, key)) fail(`missing ${key}`);
    for (const [key, item] of Object.entries(value)) {
      if (schema.propertyNames) validateSchema(schema.propertyNames, key, `${at} property name`);
      if (schema.additionalProperties === false && !Object.hasOwn(schema.properties ?? {}, key)) fail(`unknown property ${key}`);
      if (schema.properties?.[key]) validateSchema(schema.properties[key], item, `${at}.${key}`);
      else if (schema.additionalProperties && typeof schema.additionalProperties === "object")
        validateSchema(schema.additionalProperties, item, `${at}.${key}`);
    }
  }
  if (schema.if) {
    let matches = true;
    try { validateSchema(schema.if, value, at); } catch { matches = false; }
    if (matches && schema.then) validateSchema(schema.then, value, at);
  }
}
