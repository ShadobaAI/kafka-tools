import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compareOpenVikingState, checkProjectRoot, diagnose, runtimeRoute, checkCodeIndexHealth } from "../doctor.mjs";
import { withStdioMcp, jsonToolResult } from "../mcp/stdio-client.mjs";

const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

const current = { tasks: { revision: "a", files: { "sdd/x.md": "b" } } };
const state = { schemaVersion: 1, manifestDigest: "digest", runtimeVersion: "9.9.9",
  repositories: { tasks: { revision: "a", files: { "sdd/x.md": "b" } } } };
assert.equal(compareOpenVikingState(state, current, "digest", "9.9.9", false), "ready");
assert.equal(compareOpenVikingState(state, current, "digest", "9.9.9", true), "stale");
assert.equal(compareOpenVikingState(state, { tasks: { revision: "c", files: current.tasks.files } }, "digest", "9.9.9", false), "stale");
assert.equal(compareOpenVikingState(state, current, "changed", "9.9.9", false), "stale");
const result = await diagnose({}, workspaceRoot);
assert.equal(result.status, "not-ready");
assert.equal(result.checks.projectRoot.status, "ready");
assert.equal(result.checks.KAFKA_OPENVIKING_STATE_DIR.status, "missing");
assert.equal(result.checks.edt.status, "unverified");
assert.equal(result.checks.distribution.status, "unverified");
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
const toolsResult = await diagnose({}, path.join(workspaceRoot, "tools"));
assert.equal(toolsResult.checks.edt.status, "not-required");
assert.equal(toolsResult.checks.bslLs.status, "not-required");
assert.equal(toolsResult.checks.v8std.status, "unverified");
assert.equal(toolsResult.checks.codeIndex.status, "not-required");
let probes = 0;
const probe = async (_, aliases) => { probes++; return { status: "ready", aliases }; };
const liveRoute = await diagnose({}, workspaceRoot, { codeIndexProbe: probe });
assert.equal(probes, 1);
assert.equal(liveRoute.checks.codeIndex.aliases.length, 7);
await diagnose({}, path.join(workspaceRoot, "tools"), { codeIndexProbe: probe });
await diagnose({}, path.join(workspaceRoot, "tools/ai"), { codeIndexProbe: probe });
assert.equal(probes, 1, "non-1C and invalid roots must not probe code-index");
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
process.stdout.write("doctor: state freshness and fail-closed preflight passed\n");
