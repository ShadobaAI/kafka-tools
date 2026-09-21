// Synthetic contracts, never project source or normative corpus.
import { callTool } from "../policy/read-only-mcp.mjs";
import { criticalMechanisms } from "../policy/detector.mjs";

export const scenarios = [
  { id: "adapter", repo: "adapter/adapter", alias: "kfk", server: "kfk-edt" },
  { id: "conversion", repo: "conversion/KFK", alias: "kfk-conv", server: "conv-edt" },
  { id: "unit", repo: "tests/unit/unit", alias: "kfk-unit", server: "unit-edt" },
  { id: "reports", repo: "tests/reports" },
  { id: "ui", repo: "tests/ui" },
];

export function simulate(scenario, { optimized = false } = {}) {
  const trace = [];
  const record = (server, name, args, response, tags = {}) => {
    trace.push({ server, request: { name, arguments: args }, response, ...tags });
    return response;
  };
  const policy = (name, args, tags) => {
    let response;
    try { response = callTool(name, args); }
    catch (error) { response = { error: error.message }; }
    return record("kafka-policy", name, args, response, tags);
  };
  if (!scenario.alias) {
    record("repository", "inspect_contract", { repo: scenario.repo }, { contract: "local report/UI glue" });
    record("repository", "focused_test", { repo: scenario.repo }, { passed: true }, { check: "behavior" });
    return trace;
  }
  record("code-index", "health", {}, { status: "healthy", alias: scenario.alias, state: "ready" });
  const discovery = () => record("code-index", "search_terms", { repo: scenario.alias, terms: ["delegate", "registration"] },
    { candidates: ["ExistingOwner.Register"] }, { fact: "reuse", candidates: 1 });
  discovery();
  record("code-index", "get_function", { repo: scenario.alias, name: "ExistingOwner.Register" },
    { contract: "compatible exported server method" }, { fact: "contract" });
  if (!optimized) discovery();
  record(scenario.server, "inspect_target", { target: "Synthetic.Wrapper" },
    { version: "v1", contract: "test-only delegate, same context, no production API" }, { check: "target" });
  const assessments = Object.fromEntries(criticalMechanisms.map((name) => [name,
    { status: "absent", evidence: `synthetic bounded ${name} assessment for wrapper and enclosing structure` }]));
  const detection = policy("detect_1c_mechanisms", { sourceRef: "synthetic:proposal:v1", assessments,
    ...(optimized ? { format: "compact" } : {}) });
  const input = { artifact: "bsl", operation: "change", mechanisms: ["method_contract"], detection };
  const selection = policy("select_1c_requirements", input);
  const retrieve = () => {
    for (const id of [...selection.mandatory, ...selection.recommended]) {
      record("v8std", "exact_selector", { id }, { id, body: "Synthetic complete normative fixture; not an actual standard.", truncated: false }, { normative: id });
    }
  };
  retrieve();
  const ledger = (status, phase) => [...selection.mandatory, ...selection.recommended].map((rule_id) => ({
    rule_id, selection_digest: selection.digest, target: "Synthetic.Wrapper", status,
    evidence: `synthetic ${phase} checked against complete fixture`,
  }));
  if (!optimized) for (const status of ["compliant", "satisfied"]) {
    policy("validate_compliance", { selection, ledger: ledger(status, "proposal"), current: { detection } }, { schemaGuess: true });
  }
  policy("validate_compliance", { selection, ledger: ledger("passed", "proposal"), current: { detection },
    ...(optimized ? { phase: "proposal" } : {}) });
  record(scenario.server, "focused_diagnostics", { target: "Synthetic.Wrapper" }, { findings: [] }, { check: "baseline" });
  record(scenario.server, "atomic_mutation", { target: "Synthetic.Wrapper", expectedVersion: "v1" },
    { version: "v2", actual: "same delegate, unchanged mechanisms" }, { check: "mutation" });
  record(scenario.server, "focused_diagnostics", { target: "Synthetic.Wrapper" }, { findings: [] }, { check: "result" });
  // Even L reassesses the actual result. Its authorized evidence may be retained;
  // only duplicate remote classification, selection and retrieval are eliminated.
  const resultDetection = optimized ? { ...detection, sourceRef: "synthetic:result:v2" }
    : policy("detect_1c_mechanisms", { sourceRef: "synthetic:result:v2", assessments });
  if (!optimized) {
    policy("select_1c_requirements", { ...input, detection: resultDetection });
    retrieve();
  }
  policy("validate_compliance", { selection, ledger: ledger("passed", "result"), current: { detection: resultDetection },
    ...(optimized ? { phase: "result" } : {}) });
  record(scenario.server, "focused_test", { target: "Synthetic.Wrapper" }, { passed: true }, { check: "behavior" });
  return trace;
}

export function metrics(trace) {
  const successfulDiscovery = trace.filter((x) => x.fact && !x.response.error);
  const keys = successfulDiscovery.map((x) => JSON.stringify([x.server, x.fact, x.request]));
  return {
    mcp_call_count: trace.length,
    serialized_request_bytes: trace.reduce((n, x) => n + Buffer.byteLength(JSON.stringify(x.request)), 0),
    serialized_response_bytes: trace.reduce((n, x) => n + Buffer.byteLength(JSON.stringify(x.response)), 0),
    full_normative_retrieval_count: trace.filter((x) => x.normative).length,
    repeated_equivalent_call_count: keys.length - new Set(keys).size,
    candidate_fanout: Math.max(0, ...trace.map((x) => x.candidates ?? 0)),
    schema_failure_count: trace.filter((x) => x.response.error).length,
    retry_count: trace.filter((x) => x.schemaGuess).length,
    distinct_authoritative_source_count: new Set(trace.map((x) => x.server)).size,
  };
}
