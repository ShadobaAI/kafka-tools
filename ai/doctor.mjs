import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadManifest, inventory, localClient } from "./openviking/git-sync.mjs";
import { loadRegistry } from "./policy/selector.mjs";
import { visibleTools } from "./policy/read-only-mcp.mjs";
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

export async function diagnose(env = process.env, projectRoot = process.cwd(), { codeIndexProbe = probeCodeIndex } = {}) {
  const checks = {};
  checks.projectRoot = checkProjectRoot(projectRoot);
  const route = runtimeRoute(projectRoot);
  checks.route = route;
  if (checks.projectRoot.status !== "ready" || route.status !== "ready") {
    return { status: "not-ready", checks };
  }
  checks.workspace = path.resolve(env.KAFKA_PROJECTS_ROOT ?? "") === workspaceRoot ?
    { status: "ready" } : { status: "missing", detail: "KAFKA_PROJECTS_ROOT must name this workspace" };
  try {
    const registry = loadRegistry();
    const names = visibleTools().map((item) => item.name);
    if (!names.includes("detect_1c_mechanisms") || !names.includes("validate_compliance")) throw new Error("required tools missing");
    checks.policy = { status: "ready", version: registry.registryVersion, tools: names.length };
  } catch (error) { checks.policy = { status: "error", detail: error.message }; }
  const requiredEnv = ["KAFKA_OPENVIKING_STATE_DIR", "V8STD_MCP_URL"];
  if (route.aliases.length) requiredEnv.push("KAFKA_CODE_INDEX_HOME");
  for (const name of requiredEnv) {
    checks[name] = env[name] ? { status: "ready" } : { status: "missing", detail: `${name} is unset` };
  }
  checks.codeIndex = route.aliases.length ? await codeIndexProbe(env, route.aliases) : { status: "not-required" };
  if (env.KAFKA_OPENVIKING_STATE_DIR) {
    try {
      const stateDir = path.resolve(env.KAFKA_OPENVIKING_STATE_DIR);
      const { manifest, runtime, digest } = loadManifest(undefined, path.join(stateDir, "runtime.json"));
      const state = JSON.parse(fs.readFileSync(path.join(stateDir, "state.json"), "utf8"));
      const current = inventory(workspaceRoot, manifest);
      const status = compareOpenVikingState(state, current, digest, runtime.version,
        fs.existsSync(path.join(stateDir, "dirty")));
      if (status === "ready") await localClient(stateDir).ready(runtime.version);
      checks.openviking = { status };
    } catch (error) { checks.openviking = { status: "stale", detail: error.message }; }
  }
  checks.edt = route.edt.length ? { status: "unverified", servers: route.edt,
    detail: "readiness requires live assigned MCP evidence" } : { status: "not-required" };
  checks.bslLs = route.bslLsOwners.length ? { status: "unverified", owners: route.bslLsOwners,
    detail: "repository-local BSL LS requires live MCP check" } : { status: "not-required",
    detail: "no BSL LS configured by the canonical route; explicitly configured endpoints still require verification" };
  checks.v8std = { status: "unverified", detail: "endpoint configuration is not normative corpus readiness" };
  checks.distribution = { status: "unverified", detail: "installer-owned skills/MCP/guard require installed-profile verification" };
  return { status: Object.values(checks).every((item) => ["ready", "not-required"].includes(item.status)) ? "ready" : "not-ready", checks };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const projectRoot = args.length === 0 ? process.cwd() :
    args.length === 2 && args[0] === "--project-root" ? args[1] : null;
  if (!projectRoot) {
    process.stderr.write("usage: node doctor.mjs [--project-root KAFKA_ROOT_OR_REPOSITORY_ROOT]\n");
    process.exitCode = 2;
  } else diagnose(process.env, projectRoot).then((result) => {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (result.status !== "ready") process.exitCode = 1;
  }).catch((error) => { process.stderr.write(`doctor: ${error.message}\n`); process.exitCode = 1; });
}
