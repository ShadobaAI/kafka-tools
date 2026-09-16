import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadRegistry, select, validateCompliance } from "../policy/selector.mjs";
import { visibleTools, callTool } from "../policy/read-only-mcp.mjs";
import { criticalMechanisms, detectMechanisms } from "../policy/detector.mjs";

const registry = loadRegistry();
assert.deepEqual(visibleTools().map((item) => item.name),
  ["detect_1c_mechanisms", "select_1c_requirements", "select_yaxunit_requirements", "validate_compliance"]);
assert.ok(visibleTools().every((item) => item.annotations.readOnlyHint));
assert.equal(registry.oneC.rules.length, 48);
assert.equal(registry.yaxunit.rules.length, 16);
const absent = Object.fromEntries(criticalMechanisms.map((name) =>
  [name, { status: "absent", evidence: "bounded authorized source and structure checked" }]));
const detection = detectMechanisms({ sourceRef: "EDT:fixture", assessments: absent });
const oneC = (input) => select("oneC", { ...input, detection }, registry);
assert.deepEqual(detection.unknownMechanisms, []);
assert.ok(detectMechanisms({ sourceRef: "EDT:fixture", assessments: {} }).unknownMechanisms.includes("query_in_loop"));
assert.ok(detectMechanisms({ sourceRef: "EDT:fixture", sourceText: "НачатьТранзакцию();", assessments: {} })
  .detectedMechanisms.includes("explicit_transaction"));
assert.throws(() => detectMechanisms({ sourceRef: "EDT:fixture", sourceText: "Попытка", assessments: absent }), /contradictory/);

