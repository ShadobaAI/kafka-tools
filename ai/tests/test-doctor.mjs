import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compareOpenVikingState, checkProjectRoot, diagnose, runtimeRoute, checkCodeIndexHealth, formatReport } from "../doctor.mjs";
import { withStdioMcp, jsonToolResult } from "../mcp/stdio-client.mjs";
import { readInstalledConfigs } from "../mcp/installed-config.mjs";
import { listTools, checkEdtProjects, checkBslResponse } from "../mcp/doctor-probes.mjs";
import { runHttpTests } from "./test-doctor-http.mjs";
import { resolveUpdateOptions, updateMode } from "../update-openviking.mjs";

const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const updateState = path.join(os.tmpdir(), "openviking fixture with spaces");
assert.deepEqual(updateMode([]), { forceRebuild: false, allowRebuild: false });
assert.deepEqual(updateMode(["--rebuild"]), { forceRebuild: true, allowRebuild: true });
assert.throws(() => updateMode(["--unknown"]));
const updateConfig = { name: "kafka-openviking", enabled: true,
  transport: { type: "stdio", args: ["server.mjs", "--workspace-root", workspaceRoot, "--state-dir", updateState] } };
assert.equal(resolveUpdateOptions({}, () => updateConfig).stateDir, updateState);
assert.equal(resolveUpdateOptions({ KAFKA_OPENVIKING_STATE_DIR: updateState }, () => { throw new Error("must not read config"); }).stateDir, updateState);
for (const config of [null, { ...updateConfig, enabled: false },
  { ...updateConfig, transport: { type: "stdio", args: ["--workspace-root", os.tmpdir(), "--state-dir", updateState] } },
  { ...updateConfig, transport: { type: "stdio", args: ["--workspace-root", workspaceRoot, "--state-dir", "relative"] } },
  { ...updateConfig, transport: { type: "stdio", args: [...updateConfig.transport.args, "--state-dir", updateState] } }]) {
  assert.throws(() => resolveUpdateOptions({}, () => config));
}

const current = { tasks: { revision: "a", files: { "sdd/x.md": "b" } } };
const state = { schemaVersion: 1, manifestDigest: "digest", runtimeVersion: "9.9.9",
  repositories: { tasks: { revision: "a", files: { "sdd/x.md": "b" } } } };
