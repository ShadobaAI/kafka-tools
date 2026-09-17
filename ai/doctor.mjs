import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadManifest, inventory, localClient } from "./openviking/git-sync.mjs";
import { readInstalledConfigs } from "./mcp/installed-config.mjs";
import { probeConfiguredMcp } from "./mcp/doctor-probes.mjs";
import { withStdioMcp, jsonToolResult } from "./mcp/stdio-client.mjs";

const aiRoot = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(aiRoot, "..", "..");
const policy = JSON.parse(fs.readFileSync(path.join(aiRoot, "workspace-policy.json"), "utf8"));
const contours = [
  { server: "kfk-edt", roots: ["adapter/adapter", "adapter/base", "adapter/examples"], aliases: ["kfk", "kfk-base", "kfk-examples"], bslLsOwner: "adapter/adapter" },
  { server: "conv-edt", roots: ["conversion/KFK", "conversion/КД"], aliases: ["kfk-conv", "kfk-conv-kd"], bslLsOwner: null },
  { server: "unit-edt", roots: ["tests/unit/base", "tests/unit/examples", "tests/unit/unit", "tests/unit/yaxunit"], aliases: ["kfk", "kfk-base", "kfk-examples", "kfk-unit", "kfk-yaxunit"], bslLsOwner: null },
];
const repositoryRoots = new Set([...policy.protectedRepositoryRoots, "tools", "tasks", "tests/reports", "tests/ui"]);

export function runtimeRoute(projectRoot) {
  const relative = path.relative(workspaceRoot, path.resolve(projectRoot)).split(path.sep).join("/");
  const normalized = process.platform === "win32" ? relative.toLowerCase() : relative;
  const matching = (root) => (process.platform === "win32" ? root.toLowerCase() : root) === normalized;
  if (!relative) return { status: "ready", edt: contours.map((item) => item.server),
    aliases: Object.keys(policy.codeIndexAliases), bslLsOwners: ["adapter/adapter"] };
  if (![...repositoryRoots].some(matching)) return { status: "error", detail: "project root has no canonical Kafka route" };
  const contour = contours.find((item) => item.roots.some(matching));
  return { status: "ready", edt: contour ? [contour.server] : [],
    aliases: contour?.aliases ?? [], bslLsOwners: contour?.bslLsOwner ? [contour.bslLsOwner] : [] };
}

// Accept only the managed MCP health contract; filenames or an HTTP ping are not evidence.
export function checkCodeIndexHealth(health, aliases) {
  if (health?.mcp?.status !== "ok" || health?.daemon?.state !== "healthy" ||
      health.daemon.status !== "online" || health.daemon.endpoint_verified !== true ||
      health.daemon.process_alive !== true) return { status: "error", detail: "managed MCP daemon health is incomplete" };
  const normalize = (root) => String(root ?? "").replace(/^\\\\\?\\/, "").replace(/\\/g, "/").replace(/\/$/, "").toLowerCase();
  for (const alias of aliases) {
    const entries = health.repos?.filter((item) => item.repo === alias) ?? [];
    const expected = policy.codeIndexAliases[alias];
    if (!expected || entries.length !== 1 || entries[0].path_status?.status !== "ready" ||
        normalize(entries[0].root_path) !== normalize(path.resolve(workspaceRoot, expected)) ||
        normalize(entries[0].path_status.path) !== normalize(path.resolve(workspaceRoot, expected))) {
      return { status: "error", detail: `required canonical alias is not ready: ${alias}` };
    }
  }
  return { status: "ready", aliases };
}

export function compareOpenVikingState(state, current, digest, version, dirty) {
  if (dirty || !state || state.schemaVersion !== 1 || state.manifestDigest !== digest ||
      state.runtimeVersion !== version) return "stale";
  for (const [id, item] of Object.entries(current)) {
    const saved = state.repositories?.[id];
    if (!saved || saved.revision !== item.revision ||
        JSON.stringify(saved.files) !== JSON.stringify(item.files)) return "stale";
  }
  return Object.keys(state.repositories).length === Object.keys(current).length ? "ready" : "stale";
}

