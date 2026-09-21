import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { visibleTools, callTool } from "../policy/read-only-mcp.mjs";
import { criticalMechanisms, detectMechanisms, expandDetection } from "../policy/detector.mjs";
import { select, validateCompliance } from "../policy/selector.mjs";
import { validateSchema } from "../policy/schema.mjs";
import { withStdioMcp, jsonToolResult } from "../mcp/stdio-client.mjs";
import { checkPolicySurface, checkPolicyProfile, profileFiles } from "../policy/profile.mjs";
import { describeEdtExposure } from "../mcp/doctor-probes.mjs";

const assessments = Object.fromEntries(criticalMechanisms.map((name) => [name,
  { status: ["query_text", "query_in_loop"].includes(name) ? "present" : "absent", evidence: `verified ${name}` }]));
const evidence = { sourceRef: "synthetic:contract:v1", assessments };
const verbose = detectMechanisms(evidence), compact = detectMechanisms({ ...evidence, format: "compact" });
assert.deepEqual(expandDetection(compact), verbose);
assert.ok(Buffer.byteLength(JSON.stringify(compact)) < Buffer.byteLength(JSON.stringify(verbose)));
const input = { artifact: "bsl", operation: "change", mechanisms: [], detection: verbose };
const selection = select("oneC", input);
assert.deepEqual(select("oneC", { ...input, detection: compact }), selection);
const ledger = [...selection.mandatory, ...selection.recommended].map((rule_id) => ({
  rule_id, selection_digest: selection.digest, target: "Synthetic.Query", status: "passed", evidence: "checked exact fixture",
}));
const args = { phase: "proposal", selection, ledger, current: { detection: compact } };
const schema = visibleTools().find((x) => x.name === "validate_compliance").inputSchema;
for (const phase of ["proposal", "result"]) {
  assert.equal(callTool("validate_compliance", { ...args, phase }).phase, phase);
  assert.equal(validateCompliance(selection, ledger, { detection: verbose }, undefined, phase).digest, selection.digest);
  const invalid = structuredClone(args); invalid.phase = phase; invalid.ledger[0].status = "compliant";
  assert.throws(() => callTool("validate_compliance", invalid), new RegExp(`^Error: ${phase}:`));
}
assert.equal(callTool("validate_compliance", { selection, ledger, current: args.current }).phase, "proposal");
const recommended = ledger.findIndex((x) => selection.recommended.includes(x.rule_id));
assert.ok(recommended >= 0);
const deviated = structuredClone(args);
Object.assign(deviated.ledger[recommended], { status: "deviated", reason: "documented exception checked" });
assert.equal(callTool("validate_compliance", deviated).status, "passed");
for (const change of [
  (x) => { x.ledger[0].status = "compliant"; },
  (x) => { x.ledger[0].status = "satisfied"; },
  (x) => { delete x.ledger[0].status; },
  (x) => { delete x.ledger[0].evidence; },
  (x) => { x.ledger[0].evidence = " "; },
  (x) => { x.ledger[0].unknown = true; },
  (x) => { x.ledger[recommended].status = "deviated"; },
  (x) => { x.ledger[recommended].status = "deviated"; x.ledger[recommended].reason = " "; },
  (x) => { x.phase = "complete"; },
  (x) => { x.current.extra = true; },
]) {
  const invalid = structuredClone(args); change(invalid);
  assert.throws(() => validateSchema(schema, invalid));
  assert.throws(() => callTool("validate_compliance", invalid));
}
for (const change of [
  (x) => { x.ledger.push(x.ledger[0]); },
  (x) => { x.ledger[0].selection_digest = "stale"; },
  (x) => { x.selection.digest = "stale"; },
  (x) => { x.selection.registryVersion = "2000-01-01.1"; },
  (x) => { x.ledger[0].status = "deviated"; x.ledger[0].reason = "cannot waive mandatory"; },
  (x) => { x.current.detection.coverage.find((r) => r[0] === "explicit_transaction")[1] = "present"; },
]) {
  const invalid = structuredClone(args); change(invalid);
  assert.throws(() => callTool("validate_compliance", invalid));
}
for (const change of [
  (x) => { x.coverage.pop(); },
  (x) => { x.coverage[1] = x.coverage[0]; },
  (x) => { x.coverage[0][1] = "unknown"; },
  (x) => { x.coverage[0][2] = ""; },
  (x) => { x.coverage[0].push("hidden"); },
  (x) => { x.extra = "ignored?"; },
]) {
  const invalid = structuredClone(compact); change(invalid);
  assert.throws(() => select("oneC", { ...input, detection: invalid }));
}
for (const change of [
  (x) => { x.assessments.query_text.status = "compliant"; },
  (x) => { x.assessments.unknown_name = { status: "absent", evidence: "bad" }; },
  (x) => { x.assessments.query_text.extra = true; },
]) {
  const invalid = structuredClone(evidence); change(invalid);
  assert.throws(() => callTool("detect_1c_mechanisms", invalid));
}
const unknown = callTool("detect_1c_mechanisms", { sourceRef: "synthetic:unknown", assessments: {}, format: "compact" });
assert.equal(expandDetection(unknown).unknownMechanisms.length, 13);
assert.throws(() => callTool("select_1c_requirements", { ...input, detection: unknown }));
const contradict = structuredClone(evidence); contradict.assessments.query_text.status = "absent";
assert.throws(() => callTool("detect_1c_mechanisms", { ...contradict, sourceText: "Новый Запрос" }), /contradictory/);
const actual = await withStdioMcp(process.execPath, [fileURLToPath(new URL("../policy/read-only-mcp.mjs", import.meta.url))], async ({ request }) => {
  const actualTools = (await request("tools/list")).tools;
  checkPolicySurface(actualTools);
  assert.deepEqual(actualTools, visibleTools());
  assert.equal(jsonToolResult(await request("tools/call", { name: "validate_compliance", arguments: args })).phase, "proposal");
  const invalid = structuredClone(args); invalid.ledger[0].status = "compliant";
  const failed = await request("tools/call", { name: "validate_compliance", arguments: invalid });
  assert.equal(failed.isError, true);
  assert.match(failed.content[0].text, /proposal:.*expected one of passed, deviated/);
  return actualTools;
});
actual.find((x) => x.name === "validate_compliance").inputSchema.properties.ledger.items = { type: "object" };
assert.throws(() => checkPolicySurface(actual), /mismatch/);
// No user profile is read: an injected in-memory reader models complete/mixed installs.
const fakeHome = path.resolve("tools/ai/tests/fixture-profile");
assert.equal(checkPolicyProfile({ CODEX_HOME: fakeHome }, () => "same\r\n").status, "ready");
for (const file of profileFiles) {
  const read = (name) => name === path.join(fakeHome, "skills", file) ? "old" : "current";
  assert.equal(checkPolicyProfile({ CODEX_HOME: fakeHome }, read).status, "error");
}
assert.equal(checkPolicyProfile({ CODEX_HOME: fakeHome }, () => { throw Error("missing"); }).status, "error");
const management = ["list_toolsets", "enable_toolset", "get_tool_guide"].map((name) => ({ name }));
assert.equal(describeEdtExposure({ server: management, visible: management }).toolsetsAdvertised, true);
assert.equal(describeEdtExposure({ server: [], visible: [] }).status, "unverified");
assert.deepEqual(describeEdtExposure({ server: management, visible: [] }).managementHidden,
  management.map((x) => x.name));
console.log("policy-contract: strict schema, both phases, compact equivalence/fail-closed, actual stdio surface and mixed profiles passed");