assert.equal(compareOpenVikingState(state, current, "digest", "9.9.9", false), "ready");
assert.equal(compareOpenVikingState(state, current, "digest", "9.9.9", true), "stale");
assert.equal(compareOpenVikingState(state, { tasks: { revision: "c", files: current.tasks.files } }, "digest", "9.9.9", false), "stale");
assert.equal(compareOpenVikingState(state, current, "changed", "9.9.9", false), "stale");
const noProbe = () => { throw new Error("unexpected probe"); };
const result = await diagnose({}, workspaceRoot, { configLoader: () => ({}), mcpProbe: noProbe, openVikingProbe: noProbe });
assert.equal(result.status, "not-ready");
assert.equal(result.checks.projectRoot.status, "ready");
for (const name of ["kafka-policy", "kafka-openviking", "v8std", "code-index", "kfk-edt", "conv-edt", "unit-edt"]) {
  assert.equal(result.checks[name].status, "missing", name);
}
assert.equal(Object.keys(result.checks).some((name) => name.startsWith("KAFKA_")), false);
assert.equal(result.checks.distribution, undefined);
const formatted = formatReport(result);
assert.match(formatted, /НЕ НАСТРОЕНО/);
assert.match(formatted, /MCP не зарегистрирован/);
assert.doesNotMatch(formatted, /KAFKA_CODE_INDEX_HOME|Переменная окружения/);
assert.equal(checkProjectRoot(workspaceRoot).kind, "workspace");
for (const relative of ["adapter/adapter", "conversion/KFK", "tests/unit/unit", "tools", "tasks"]) {
  assert.equal(checkProjectRoot(path.resolve(workspaceRoot, relative)).kind, "repository", relative);
}
assert.equal(checkProjectRoot(os.tmpdir()).status, "error");
assert.deepEqual(runtimeRoute(path.join(workspaceRoot, "conversion/KFK")).edt, ["conv-edt"]);
assert.deepEqual(runtimeRoute(path.join(workspaceRoot, "tests/unit/unit")).edt, ["unit-edt"]);
assert.deepEqual(runtimeRoute(path.join(workspaceRoot, "adapter/base")).edt, ["kfk-edt"]);
assert.deepEqual(runtimeRoute(path.join(workspaceRoot, "tools")).edt, []);
assert.equal(runtimeRoute(path.join(workspaceRoot, "tools/ai")).status, "error");
assert.equal(runtimeRoute(workspaceRoot).edt.length, 3);
const sharedNames = ["kafka-policy", "kafka-openviking", "v8std"];
const fixtureConfig = { command: "fixture-only", args: [], fixture: true };
const configured = (_env, _root, route) => Object.fromEntries([
  ...sharedNames, ...route.edt, ...(route.aliases.length ? ["code-index"] : []),
  ...route.bslLsOwners.map((owner) => `bsl-ls:${owner}`),
].map((name) => [name, fixtureConfig]));
let observed = [], openVikingCalls = 0;
const readyDependencies = {
  configLoader: configured,
  mcpProbe: async (name, config, env, options) => {
    assert.equal(config, fixtureConfig);
    assert.deepEqual(env, {});
    observed.push({ name, options });
    return { status: "ready" };
  },
  openVikingProbe: async (config) => { assert.equal(config, fixtureConfig); openVikingCalls++; return { status: "ready" }; },
};
const liveRoute = await diagnose({}, workspaceRoot, readyDependencies);
assert.equal(liveRoute.status, "ready");
assert.equal(openVikingCalls, 1);
assert.equal(observed.find((item) => item.name === "code-index").options.aliases.length, 7);
assert.equal(observed.filter((item) => item.options.edt).length, 3);
for (const [relative, edt, aliases] of [["tools", [], []],
  ["conversion/KFK", ["conv-edt"], ["kfk-conv", "kfk-conv-kd"]],
  ["adapter/adapter", ["kfk-edt"], ["kfk", "kfk-base", "kfk-examples"]]]) {
  observed = [];
  const report = await diagnose({}, path.join(workspaceRoot, relative), readyDependencies);
  assert.equal(report.status, "ready");
  assert.deepEqual(observed.filter((item) => item.options.edt).map((item) => item.name), edt);
  assert.deepEqual(observed.find((item) => item.name === "code-index")?.options.aliases ?? [], aliases);
  assert.equal(observed.some((item) => item.name.startsWith("bsl-ls:")), relative === "adapter/adapter");
}
const invalidRoute = await diagnose({}, path.join(workspaceRoot, "tools/ai"), {
  configLoader: noProbe, mcpProbe: noProbe, openVikingProbe: noProbe,
});
assert.equal(invalidRoute.status, "not-ready");
for (const failed of ["v8std", "code-index", "kfk-edt", "kafka-openviking"]) {
  openVikingCalls = 0;
  const report = await diagnose({}, workspaceRoot, { ...readyDependencies,
    mcpProbe: async (name) => ({ status: name === failed ? "error" : "ready" }),
  });
  assert.equal(report.status, "not-ready");
  assert.equal(report.checks[failed].status, "error");
  assert.equal(openVikingCalls, failed === "kafka-openviking" ? 0 : 1);
  if (failed === "kafka-openviking") assert.equal(report.checks.openviking, undefined);
}
assert.equal((await diagnose({}, workspaceRoot, { ...readyDependencies,
  openVikingProbe: async () => ({ status: "stale" }),
})).status, "not-ready");

// Configuration resolution uses only a fake Codex CLI and retains owned paths.
const readCalls = [];
const transport = { type: "stdio", command: "custom-node", args: ["custom/server.mjs"], cwd: "custom/cwd",
  env: { CUSTOM: "fixture-value" } };
const http = { type: "streamable_http", url: "https://fixture.invalid/custom-mcp", http_headers: { "X-Fixture": "static" },
  env_http_headers: { Authorization: "FIXTURE_TOKEN" }, bearer_token_env_var: null };
