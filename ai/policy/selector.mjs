import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { criticalMechanisms, expandDetection } from "./detector.mjs";
import { validateSchema, ledgerItemSchema } from "./schema.mjs";

const registryPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "registry.json");
const implications = {
  changed_signature: ["method_contract"],
  method_naming: ["method_contract"],
  query_parameters: ["query_text"],
  temporary_query_table: ["query_text"],
  existence_query: ["query_text"],
  query_result_processing: ["query_text"],
  query_in_loop: ["query_text"],
  unbounded_query_result: ["query_text"],
  select_allowed: ["query_text"],
  database_assertion: ["assertions"],
  nontrivial_predicate: ["database_assertion"],
  persistent_data: ["test_data"],
  transactional_test: ["persistent_data"],
  new_module: ["module_structure"],
};

function isStringArray(value) {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.length > 0);
}

export function loadRegistry(source = registryPath) {
  const registry = JSON.parse(fs.readFileSync(source, "utf8"));
  if (registry.schemaVersion !== 1 || !/^\d{4}-\d{2}-\d{2}\.\d+$/.test(registry.registryVersion)) {
    throw new Error("unsupported policy registry version");
  }
  for (const kind of ["oneC", "yaxunit"]) {
    const group = registry[kind];
    if (!group || !isStringArray(group.operations) || !isStringArray(group.mechanisms) ||
        !Array.isArray(group.rules) || (kind === "oneC" && !isStringArray(group.artifacts))) {
      throw new Error(`incomplete ${kind} registry`);
    }
    const ids = new Set();
    for (const rule of group.rules) {
      if (typeof rule.id !== "string" || ids.has(rule.id) || !["mandatory", "recommended"].includes(rule.strength) || !isStringArray(rule.selectors) ||
          (rule.artifacts && (!isStringArray(rule.artifacts) || rule.artifacts.some((x) => !group.artifacts.includes(x)))) ||
          (rule.operations && (!isStringArray(rule.operations) || rule.operations.some((x) => !group.operations.includes(x)))) ||
          (rule.any && (!isStringArray(rule.any) || rule.any.some((x) => !group.mechanisms.includes(x))))) {
        throw new Error(`invalid ${kind} registry rule ${rule.id}`);
      }
      for (const selector of rule.selectors) {
        if (kind === "yaxunit" ? !/^yaxunit:patterns:[a-z-]+$/.test(selector) :
          !/^(std\d+|corporate:work:[a-z-]+:overview(?:#[^#]+)?)$/.test(selector)) {
          throw new Error(`invalid exact policy selector ${selector}`);
        }
      }
      ids.add(rule.id);
    }
  }
  return registry;
}

function effectiveMechanisms(group, input) {
  const effective = new Set();
  for (const field of ["mechanisms", "classifiedMechanisms", "detectedMechanisms"]) {
    const values = input[field] ?? [];
    if (!isStringArray(values) && !(Array.isArray(values) && values.length === 0)) {
      throw new Error(`invalid ${field}`);
    }
    for (const value of values) effective.add(value);
  }
  const unknown = input.unknownMechanisms ?? [];
  if (!Array.isArray(unknown) || unknown.some((x) => typeof x !== "string")) {
    throw new Error("invalid unknownMechanisms");
  }
  if (unknown.length) throw new Error(`mechanism applicability unresolved: ${unknown.join(", ")}`);
  const pending = [...effective];
  for (let index = 0; index < pending.length; index += 1) {
    const value = pending[index];
    if (!group.mechanisms.includes(value)) throw new Error(`unknown required mechanism: ${value}`);
    for (const implied of implications[value] ?? []) {
      if (!group.mechanisms.includes(implied)) throw new Error(`registry lacks implied mechanism ${implied}`);
      if (!effective.has(implied)) { effective.add(implied); pending.push(implied); }
    }
  }
  return [...effective].sort();
}

function ruleMatches(rule, artifact, operation, mechanisms) {
  return (!rule.artifacts || rule.artifacts.includes(artifact)) &&
    (!rule.operations || rule.operations.includes(operation)) &&
    (!rule.any || rule.any.some((item) => mechanisms.includes(item)));
}

export function select(kind, input, registry = loadRegistry()) {
  if (!["oneC", "yaxunit"].includes(kind) || !input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("invalid selection request");
  }
  const group = registry[kind];
  input = { ...input, detection: expandDetection(input.detection) };
  if (kind === "oneC") {
    const detection = input.detection;
    if (!detection || typeof detection.sourceRef !== "string" || !detection.sourceRef.trim() ||
        !detection.coverage || !Array.isArray(detection.detectedMechanisms) ||
        !Array.isArray(detection.unknownMechanisms) ||
        criticalMechanisms.some((mechanism) => !["present", "absent"].includes(detection.coverage[mechanism]?.status) ||
          typeof detection.coverage[mechanism]?.evidence !== "string" || !detection.coverage[mechanism].evidence.trim()) ||
        detection.unknownMechanisms.length ||
        new Set(detection.detectedMechanisms).size !== detection.detectedMechanisms.length ||
        criticalMechanisms.some((mechanism) =>
          (detection.coverage[mechanism].status === "present") !== detection.detectedMechanisms.includes(mechanism))) {
      throw new Error("incomplete or contradictory mechanism detection");
    }
    const claimed = [...(input.mechanisms ?? []), ...(input.classifiedMechanisms ?? []),
      ...(input.detectedMechanisms ?? [])];
    if (claimed.some((mechanism) => criticalMechanisms.includes(mechanism) &&
        detection.coverage[mechanism].status === "absent")) {
      throw new Error("explicit mechanism contradicts detection absence");
    }
  }
  const artifact = kind === "oneC" ? input.artifact : "yaxunit";
  if (kind === "oneC" && !group.artifacts.includes(artifact)) throw new Error(`unknown artifact: ${artifact}`);
  if (!group.operations.includes(input.operation)) throw new Error(`unknown operation: ${input.operation}`);
  const mechanisms = effectiveMechanisms(group, { ...input,
    detectedMechanisms: [...(input.detectedMechanisms ?? []), ...(input.detection?.detectedMechanisms ?? [])] });
  if (kind === "oneC" && mechanisms.some((mechanism) =>
    criticalMechanisms.includes(mechanism) && input.detection.coverage[mechanism].status === "absent")) {
    throw new Error("effective mechanism contradicts detection absence");
  }
  const rows = group.rules.filter((rule) => ruleMatches(rule, artifact, input.operation, mechanisms));
  if (kind === "oneC" && artifact === "metadata" && rows.length === 0) {
    throw new Error("metadata requirements require an explicit mechanism and normative resolution");
  }
  const mandatory = [...new Set(rows.filter((rule) => rule.strength === "mandatory").flatMap((rule) => rule.selectors))].sort();
  const recommended = [...new Set(rows.filter((rule) => rule.strength === "recommended").flatMap((rule) => rule.selectors))]
    .filter((selector) => !mandatory.includes(selector)).sort();
  if (mandatory.length + recommended.length === 0 && !["run", "report"].includes(input.operation)) {
    throw new Error("policy selection is empty; resolve uncovered mechanism");
  }
  const canonical = {
    schemaVersion: registry.schemaVersion, registryVersion: registry.registryVersion,
    kind, artifact, operation: input.operation, mechanisms, mandatory, recommended,
  };
  const digest = crypto.createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
  return { ...canonical, digest, matchedRows: rows.map((rule) => rule.id),
    ...(kind === "oneC" ? { detectionSourceRef: input.detection.sourceRef } : {}) };
}

export function validateCompliance(selection, ledger, current = {}, registry = loadRegistry(), phase = "proposal") {
  try {
    if (!["proposal", "result"].includes(phase)) throw new Error("invalid compliance phase");
    return { ...checkCompliance(selection, ledger, current, registry), phase };
  } catch (error) { throw new Error(`${phase}: ${error.message}`); }
}

function checkCompliance(selection, ledger, current, registry) {
  if (!selection || typeof selection !== "object" || !Array.isArray(ledger)) throw new Error("invalid compliance request");
  if (selection.registryVersion !== registry.registryVersion || selection.schemaVersion !== registry.schemaVersion) {
    throw new Error("stale policy registry selection");
  }
  if (selection.kind === "oneC" && !current.detection) throw new Error("current mechanism detection required");
  const fresh = select(selection.kind, {
    artifact: selection.artifact, operation: selection.operation,
    mechanisms: current.mechanisms ?? selection.mechanisms,
    classifiedMechanisms: current.classifiedMechanisms,
    detectedMechanisms: current.detectedMechanisms,
    unknownMechanisms: current.unknownMechanisms,
    detection: current.detection,
  }, registry);
  if (fresh.digest !== selection.digest || !Array.isArray(selection.mandatory) ||
      !Array.isArray(selection.recommended) ||
      JSON.stringify(fresh.mandatory) !== JSON.stringify(selection.mandatory) ||
      JSON.stringify(fresh.recommended) !== JSON.stringify(selection.recommended)) {
    throw new Error("selection digest mismatch or changed mechanisms; reselect requirements");
  }
  const byRule = new Map();
  for (const entry of ledger) {
    if (!entry || typeof entry.rule_id !== "string" || byRule.has(entry.rule_id) ||
        entry.selection_digest !== selection.digest || typeof entry.target !== "string" || !entry.target.trim() ||
        typeof entry.evidence !== "string" || !entry.evidence.trim()) {
      throw new Error("invalid or duplicate compliance ledger entry");
    }
    byRule.set(entry.rule_id, entry);
  }
  const missing = [...selection.mandatory, ...selection.recommended].filter((id) => !byRule.has(id));
  const extra = [...byRule.keys()].filter((id) => !selection.mandatory.includes(id) && !selection.recommended.includes(id));
  if (missing.length || extra.length) throw new Error(`compliance ledger coverage mismatch: missing=${missing.join(",")} extra=${extra.join(",")}`);
  const blocking = selection.mandatory.filter((id) => !["passed"].includes(byRule.get(id).status));
  if (blocking.length) throw new Error(`mandatory requirements unresolved or violated: ${blocking.join(",")}`);
  for (const id of selection.recommended) {
    const entry = byRule.get(id);
    if (!entry || !["passed", "deviated"].includes(entry.status) ||
        (entry.status === "deviated" && (typeof entry.reason !== "string" || !entry.reason.trim()))) {
      throw new Error(`recommended requirement lacks a valid status or deviation reason: ${id}`);
    }
  }
  for (const entry of ledger) validateSchema(ledgerItemSchema, entry, "ledger item");
  return { status: "passed", digest: selection.digest, checked: selection.mandatory.length };
}