export function checkProjectRoot(projectRoot) {
  const root = path.resolve(projectRoot);
  const workspace = process.platform === "win32" ? workspaceRoot.toLowerCase() : workspaceRoot;
  const candidate = process.platform === "win32" ? root.toLowerCase() : root;
  if (candidate === workspace) return { status: "ready", kind: "workspace" };
  if (!candidate.startsWith(`${workspace}${path.sep}`)) {
    return { status: "error", detail: "Codex project root is outside Kafka workspace" };
  }
  if (runtimeRoute(root).status !== "ready") return runtimeRoute(root);
  const git = spawnSync("git", ["-c", `safe.directory=${root}`, "-C", root, "rev-parse", "--show-toplevel"],
    { encoding: "utf8", timeout: 5000, windowsHide: true });
  if (git.error || git.status !== 0 || path.resolve(git.stdout.trim()).toLowerCase() !== root.toLowerCase()) {
    return { status: "error", detail: "Codex project root must be a Kafka repository root" };
  }
  return { status: "ready", kind: "repository" };
}

export async function probeCodeIndex(env, aliases) {
  if (!aliases.length) return { status: "not-required" };
  if (!env.KAFKA_CODE_INDEX_HOME) return { status: "missing", detail: "KAFKA_CODE_INDEX_HOME is unset" };
  const root = path.resolve(env.KAFKA_CODE_INDEX_HOME);
  const launcher = path.join(root, "mcp", "code-index-mcp.ps1");
  if (!fs.existsSync(launcher) || !fs.existsSync(path.join(root, "daemon.toml"))) {
    return { status: "missing", detail: "managed code-index launcher/config missing" };
  }
  try {
    return await withStdioMcp("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive",
      "-ExecutionPolicy", "Bypass", "-File", launcher, "-CodeIndexHome", root, "-SkipDaemonBootstrap"],
    async ({ request }) => checkCodeIndexHealth(jsonToolResult(await request("tools/call",
      { name: "health", arguments: {} })), aliases), { env, cwd: workspaceRoot });
  } catch (error) { return { status: "error", detail: error.message }; }
}

export async function diagnose(env = process.env, projectRoot = process.cwd(), {
  configLoader = readInstalledConfigs, mcpProbe = probeConfiguredMcp,
  openVikingProbe = probeOpenViking, progress = () => {},
} = {}) {
  const checks = {};
  checks.projectRoot = checkProjectRoot(projectRoot);
  const route = runtimeRoute(projectRoot);
  checks.route = route;
  if (checks.projectRoot.status !== "ready" || route.status !== "ready") {
    return { status: "not-ready", checks };
  }
  progress("Чтение настроек MCP через Codex CLI...");
  const configs = configLoader(env, projectRoot, route, workspaceRoot);
  for (const [name, config] of Object.entries(configs)) {
    progress(`Проверка ${name}...`);
    const contour = contours.find((item) => item.server === name);
    checks[name] = await mcpProbe(name, config, env, { checkCodeIndexHealth, aliases: route.aliases,
      workspaceRoot, edt: contour ? { roots: contour.roots, port: { "kfk-edt": 8765, "conv-edt": 8767, "unit-edt": 8768 }[name] } : undefined });
    if (name === "kafka-openviking" && checks[name].status === "ready") {
      progress("Проверка runtime и данных OpenViking...");
      checks.openviking = await openVikingProbe(config);
    }
  }
  for (const name of ["kafka-policy", "kafka-openviking", "v8std", ...route.edt,
    ...route.bslLsOwners.map((owner) => `bsl-ls:${owner}`), ...(route.aliases.length ? ["code-index"] : [])]) {
    checks[name] ??= { status: "missing", detail: "MCP не зарегистрирован в назначенной конфигурации." };
  }
  return { status: Object.values(checks).every((item) => ["ready", "not-required"].includes(item.status)) ? "ready" : "not-ready", checks };
}