const fakeRead = (args, cwd, env) => {
  assert.deepEqual(args, ["get", args[1], "--json"]);
  assert.equal(env.FIXTURE, "configured");
  readCalls.push({ name: args[1], cwd });
  if (args[1] === "bsl-ls") return null;
  return { name: args[1], enabled: true, transport: args[1] === "v8std" ? http : transport,
    enabled_tools: ["health"], disabled_tools: ["mutate"], startup_timeout_sec: 12, tool_timeout_sec: 15 };
};
const conversionRoot = path.join(workspaceRoot, "conversion/KFK");
const configs = readInstalledConfigs({ FIXTURE: "configured" }, conversionRoot, runtimeRoute(conversionRoot), workspaceRoot, fakeRead);
assert.deepEqual(configs.v8std.http_headers, http.http_headers);
assert.deepEqual(configs.v8std.env_http_headers, http.env_http_headers);
assert.equal(configs.v8std.url, http.url);
assert.equal(configs.v8std.bearer_token_env_var, null);
assert.deepEqual(configs["code-index"].args, transport.args);
assert.deepEqual(configs["code-index"].env, transport.env);
assert.equal(configs["code-index"].cwd, transport.cwd);
assert.equal(configs["code-index"].command, transport.command);
assert.deepEqual(configs["code-index"].disabled_tools, ["mutate"]);
assert.equal(configs["code-index"].startup_timeout_sec, 12);
assert.equal(configs["conv-edt"].configCwd, conversionRoot);
assert.equal(configs["kafka-policy"].configCwd, conversionRoot);
assert.equal(configs["bsl-ls:conversion/KFK"], undefined);
assert.equal(readCalls.some((item) => ["kfk-edt", "unit-edt"].includes(item.name)), false);
const missingConfigs = readInstalledConfigs({}, workspaceRoot, runtimeRoute(workspaceRoot), workspaceRoot, () => null);
assert.ok(missingConfigs["kfk-edt"].error);
assert.ok(missingConfigs["bsl-ls:adapter/adapter"].error);
assert.equal(missingConfigs["bsl-ls:conversion/KFK"], undefined);
const brokenConfigs = readInstalledConfigs({}, conversionRoot, runtimeRoute(conversionRoot), workspaceRoot,
  () => { throw new Error("fixture CLI unavailable"); });
assert.equal(brokenConfigs.v8std.error, "fixture CLI unavailable");
assert.equal(brokenConfigs["conv-edt"].error, "fixture CLI unavailable");
const malformedConfigs = readInstalledConfigs({}, conversionRoot, runtimeRoute(conversionRoot), workspaceRoot,
  () => ({ name: "wrong-name", transport }));
assert.ok(malformedConfigs["conv-edt"].error);

let pages = 0;
assert.deepEqual(await listTools(async (method, params) => {
  assert.equal(method, "tools/list");
  assert.deepEqual(params, pages === 0 ? {} : { cursor: "page-2" });
  return pages++ === 0 ? { tools: [{ name: "health" }], nextCursor: "page-2" } : { tools: [{ name: "mutate" }] };
}, { enabled_tools: ["health", "mutate"], disabled_tools: ["mutate"] }), [{ name: "health" }]);
assert.equal(pages, 2);
await assert.rejects(listTools(async () => ({ tools: [{ name: "same" }], nextCursor: "repeat" }), {}), /повторяющиеся|пагинация/);
await assert.rejects(listTools(async () => ({ tools: [], nextCursor: "repeat" }), {}), /пагинация/);
await assert.rejects(listTools(async () => ({ tools: {} }), {}), /список/);
const edtStatus = { running: true, port: 8767 };
assert.equal(checkBslResponse({ count: 1, functions: [{ name: "Сообщить" }] }), true);
for (const response of [{}, [], null, { count: 0, functions: [] }, { count: 1, functions: [{ name: "unrelated" }] },
  { error: "failed", count: 1, functions: [{ name: "Сообщить" }] }, { success: false, count: 1, functions: [{ name: "Сообщить" }] }]) {
  assert.equal(checkBslResponse(response), false);
}
const edtProjects = { projects: [{ path: conversionRoot, state: "ready", open: true, edtProject: true }] };
assert.equal(checkEdtProjects(edtStatus, edtProjects, [conversionRoot], 8767).status, "ready");
assert.equal(checkEdtProjects({ ...edtStatus, port: 8765 }, edtProjects, [conversionRoot], 8767).status, "error");
assert.equal(checkEdtProjects({ ...edtStatus, running: false }, edtProjects, [conversionRoot], 8767).status, "error");
for (const change of [
  (value) => { value.projects = []; },
  (value) => { value.projects[0].open = false; },
  (value) => { value.projects[0].state = "building"; },
  (value) => { value.projects[0].edtProject = false; },
  (value) => { value.projects[0].path = path.join(workspaceRoot, "adapter/adapter"); },
  (value) => { value.projects.push({ ...value.projects[0] }); },
]) {
  const value = structuredClone(edtProjects);
  change(value);
  assert.equal(checkEdtProjects(edtStatus, value, [conversionRoot], 8767).status, "error");
}
const health = { mcp: { status: "ok" }, daemon: { state: "healthy", status: "online",
  endpoint_verified: true, process_alive: true }, repos: [{ repo: "kfk",
  root_path: path.join(workspaceRoot, "adapter/adapter"),
  path_status: { status: "ready", path: path.join(workspaceRoot, "adapter/adapter") } }] };
