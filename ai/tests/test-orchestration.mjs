// Trace acceptance oracle for skill contracts. This is not a runtime agent or
// semantic server-side deduplicator. No live source or normative corpus is used.
import assert from "node:assert/strict";
import fs from "node:fs";
import { scenarios, simulate } from "./orchestration-scenarios.mjs";

const text = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), "utf8");
const agents = text("AGENTS.md"), change = text(".codex/skills/1c-code-change/SKILL.md"),
  index = text(".codex/skills/1c-code-index/SKILL.md"), routing = text(".codex/skills/1c-routing/SKILL.md"),
  requirements = text(".codex/skills/1c-code-change/references/requirements.md");
for (const phrase of ["recoverable-workflow", "correctable-invocation", "transient-retryable", "infrastructure",
  "authority-contradiction", "unsafe-or-out-of-scope", "unknown", "no new user-triggered run",
  "never blindly retry a write", "stop condition", "Never access configuration or extension source trees under `src/**`"])
  assert.ok(agents.includes(phrase), phrase);
for (const phrase of ["mandatory $1c-code-index reuse-gate", "are exempt", "**L**", "**M**", "**H**",
  "never diff size", "production public API", "client/server", "module persistent state", "focused EDT baseline",
  "actual result", "stricter tier", "phase: proposal", "phase: result"]) assert.ok(change.includes(phrase), phrase);
for (const phrase of ["1–3 terms", "at most 5", "get_function", "non-exported", "repository ownership",
  "one unresolved", "new unresolved fact", "no duplicate EDT discovery fallback"].filter((x) => x !== "one unresolved"))
  assert.ok(index.includes(phrase), phrase);
assert.ok(requirements.includes("never unchanged full selectors twice"));
assert.ok(routing.includes("Reuse successfully enabled toolsets"));
assert.ok(routing.includes("never invent a server preference"));
assert.ok(agents.includes("Do not load it for unrelated repository, tooling, Git"));

function auditCanonical(trace, scenario) {
  const facts = new Set(), norms = new Set(); let selections = 0;
  for (const entry of trace) {
    if (entry.invalidation) {
      const event = entry.invalidation;
      assert.ok(["mutation", "reindex", "reconnect", "registry-change", "artifact-change", "contradiction"].includes(event.reason));
      for (const key of facts) if (event.facts?.includes(JSON.parse(key)[1])) facts.delete(key);
      for (const selector of event.norms ?? []) norms.delete(selector);
      if (event.selection) selections = 0;
      continue;
    }
    assert.ok(!entry.response.error, "unexpected schema failure");
    if (entry.fact) {
      const key = JSON.stringify([entry.server, entry.fact, entry.request]);
      assert.ok(!facts.has(key), "repeated discovery"); facts.add(key);
    }
    if (entry.normative) { assert.ok(!norms.has(entry.normative), "repeated normative retrieval"); norms.add(entry.normative); }
    if (entry.request.name === "select_1c_requirements") selections++;
    if (entry.request.arguments.repo && scenario.alias) assert.equal(entry.request.arguments.repo, scenario.alias);
    if (entry.server.endsWith("-edt")) assert.equal(entry.server, scenario.server);
    if (!scenario.alias) assert.equal(entry.server, "repository", "non-1C overhead");
  }
  assert.equal(selections, scenario.alias ? 1 : 0, "repeated selection");
}
for (const scenario of scenarios) {
  assert.ok(agents.includes(`\`${scenario.repo}\``));
  if (scenario.alias) {
    // Routes come from the shared instructions; the fixture must not silently drift.
    const row = agents.split(/\r?\n/).find((line) => line.startsWith(`| \`${scenario.repo}\` |`) && line.includes("876"));
    assert.ok(row.includes(scenario.server));
    assert.ok(agents.split(/\r?\n/).some((line) => line.startsWith(`| \`${scenario.repo}\` |`) && line.includes(`\`${scenario.alias}\``)));
  }
  auditCanonical(simulate(scenario, { optimized: true }), scenario);
}
const unit = scenarios.find((x) => x.id === "unit"), good = simulate(unit, { optimized: true });
for (const [name, message] of [["search_terms", /repeated discovery/], ["exact_selector", /repeated normative/],
  ["select_1c_requirements", /repeated selection/]]) {
  assert.throws(() => auditCanonical([...good, good.find((x) => x.request.name === name)], unit), message);
}
const wrongRoute = structuredClone(good); wrongRoute.find((x) => x.server === "unit-edt").server = "kfk-edt";
assert.throws(() => auditCanonical(wrongRoute, unit));
// Relevant invalidation permits a new question; unrelated facts remain reusable.
const discovery = good.find((x) => x.request.name === "search_terms");
const normative = good.find((x) => x.normative);
const selected = good.find((x) => x.request.name === "select_1c_requirements");
auditCanonical([...good, { invalidation: { reason: "reindex", facts: ["reuse"] } }, discovery], unit);
assert.throws(() => auditCanonical([...good, { invalidation: { reason: "mutation", facts: ["other-target"] } }, discovery], unit), /repeated discovery/);
auditCanonical([...good, { invalidation: { reason: "registry-change", selection: true, norms: [normative.normative] } }, selected, normative], unit);
assert.throws(() => auditCanonical([...good, { invalidation: { reason: "reconnect", facts: ["reuse"] } }, normative], unit), /repeated normative/);
assert.throws(() => auditCanonical([...good, { invalidation: { reason: "mutation", facts: ["target"] } }, selected], unit), /repeated selection/);