export async function probeOpenViking(config) {
  const option = (flag) => {
    const indexes = (config.args ?? []).flatMap((arg, index) => arg === flag ? [index] : []);
    return indexes.length === 1 ? config.args[indexes[0] + 1] : undefined;
  };
  const stateDir = option("--state-dir"), configuredRoot = option("--workspace-root");
  if (!stateDir || !path.isAbsolute(stateDir) || !configuredRoot || path.resolve(configuredRoot).toLowerCase() !== workspaceRoot.toLowerCase()) {
    return { status: "error", detail: "Проверьте --state-dir и --workspace-root в args MCP kafka-openviking." };
  }
  for (const file of ["runtime.json", "state.json"]) {
    if (!fs.existsSync(path.join(stateDir, file))) return { status: "missing", detail: `В настроенном state-dir отсутствует ${file}. Проверьте args MCP и завершение установки OpenViking.` };
  }
  let stage = "metadata";
  try {
    const { manifest, runtime, digest } = loadManifest(undefined, path.join(stateDir, "runtime.json"));
    const state = JSON.parse(fs.readFileSync(path.join(stateDir, "state.json"), "utf8"));
    stage = "inventory";
    const status = compareOpenVikingState(state, inventory(workspaceRoot, manifest), digest, runtime.version,
      fs.existsSync(path.join(stateDir, "dirty")));
    stage = "runtime";
    await localClient(stateDir).ready(runtime.version);
    return { status, detail: status === "ready" ? "Runtime готов; данные соответствуют committed HEAD." :
      "Runtime отвечает, но Git-контекст устарел. Обновите его через update-openviking.cmd с тем же state-dir." };
  } catch (error) {
    const details = {
      metadata: "Некорректные runtime.json/state.json OpenViking или несовместимая версия runtime. Проверьте выбранный state-dir и завершение установки.",
      inventory: "Не удалось сверить OpenViking с committed Git inventory. Проверьте доступ к репозиториям workspace.",
      runtime: Number.isInteger(error.status) ? `OpenViking runtime вернул HTTP ${error.status}. Проверьте Docker-сервис, авторизацию и /ready.` :
        "OpenViking runtime не подтвердил /health и /ready. Проверьте Docker-сервис, версию, embedding и хранилище; сервисы автоматически не запускались.",
    };
    return { status: "error", detail: details[stage] };
  }
}

export function formatReport(result) {
  const labels = {
    projectRoot: "Каталог проекта", route: "Маршрут проверок", workspace: "Корень Kafka workspace",
    "kafka-policy": "Правила toolkit (MCP)", "code-index": "Индекс исходного кода", openviking: "OpenViking: runtime и данные",
    "kafka-openviking": "OpenViking (MCP)",
    edt: "EDT", bslLs: "BSL Language Server", v8std: "База стандартов v8std",
    distribution: "Установленные skills, MCP и защитные правила",
  };
  const statuses = {
    ready: "OK", "not-required": "НЕ ТРЕБУЕТСЯ", missing: "НЕ НАСТРОЕНО",
    stale: "ТРЕБУЕТ ПРОВЕРКИ / ОБНОВЛЕНИЯ", error: "ОШИБКА", unverified: "НЕ ПРОВЕРЕНО",
  };
  const lines = ["Диагностика Kafka toolkit", result.status === "ready" ?
    "Итог: готовность подтверждена." : "Итог: готовность НЕ подтверждена."];
  const groups = [
    ["Проблемы настройки и ошибки", (status) => !["ready", "not-required", "unverified"].includes(status)],
    ["Что ещё не проверено (это не означает неисправность)", (status) => status === "unverified"],
    ["Успешные и необязательные проверки", (status) => ["ready", "not-required"].includes(status)],
  ];
  for (const [title, matches] of groups) {
    const entries = Object.entries(result.checks).filter(([, check]) => matches(check.status));
    if (!entries.length) continue;
    lines.push("", `${title}:`);
    for (const [name, check] of entries) {
      lines.push(`  [${statuses[check.status] ?? check.status}] ${labels[name] ?? name}`);
      if (check.detail) lines.push(`    ${check.detail}`);
      if (check.servers?.length) lines.push(`    Серверы: ${check.servers.join(", ")}`);
      if (check.owners?.length) lines.push(`    Проекты: ${check.owners.join(", ")}`);
    }
  }
  if (Object.values(result.checks).some((check) => check.status === "missing")) {
    lines.push("", "Следующий шаг: проверьте регистрацию MCP и доверие к проекту в Codex; см. tools/ai/README.md.");
  }
  return `${lines.join("\n")}\n`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const human = args[0] === "--human";
  if (human) args.shift();
  const projectRoot = args.length === 0 ? process.cwd() :
    args.length === 2 && args[0] === "--project-root" ? args[1] : null;
  if (!projectRoot) {
    process.stderr.write("usage: node doctor.mjs [--human] [--project-root KAFKA_ROOT_OR_REPOSITORY_ROOT]\n");
    process.exitCode = 2;
  } else diagnose(process.env, projectRoot, { progress: human ? (message) => process.stderr.write(`${message}\n`) : () => {} }).then((result) => {
    process.stdout.write(human ? formatReport(result) : `${JSON.stringify(result, null, 2)}\n`);
    if (result.status !== "ready") process.exitCode = 1;
  }).catch((error) => { process.stderr.write(`doctor: ${error.message}\n`); process.exitCode = 1; });
}
