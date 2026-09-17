import { spawnSync } from "node:child_process";
import path from "node:path";
import os from "node:os";

// Let Codex parse TOML and resolve its configuration layers. Never print its
// output: transport records can contain authentication headers and environment.
export function codexMcp(args, cwd, env = process.env) {
  const windows = process.platform === "win32";
  const command = windows ? path.join(env.SystemRoot ?? "C:\\Windows", "System32/WindowsPowerShell/v1.0/powershell.exe") : "codex";
  const argv = windows ? ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
    "[Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding; $a = ConvertFrom-Json -InputObject ([Console]::In.ReadToEnd()); & codex mcp @a; exit $LASTEXITCODE"] : ["mcp", ...args];
  const result = spawnSync(command, argv, { cwd, env, input: JSON.stringify(args),
    encoding: "utf8", windowsHide: true, timeout: 15000, maxBuffer: 1024 * 1024 });
  if (!result.error && result.status !== 0 && /^Error: No MCP server named /m.test(result.stderr ?? "")) return null;
  if (result.error || result.status !== 0) throw new Error("Не удалось прочитать MCP-конфигурацию через Codex CLI. Проверьте доступность codex и корректность config.toml.");
  try { return JSON.parse(result.stdout); }
  catch { throw new Error("Codex CLI вернул некорректный JSON конфигурации MCP."); }
}

export function readInstalledConfigs(env, projectRoot, route, workspaceRoot, read = codexMcp) {
  const records = {};
  const owners = { "kfk-edt": "adapter/adapter", "conv-edt": "conversion/KFK", "unit-edt": "tests/unit/unit" };
  const sharedCwd = path.resolve(projectRoot) === path.resolve(workspaceRoot) ? os.tmpdir() : projectRoot;
  const scopes = [{ cwd: sharedCwd, names: ["kafka-policy", "kafka-openviking", "v8std", ...(route.aliases.length ? ["code-index"] : [])] }];
  for (const name of route.edt) scopes.push({ cwd: path.join(workspaceRoot, owners[name]), names: [name] });
  const bslOwners = new Set(route.bslLsOwners);
  if (path.resolve(projectRoot) !== path.resolve(workspaceRoot)) bslOwners.add(path.relative(workspaceRoot, projectRoot));
  else for (const owner of Object.values(owners)) bslOwners.add(owner);
  for (const owner of bslOwners) scopes.push({ cwd: path.join(workspaceRoot, owner), names: ["bsl-ls"], owner, optional: !route.bslLsOwners.includes(owner) });
  for (const scope of scopes) {
    try {
      for (const name of scope.names) {
        const key = name === "bsl-ls" ? `bsl-ls:${scope.owner}` : name;
        const item = read(["get", name, "--json"], scope.cwd, env);
        if (item === null) {
          if (!scope.optional) records[key] = { error: "MCP не зарегистрирован в назначенной конфигурации. Проверьте config.toml и доверие к проекту в Codex." };
          continue;
        }
        if (item.name !== name || !item.transport) throw new Error("Неполная MCP-конфигурация из Codex CLI.");
        records[key] = { ...item.transport, enabled: item.enabled, enabled_tools: item.enabled_tools,
          disabled_tools: item.disabled_tools, startup_timeout_sec: item.startup_timeout_sec,
          tool_timeout_sec: item.tool_timeout_sec, owner: scope.owner, configCwd: scope.cwd };
      }
    } catch (error) {
      for (const name of scope.names) records[name === "bsl-ls" ? `bsl-ls:${scope.owner}` : name] = { error: error.message };
    }
  }
  return records;
}