const excludedL = ["production-api", "production-contract", "metadata", "query", "transaction", "privileged",
  "full-access", "client-server", "module-state", "security", "external-protocol", "cross-repository", "destructive", "uncertain"];

function auditDecision({ standalone = true, trivial = false, tier = "M", risks = [], candidates = [],
  coverage = "ready", escalationReason, steps, recovery }) {
  if (tier === "L") assert.ok(!risks.some((x) => excludedL.includes(x)), "unsafe Tier L");
  if (risks.some((x) => ["production-api", "metadata", "security", "cross-repository", "destructive", "uncertain"].includes(x)))
    assert.equal(tier, "H", "requires high-risk controls");
  if (candidates.length > 5) assert.ok(["ambiguity", "insufficient coverage", "conflicting candidates"].includes(escalationReason), "candidate budget");
  const mutate = steps.includes("mutate"), reuse = steps.includes("reuse"), create = steps.includes("create");
  if (standalone && !trivial && (reuse || create)) {
    assert.ok(steps.includes("search_terms"), "mandatory reuse gate");
    assert.equal(coverage, "ready", "stale/partial search cannot prove absence");
    if (candidates.length) assert.ok(steps.includes("get_function"), "inspect candidates");
    if (candidates.some((x) => x.compatible && x.exported)) assert.ok(reuse && !create, "duplicate implementation");
    if (candidates.some((x) => x.compatible && !x.exported)) assert.ok(steps.includes("inspect_owner"), "private method owner");
    if (create) assert.ok(candidates.every((x) => !x.compatible || x.mismatch), "contract mismatch evidence");
  }
  if (steps.includes("mutate_dependency")) assert.ok(steps.includes("authorize_dependency"), "reuse does not expand scope");
  if (recovery) {
    const { category, safe = false, attempts = 0, idempotent = false, documented = false } = recovery;
    if (["infrastructure", "authority-contradiction", "unsafe-or-out-of-scope", "unknown"].includes(category)) {
      assert.ok(!mutate && !steps.includes("fallback_discovery"), "blocked authority");
    } else {
      assert.ok(["recoverable-workflow", "correctable-invocation", "transient-retryable"].includes(category));
      assert.ok(safe, "recovery outside authorized safe scope");
      if (category === "recoverable-workflow") assert.ok(steps.indexOf("validate_recovery") > steps.indexOf("recover") &&
        (!mutate || steps.indexOf("validate_recovery") < steps.indexOf("mutate")), "recovery validation");
      else assert.ok(attempts <= 1 && (category !== "transient-retryable" || idempotent || documented), "retry budget/safety");
    }
  }
  if (steps.includes("write_timeout")) {
    assert.ok(steps.includes("verify_authoritative"), "indeterminate write needs verification");
    assert.ok(!steps.includes("retry_write"), "blind write retry");
  }
}
// S1–S3, private owner, trivial exemption and cross-repository candidate.
const exported = { compatible: true, exported: true };
auditDecision({ candidates: [exported], steps: ["search_terms", "get_function", "reuse"] });
assert.throws(() => auditDecision({ candidates: [exported], steps: ["search_terms", "get_function", "create"] }), /duplicate/);
auditDecision({ candidates: [{ compatible: false, mismatch: "server context" }], steps: ["search_terms", "get_function", "create"] });
auditDecision({ steps: ["search_terms", "create"] });
auditDecision({ candidates: [{ compatible: true, exported: false, mismatch: "owner cannot be used within scope" }],
  steps: ["search_terms", "get_function", "inspect_owner", "create"] });
