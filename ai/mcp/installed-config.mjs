import { readCodexConfig, configuredServer, scopedReader } from "./codex-config.mjs";
import path from "node:path";
import os from "node:os";

// Let Codex parse TOML and resolve its configuration layers. Never print its
// output: transport records can contain authentication headers and environment.
export function codexMcp(args, cwd, env = process.env) {
  return configuredServer(readCodexConfig(cwd, env), args[1]);
}

export function readInstalledConfigs(env, projectRoot, route, workspaceRoot, read = scopedReader()) {
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
      for (const name of scope.names) records[name === "bsl-ls" ? `bsl-ls:${scope.owner}` : name] = { error: error.code === "project_config_disabled" ? "Проектные настройки MCP отключены Codex: подтвердите доверие к этому каталогу проекта." : error.code ? "Не удалось прочитать настройки Codex через config/read (" + error.code + "). Проверьте версию CLI и конфигурацию." : error.message };
    }
  }
  return records;
}
