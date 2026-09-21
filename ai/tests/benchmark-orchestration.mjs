import assert from "node:assert/strict";
import fs from "node:fs";
import { scenarios, simulate, metrics } from "./orchestration-scenarios.mjs";

const baselineUrl = new URL("./fixtures/orchestration-baseline.json", import.meta.url);
if (process.argv.includes("--capture-baseline")) {
  assert.ok(!fs.existsSync(baselineUrl), "Never overwrite the frozen pre-implementation baseline");
  fs.mkdirSync(new URL("./fixtures/", import.meta.url), { recursive: true });
  const traces = Object.fromEntries(scenarios.map((x) => [x.id, simulate(x)]));
  fs.writeFileSync(baselineUrl, JSON.stringify({ kind: "synthetic pre-SPEC-0014 traces, not LLM or billed tokens", traces }, null, 2) + "\n");
  console.log(JSON.stringify(Object.fromEntries(Object.entries(traces).map(([id, trace]) => [id, metrics(trace)])), null, 2));
} else {
  const baseline = JSON.parse(fs.readFileSync(baselineUrl, "utf8"));
  const report = {};
  for (const scenario of scenarios) {
    const before = metrics(baseline.traces[scenario.id]), trace = simulate(scenario, { optimized: true }), after = metrics(trace);
    const bytes = (m) => m.serialized_request_bytes + m.serialized_response_bytes;
    const reduction = 1 - bytes(after) / bytes(before);
    assert.equal(after.schema_failure_count, 0);
    assert.equal(after.retry_count, 0);
    assert.equal(after.repeated_equivalent_call_count, 0);
    assert.ok(after.candidate_fanout <= 5);
    assert.deepEqual(trace.filter((x) => x.check).map((x) => x.check),
      baseline.traces[scenario.id].filter((x) => x.check).map((x) => x.check));
    if (scenario.alias) assert.ok(reduction >= 0.30, `${scenario.id}: byte reduction ${reduction}`);
    report[scenario.id] = { before, after, reduction_percent: +(reduction * 100).toFixed(2) };
  }
  console.log(JSON.stringify(report, null, 2));
}