auditDecision({ trivial: true, steps: ["create"] });
assert.throws(() => auditDecision({ steps: ["create"] }), /reuse gate/);
auditDecision({ candidates: [exported], steps: ["search_terms", "get_function", "reuse"] });
assert.throws(() => auditDecision({ steps: ["mutate_dependency"] }), /does not expand/);
assert.throws(() => auditDecision({ candidates: Array(6).fill(exported), steps: [] }), /budget/);
auditDecision({ candidates: Array(6).fill(exported), escalationReason: "ambiguity", steps: [] });
// S4: missing adopted object, then validate and continue without another user turn.
auditDecision({ steps: ["recover", "validate_recovery", "mutate"], recovery: { category: "recoverable-workflow", safe: true } });
assert.throws(() => auditDecision({ steps: ["recover", "mutate"], recovery: { category: "recoverable-workflow", safe: true } }));
// S5/S6 and all blocking categories. No EDT substitution after a stale index.
for (const category of ["infrastructure", "authority-contradiction", "unsafe-or-out-of-scope", "unknown"]) {
  auditDecision({ steps: ["stop"], recovery: { category } });
  assert.throws(() => auditDecision({ steps: ["mutate"], recovery: { category } }), /blocked authority/);
  assert.throws(() => auditDecision({ steps: ["fallback_discovery"], recovery: { category } }), /blocked authority/);
}
assert.throws(() => auditDecision({ coverage: "stale", steps: ["search_terms", "create"] }), /stale/);
for (const category of ["correctable-invocation", "transient-retryable"]) {
  auditDecision({ steps: ["continue"], recovery: { category, safe: true, attempts: 1, idempotent: true } });
  assert.throws(() => auditDecision({ steps: ["continue"], recovery: { category, safe: true, attempts: 2, idempotent: true } }), /retry/);
}
assert.throws(() => auditDecision({ steps: ["continue"], recovery: { category: "transient-retryable", safe: true, attempts: 1 } }));
// S8–S10: low-risk wrapper vs queries, production API/schema and uncertain risk.
auditDecision({ tier: "L", steps: [] });
for (const risk of excludedL) assert.throws(() => auditDecision({ tier: "L", risks: [risk], steps: [] }), /unsafe Tier L/);
auditDecision({ tier: "M", risks: ["query"], steps: [] });
for (const risk of ["production-api", "metadata", "uncertain"]) {
  auditDecision({ tier: "H", risks: [risk], steps: [] });
  assert.throws(() => auditDecision({ tier: "M", risks: [risk], steps: [] }), /high-risk/);
}
// S12: an uncertain write is inspected, not repeated.
auditDecision({ steps: ["write_timeout", "verify_authoritative"] });
assert.throws(() => auditDecision({ steps: ["write_timeout", "retry_write"] }), /indeterminate/);
assert.throws(() => auditDecision({ steps: ["write_timeout", "verify_authoritative", "retry_write"] }), /blind/);
console.log("orchestration: reuse, recovery, risk tiers, invalidation regressions, adapter/conversion/unit/non-1C routes passed (synthetic trace oracle)");