// Migration gate: every exact selector in the old prompt tables is present in the registry.
const fixtureRoot = path.dirname(fileURLToPath(import.meta.url));
const legacy1C = fs.readFileSync(path.join(fixtureRoot, "legacy-requirements.md"), "utf8");
const corporateTable = legacy1C.split(/## Corporate selectors\r?\n/)[1].split("## General standards")[0];
const generalTable = legacy1C.split(/## General standards\r?\n/)[1];
const legacySelectors = new Set();
for (const line of corporateTable.split(/\r?\n/).filter((value) => value.startsWith("| ") && !value.startsWith("|---"))) {
  const rhs = line.split("|")[2];
  if (!rhs || rhs.includes("Document / exact headings")) continue;
  for (const token of rhs.match(/`[^`]+`/g) ?? []) {
    const content = token.slice(1, -1);
    const [name, headings] = content.split(" / ");
    const id = `corporate:work:${name.split(" ")[0]}:overview`;
    if (headings) for (const heading of headings.split(";").map((part) => part.trim())) legacySelectors.add(`${id}#${heading}`);
    else legacySelectors.add(id);
  }
}
for (const id of generalTable.match(/std\d+/g) ?? []) legacySelectors.add(id);
const migrated1C = new Set(registry.oneC.rules.flatMap((rule) => rule.selectors));
assert.deepEqual([...legacySelectors].filter((selector) => !migrated1C.has(selector)), []);
const legacyYaxunit = fs.readFileSync(path.join(fixtureRoot, "legacy-yaxunit-routing.md"), "utf8")
  .split(/## Pattern routing\r?\n/)[1];
const migratedYaxunit = new Set(registry.yaxunit.rules.flatMap((rule) => rule.selectors));
for (const line of legacyYaxunit.split(/\r?\n/).filter((value) => value.startsWith("| ") && !value.startsWith("|---"))) {
  const rhs = line.split("|")[2];
  if (!rhs || rhs.includes("Required pattern IDs")) continue;
  for (const token of rhs.match(/`[^`]+`/g) ?? []) {
    const name = token.slice(1, -1).replace(/^yaxunit:patterns:/, "");
    assert.ok(migratedYaxunit.has(`yaxunit:patterns:${name}`), name);
  }
}

const queryDetection = detectMechanisms({ sourceRef: "EDT:fixture", assessments: {
  ...absent, query_in_loop: { status: "present", evidence: "structured loop containing query call" },
  query_text: { status: "present", evidence: "query text" },
} });
const query = select("oneC", { artifact: "bsl", operation: "change",
  mechanisms: ["existence_query"], detection: queryDetection }, registry);
assert.ok(query.recommended.includes("std436"));
assert.ok(query.mandatory.includes("std438"));
assert.ok(query.mandatory.includes("std437"));
assert.ok(query.mandatory.includes("corporate:work:query-conventions:overview#Запросы в цикле"));
assert.equal(query.mandatory.filter((id) => id === "std437").length, 1);
assert.deepEqual(query.mechanisms, ["existence_query", "query_in_loop", "query_text"]);
assert.equal(query.digest, select("oneC", { artifact: "bsl", operation: "change",
  mechanisms: ["existence_query", "query_in_loop"], detection: queryDetection }, registry).digest);
assert.notEqual(query.digest, oneC({ artifact: "bsl", operation: "change",
  mechanisms: ["method_contract"] }).digest);
assert.throws(() => oneC({ artifact: "bsl", operation: "change",
  mechanisms: ["unregistered_mechanism"] }), /unknown required mechanism/);
assert.throws(() => oneC({ artifact: "bsl", operation: "change",
  mechanisms: [], unknownMechanisms: ["query_in_loop"] }), /unresolved/);
assert.throws(() => oneC({ artifact: "metadata", operation: "change",
  mechanisms: [] }), /metadata requirements/);
assert.throws(() => oneC({ artifact: "bsl", operation: "change",
  mechanisms: ["explicit_transaction"] }), /contradicts detection absence/);
assert.throws(() => select("oneC", { artifact: "bsl", operation: "change", mechanisms: [] }, registry), /incomplete/);
assert.throws(() => select("oneC", { artifact: "bsl", operation: "change", mechanisms: [],
  detection: { ...detection, coverage: { ...detection.coverage,
    query_text: { status: "absent", evidence: "" } } } }, registry), /incomplete/);
const fixtureDir = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-policy-schema-"));
try {
  const fixture = path.join(fixtureDir, "unknown.json");
  fs.writeFileSync(fixture, JSON.stringify({ ...registry, schemaVersion: 2 }));
  assert.throws(() => loadRegistry(fixture), /unsupported policy registry version/);
} finally {
  fs.rmSync(fixtureDir, { recursive: true, force: true });
}

const tests = select("yaxunit", { operation: "change", mechanisms: ["persistent_data", "database_assertion"] }, registry);
assert.ok(tests.mandatory.includes("yaxunit:patterns:data-isolation"));
assert.ok(tests.mandatory.includes("yaxunit:patterns:test-data"));
assert.ok(tests.mandatory.includes("yaxunit:patterns:assertions"));
assert.ok(!tests.mandatory.includes("yaxunit:patterns:authoring-baseline"));
const review = select("yaxunit", { operation: "review", mechanisms: [] }, registry);
assert.deepEqual(review.mandatory, ["yaxunit:patterns:test-analysis-and-migration"]);
const run = select("yaxunit", { operation: "run", mechanisms: [] }, registry);
assert.deepEqual(run.mandatory, []);

const ledger = query.mandatory.map((rule_id) => ({ rule_id, selection_digest: query.digest,
  target: "Method.Query", status: "passed", evidence: "checked exact section against proposed change" }));
ledger.push(...query.recommended.map((rule_id) => ({ rule_id, selection_digest: query.digest,
  target: "Method.Query", status: "deviated", evidence: "batch processing exception checked", reason: "std436 §2" })));
const current = { detection: queryDetection };
assert.equal(validateCompliance(query, ledger, current, registry).status, "passed");
assert.throws(() => validateCompliance(query, ledger.slice(1), current, registry), /coverage mismatch/);
assert.throws(() => validateCompliance(query, [{ ...ledger[0], status: "unresolved" }, ...ledger.slice(1)], current, registry), /unresolved or violated/);
// A permitted std436 exception cannot waive the mandatory corporate justification.
const loopRule = "corporate:work:query-conventions:overview#Запросы в цикле";
for (const status of ["violated", "deviated", "not-applicable"]) {
  const rejected = ledger.map((entry) => entry.rule_id === loopRule ?
    { ...entry, status, reason: "portion processing under std436 section 2" } : entry);
  assert.throws(() => validateCompliance(query, rejected, current, registry), /unresolved or violated/);
}
const postLedger = structuredClone(ledger).map((entry) => ({ ...entry,
  evidence: "fixture result checked against the same selected rule and documented exception" }));
assert.equal(validateCompliance(query, postLedger, current, registry).digest, query.digest);
const expandedDetection = detectMechanisms({ sourceRef: "EDT:changed-fixture", assessments: {
  ...absent,
  query_in_loop: { status: "present", evidence: "structured loop containing query call" },
  query_text: { status: "present", evidence: "query text" },
  exception_handler: { status: "present", evidence: "new exception handler" },
} });
assert.throws(() => validateCompliance(query, ledger, { detection: expandedDetection }, registry), /digest mismatch/);
assert.throws(() => validateCompliance({ ...query, digest: "bad" }, ledger, current, registry), /digest mismatch/);
assert.throws(() => validateCompliance(query, ledger.slice(0, -1), current, registry), /coverage mismatch/);
assert.throws(() => validateCompliance(query, [{ ...ledger.at(-1), reason: "" }, ...ledger.slice(0, -1)], current, registry), /deviation reason/);
assert.equal(callTool("select_yaxunit_requirements", { operation: "run", mechanisms: [] }, registry).mandatory.length, 0);
assert.throws(() => callTool("remember", {}, registry), /unknown policy tool/);

if (process.env.V8STD_REPO) {
  const root = path.resolve(process.env.V8STD_REPO);
  const all = new Set([...registry.oneC.rules, ...registry.yaxunit.rules].flatMap((rule) => rule.selectors));
  for (const selector of all) {
    if (selector.startsWith("std")) {
      assert.ok(fs.existsSync(path.join(root, "docs", "std", `${selector.slice(3)}.md`)), selector);
    } else if (selector.startsWith("corporate:")) {
      const [id, heading] = selector.split("#");
      const file = path.join(root, "docs", "corporate", "work", `${id.split(":")[2]}.md`);
      const content = fs.readFileSync(file, "utf8");
      assert.ok(content.includes(`id: ${id.replace(/:overview$/, "")}`), selector);
      if (heading) assert.ok(content.split(/\r?\n/).some((line) => /^#{2,6} /.test(line) && line.slice(line.indexOf(" ") + 1) === heading), selector);
    } else {
      const file = path.join(root, "docs", "yaxunit", "patterns", `${selector.split(":").at(-1)}.md`);
      assert.ok(fs.readFileSync(file, "utf8").includes(`id: ${selector}`), selector);
    }
  }
}
process.stdout.write("policy: registry, selection, exact selectors, and compliance gates passed\n");