assert.equal(checkCodeIndexHealth(health, ["kfk"]).status, "ready");
assert.equal(checkCodeIndexHealth(health, ["kfk-unit"]).status, "error");
for (const mutate of [
  (item) => { item.daemon.endpoint_verified = false; },
  (item) => { item.daemon.state = "degraded"; },
  (item) => { item.repos[0].path_status.status = "stale"; },
  (item) => { item.repos[0].root_path = path.join(workspaceRoot, "tests/unit/base"); },
  (item) => { item.repos[0].path_status.path = path.join(workspaceRoot, "tests/unit/base"); },
  (item) => { item.repos.push(structuredClone(item.repos[0])); },
]) {
  const changed = structuredClone(health);
  mutate(changed);
  assert.equal(checkCodeIndexHealth(changed, ["kfk"]).status, "error");
}
assert.equal(checkCodeIndexHealth(null, ["kfk"]).status, "error");
const server = `
let initialized = false;
require('node:readline').createInterface({input: process.stdin}).on('line', line => {
  const m = JSON.parse(line);
  if (m.method === 'notifications/initialized') { initialized = true; return; }
  const result = m.method === 'initialize' ? { protocolVersion: '2024-11-05', serverInfo: {name: 'fixture', version: '1'} } :
    {content: [{type: 'text', text: JSON.stringify({initialized, label: 'готово'})}]};
  process.stdout.write(JSON.stringify({jsonrpc: '2.0', id: m.id, result}) + '\\n');
});`;
const answer = await withStdioMcp(process.execPath, ["-e", server], async ({ request }) =>
  jsonToolResult(await request("tools/call", { name: "health", arguments: {} })));
assert.deepEqual(answer, { initialized: true, label: "готово" });
for (const [script, pattern, options] of [
  ["process.exit(1)", /transport closed/, {}],
  ["process.stdout.write('bad\\n'); process.stdin.resume()", /invalid MCP JSON/, {}],
  ["process.stdout.write('null\\n'); process.stdin.resume()", /invalid MCP envelope/, {}],
  [server.replace("{name: 'fixture', version: '1'}", "true"), /incomplete MCP initialize/, {}],
  [server.replace("id: m.id, result", "id: m.id, error: null, result"), /MCP request failed/, {}],
  ["process.stdin.resume()", /timed out/, { timeout: 100 }],
  ["process.stdout.write('x'.repeat(100)); process.stdin.resume()", /budget exceeded/, { maxBytes: 50 }],
]) {
  await assert.rejects(withStdioMcp(process.execPath, ["-e", script], () => null, options), pattern);
}
assert.throws(() => jsonToolResult({ isError: true }), /tool returned error/);
await runHttpTests();
process.stdout.write("doctor: state freshness and fail-closed preflight passed\n");
