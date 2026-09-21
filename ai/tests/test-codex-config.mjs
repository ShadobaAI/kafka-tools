import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { configuredServer, readCodexConfig, requestConfig, scopedReader } from "../mcp/codex-config.mjs";

const snapshot = { config: { mcp_servers: { fixture: { command: "never-start", required: true } } }, layers: [] };
assert.equal(configuredServer(snapshot, "fixture").required, true);
assert.equal(configuredServer(snapshot, "missing"), null);
assert.throws(() => configuredServer({ ...snapshot, layers: [{ disabledReason: true, config: snapshot.config }] }, "fixture"), { code: "project_config_disabled" });
assert.throws(() => configuredServer({ config: { mcp_servers: { fixture: {} } } }, "fixture"), { code: "configuration_malformed" });
let reads = 0;
const cached = scopedReader(() => { reads++; return snapshot; });
cached(["get", "fixture"], "."); cached(["get", "missing"], ".");
assert.equal(reads, 1);
cached(["get", "fixture"], ".."); assert.equal(reads, 2);
let failures = 0;
const broken = scopedReader(() => { failures++; throw Object.assign(new Error("private"), { code: "cli_failed" }); });
for (let i = 0; i < 2; i++) assert.throws(() => broken(["get", "fixture"], "."), { code: "cli_failed" });
assert.equal(failures, 1);
for (const [result, code] of [
  [{ status: 1, stderr: "private token" }, "cli_failed"],
  [{ status: 0, stdout: "invalid" }, "cli_invalid_json"],
  [{ status: 0, stdout: "null" }, "configuration_malformed"],
  [{ status: 0, stdout: '{"errorCode":"cli_unavailable"}' }, "cli_unavailable"],
  [{ error: { code: "ETIMEDOUT" } }, "cli_timeout"],
]) assert.throws(() => readCodexConfig(process.cwd(), {}, () => result), { code });
assert.deepEqual(readCodexConfig(process.cwd(), {}, () => ({ status: 0, stdout: JSON.stringify(snapshot) })), snapshot);

// A fake JSON-RPC child verifies that the reader never creates a thread or starts MCP.
const expectedCwd = path.resolve(process.cwd());
const launch = (command, args, options) => spawn(process.execPath, ["--input-type=module", "-e", `
  import readline from 'node:readline';
  let initialized = false;
  for await (const line of readline.createInterface({input:process.stdin})) {
    const msg = JSON.parse(line);
    if (msg.method === 'initialize') console.log(JSON.stringify({id:1,result:{}}));
    else if (msg.method === 'initialized') initialized = true;
    else if (msg.method === 'config/read' && initialized && msg.params.cwd === ${JSON.stringify(expectedCwd)} && msg.params.includeLayers) {
      console.log(JSON.stringify({id:2,result:{config:{...${JSON.stringify(snapshot.config)},private_token:'do-not-return'},layers:[]}}));
    } else process.exit(3);
  }
`], options);
assert.deepEqual(await requestConfig(expectedCwd, process.env, launch), snapshot);
const malformedLaunch = (command, args, options) => spawn(process.execPath, ["-e", "console.log(JSON.stringify({id:2,result:{config:{},layers:42}}))"], options);
await assert.rejects(requestConfig(expectedCwd, process.env, malformedLaunch), { code: "configuration_malformed" });

if (process.argv.includes("--live-cli-fixture")) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "toolkit-config-test-"));
  try {
    const home = path.join(root, "home"), project = path.join(root, "project with spaces");
    fs.mkdirSync(home); fs.mkdirSync(path.join(project, ".codex"), { recursive: true });
    assert.equal(spawnSync("git", ["init", "--quiet", project]).status, 0);
    const userConfig = '[mcp_servers.fixture]\ncommand="user-never-start"\n';
    fs.writeFileSync(path.join(home, "config.toml"), userConfig);
    fs.writeFileSync(path.join(project, ".codex/config.toml"), '[mcp_servers.fixture]\ncommand="project-never-start"\nrequired=true\n');
    const env = { ...process.env, CODEX_HOME: home };
    const disabled = readCodexConfig(project, env);
    assert.throws(() => configuredServer(disabled, "fixture"), { code: "project_config_disabled" });
    fs.writeFileSync(path.join(home, "config.toml"), userConfig + '[projects.' + JSON.stringify(fs.realpathSync.native(project)) + ']\ntrust_level="trusted"\n');
    const enabled = configuredServer(readCodexConfig(project, env), "fixture");
    assert.equal(enabled.transport.command, "project-never-start");
    assert.equal(enabled.required, true);
    assert.equal(configuredServer(readCodexConfig(home, env), "fixture").transport.command, "user-never-start");
    console.log("Live CLI fixture: trusted/untrusted, overrides and cwd passed (no MCP started).");
  } finally {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith("toolkit-config-test-"));
    fs.rmSync(root, { recursive: true, force: true });
  }
}
console.log("Codex configuration reader checks passed.");
