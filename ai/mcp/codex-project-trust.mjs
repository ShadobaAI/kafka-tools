import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { requestCodex } from "./codex-config.mjs";
const fail = message => { throw new Error(message); };
export function pathKey(value) {
  const normalized = path.resolve(value).replaceAll("\\", "/").replace(/\/$/, "");
  return process.platform === "win32" ? normalized.toLowerCase() : normalized;
}
export function planTrust(projects, roots) {
  const updated = structuredClone(projects);
  const pending = [];
  for (const root of roots) {
    const keys = Object.keys(updated).filter(key => pathKey(key) === pathKey(root));
    if (keys.length > 1) fail("Conflicting equivalent project paths in Codex config; resolve duplicates before installation.");
    const key = keys[0];
    // Codex uses the canonical native path as its project key on Windows.
    if (key === root && updated[key]?.trust_level === "trusted") continue;
    const previous = key ? updated[key] : {};
    if (!previous || typeof previous !== "object" || Array.isArray(previous)) fail("Invalid project trust entry.");
    if (key) delete updated[key];
    updated[root] = { ...previous, trust_level: "trusted" };
    pending.push(root);
  }
  return { updated, pending };
}
export async function ensureTrust(roots, { env = process.env, approve = false, rpc = requestCodex } = {}) {
  const canonical = [...new Set(roots.map(root => fs.realpathSync.native(path.resolve(root))))];
  if (!canonical.length) fail("No project roots supplied.");
  const home = path.resolve(env.CODEX_HOME || path.join(os.homedir(), ".codex"));
  const configFile = path.join(home, "config.toml");
  const cwd = canonical[0];
  const snapshot = await rpc(cwd, env, "config/read", { cwd, includeLayers: true });
  const user = snapshot.layers?.find(layer => layer.name?.type === "user" && !layer.name.profile && pathKey(layer.name.file) === pathKey(configFile));
  if (!user || !user.version) fail("Codex did not return a versioned user configuration layer. Update Codex CLI and retry.");
  const projects = user.config?.projects ?? {};
  if (typeof projects !== "object" || Array.isArray(projects)) fail("Invalid projects table in Codex configuration.");
  const { updated, pending } = planTrust(projects, canonical);
  if (!pending.length) {
    for (const root of canonical) {
      const verified = root === cwd ? snapshot : await rpc(root, env, "config/read", { cwd: root, includeLayers: true });
      if (verified.layers?.some(layer => layer.name?.type === "project" && layer.disabledReason)) fail("Codex still disables a project configuration layer; installation stopped.");
    }
    return { pending, configFile, changed: false };
  }
  if (!approve) return { pending, configFile, changed: false };
  await rpc(cwd, env, "config/value/write", { keyPath: "projects", value: updated,
    mergeStrategy: "replace", filePath: configFile, expectedVersion: user.version });
  for (const root of canonical) {
    const verified = await rpc(root, env, "config/read", { cwd: root, includeLayers: true });
    const persisted = verified.layers?.find(layer => layer.name?.type === "user" && !layer.name.profile && pathKey(layer.name.file) === pathKey(configFile));
    if (persisted?.config?.projects?.[root]?.trust_level !== "trusted") fail("Codex did not retain project trust; installation stopped.");
    if (verified.layers?.some(layer => layer.name?.type === "project" && layer.disabledReason)) fail("Codex still disables a project configuration layer; installation stopped.");
  }
  return { pending: [], configFile, changed: true };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2), approve = args.includes("--approve");
    const homeIndex = args.indexOf("--codex-home");
    const env = { ...process.env };
    if (homeIndex !== -1) {
      if (!args[homeIndex + 1]) fail("Missing Codex home.");
      env.CODEX_HOME = path.resolve(args[homeIndex + 1]); args.splice(homeIndex, 2);
    }
    const result = await ensureTrust(args.filter(arg => arg !== "--approve"), { env, approve });
    if (result.pending.length) {
      console.log("Project trust is required. Codex user config: " + result.configFile);
      for (const root of result.pending) console.log("  " + root);
      process.exitCode = 10;
    } else console.log(result.changed ? "Project trust saved and verified." : "Project trust is already configured; no changes.");
  } catch {
    // Never expose API errors or raw configuration; they can contain secrets.
    console.error("Cannot check/save Codex project trust. Check Codex CLI version, configuration validity, file permissions and concurrent edits. Setup stopped.");
    process.exitCode = 1;
  }
}
