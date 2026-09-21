import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const self = fileURLToPath(import.meta.url);
const fail = code => Object.assign(new Error(code), { code });

// Private worker output is consumed by the parent, never written to the UI/log.
export function readCodexConfig(cwd, env = process.env, run = spawnSync) {
  const result = run(process.execPath, [self, "--read"], { cwd, env,
    input: JSON.stringify({ cwd: path.resolve(cwd) }), encoding: "utf8", windowsHide: true,
    timeout: 22000, maxBuffer: 4 * 1024 * 1024 });
  if (result.error?.code === "ETIMEDOUT") throw fail("cli_timeout");
  if (result.error?.code === "ENOBUFS") throw fail("cli_output_limit");
  if (result.status === 127) throw fail("cli_unavailable");
  if (result.error || result.status !== 0) throw fail("cli_failed");
  let payload;
  try { payload = JSON.parse(result.stdout); } catch { throw fail("cli_invalid_json"); }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw fail("configuration_malformed");
  if (payload.errorCode) throw fail(payload.errorCode);
  if (!payload.config || typeof payload.config !== "object" || Array.isArray(payload.config)) throw fail("configuration_malformed");
  return payload;
}

export function configuredServer(snapshot, name) {
  if (snapshot.layers?.some(layer => layer.disabledReason && layer.config?.mcp_servers?.[name])) throw fail("project_config_disabled");
  const raw = snapshot.config.mcp_servers?.[name];
  if (!raw) {
    return null;
  }
  if (typeof raw !== "object" || Array.isArray(raw) || (!raw.command && !raw.url)) throw fail("configuration_malformed");
  return { ...raw, name, transport: raw };
}

export function scopedReader(read = readCodexConfig) {
  const cache = new Map();
  return (args, cwd, env) => {
    const key = path.resolve(cwd);
    if (!cache.has(key)) {
      try { cache.set(key, { snapshot: read(key, env) }); }
      catch (error) { cache.set(key, { error }); }
    }
    const entry = cache.get(key);
    if (entry.error) throw entry.error;
    return configuredServer(entry.snapshot, args[1]);
  };
}

export async function requestConfig(cwd, env = process.env, launch = spawn) {
  const windows = process.platform === "win32";
  const command = windows ? path.join(env.SystemRoot ?? "C:\\Windows", "System32/WindowsPowerShell/v1.0/powershell.exe") : "codex";
  const args = windows ? ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
    "[Console]::InputEncoding=[Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { exit 127 }; & codex app-server --listen stdio://; exit $LASTEXITCODE"] : ["app-server", "--listen", "stdio://"];
  const child = launch(command, args, { cwd, env, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
  let buffer = "", total = 0, finished = false, timer;
  try {
    return await new Promise((resolve, reject) => {
      const stop = (error, result) => { if (finished) return; finished = true; clearTimeout(timer); error ? reject(error) : resolve(result); };
      const send = msg => child.stdin.write(JSON.stringify(msg) + "\n");
      timer = setTimeout(() => stop(fail("cli_timeout")), 15000);
      child.on("error", () => stop(fail(windows ? "cli_launcher_unavailable" : "cli_unavailable")));
      child.on("exit", code => stop(fail(code === 127 ? "cli_unavailable" : "cli_failed")));
      child.stdin.on("error", () => stop(fail("cli_failed")));
      child.stderr.on("data", data => { total += data.length; if (total > 4 * 1024 * 1024) stop(fail("cli_output_limit")); });
      child.stdout.setEncoding("utf8");
      child.stdout.on("data", data => {
        total += Buffer.byteLength(data); buffer += data;
        if (total > 4 * 1024 * 1024) return stop(fail("cli_output_limit"));
        let boundary;
        while (!finished && (boundary = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 1);
          if (!line.trim()) continue;
          let msg;
          try { msg = JSON.parse(line); } catch { return stop(fail("cli_invalid_json")); }
          if (!msg || typeof msg !== "object") return stop(fail("cli_invalid_json"));
          if (msg.id === 1) {
            if (msg.error || !msg.result) return stop(fail("cli_failed"));
            send({ method: "initialized" });
            send({ id: 2, method: "config/read", params: { cwd: path.resolve(cwd), includeLayers: true } });
          } else if (msg.id === 2) {
            if (msg.error || !msg.result?.config || typeof msg.result.config !== "object" || Array.isArray(msg.result.config) || (msg.result.layers != null && !Array.isArray(msg.result.layers))) return stop(fail("configuration_malformed"));
            // Keep only MCP data; provider/authentication settings are not needed.
            stop(null, { config: { mcp_servers: msg.result.config.mcp_servers ?? {} },
              layers: (msg.result.layers ?? []).map(layer => ({ disabledReason: Boolean(layer?.disabledReason),
                config: { mcp_servers: layer?.config?.mcp_servers ?? {} } })) });
          }
        }
      });
      send({ id: 1, method: "initialize", params: { clientInfo: { name: "toolkit_doctor", version: "1.0.0" } } });
    });
  } finally {
    clearTimeout(timer); child.stdin.end();
    if (child.exitCode === null) {
      await Promise.race([new Promise(resolve => child.once("exit", resolve)), new Promise(resolve => setTimeout(resolve, 1000))]);
      if (child.exitCode === null && child.pid) {
        if (windows) spawnSync(path.join(env.SystemRoot ?? "C:\\Windows", "System32/taskkill.exe"), ["/pid", String(child.pid), "/t", "/f"], { windowsHide: true, stdio: "ignore", timeout: 3000 });
        else child.kill("SIGKILL");
      }
    }
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === self && process.argv[2] === "--read") {
  try {
    const { cwd } = JSON.parse(fs.readFileSync(0, "utf8"));
    process.stdout.write(JSON.stringify(await requestConfig(cwd)));
  } catch (error) {
    const allowed = new Set(["cli_timeout", "cli_unavailable", "cli_launcher_unavailable", "cli_failed", "cli_output_limit", "cli_invalid_json", "configuration_malformed"]);
    process.stdout.write(JSON.stringify({ errorCode: allowed.has(error.code) ? error.code : "cli_failed" }));
  }
}
