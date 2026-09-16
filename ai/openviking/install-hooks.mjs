import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadManifest } from "./git-sync.mjs";

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const marker = "# KAFKA-OPENVIKING-HOOK v1";
const hookNames = ["post-checkout", "post-merge", "post-rewrite"];

function git(root, args) {
  return execFileSync("git", ["-c", `safe.directory=${root}`, "-C", root, ...args],
    { encoding: "utf8", timeout: 5000, windowsHide: true }).trim();
}

function shellQuote(value) { return `'${String(value).replace(/'/g, `'"'"'`)}'`; }

export function hookBody({ node, dispatcher, workspaceRoot, stateDir, hook }) {
  const invoke = [node, dispatcher, "--workspace-root", workspaceRoot, "--state-dir", stateDir, "--hook", hook]
    .map(shellQuote).join(" ");
  return `#!/bin/sh\n${marker}\nforeign="$0.kafka-user"\nforeign_status=0\n` +
    `if [ -x "$foreign" ]; then "$foreign" "$@" || foreign_status=$?; fi\n` +
    `${invoke} >/dev/null 2>&1 || echo "warning: OpenViking eager reconciliation was not dispatched" >&2\n` +
    `exit "$foreign_status"\n`;
}

function writeAtomic(destination, body) {
  const temporary = `${destination}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, body, { encoding: "utf8", flag: "wx", mode: 0o755 });
  try { fs.renameSync(temporary, destination); }
  catch (error) { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); throw error; }
  try { fs.chmodSync(destination, 0o755); } catch { /* Windows has no executable bit. */ }
}

export function installHooks({ workspaceRoot, stateDir, node = process.execPath,
                               manifestFile, dispatcher = path.join(moduleDir, "hook-dispatch.mjs") }) {
  for (const value of [workspaceRoot, stateDir, node, dispatcher]) {
    if (!value || !path.isAbsolute(value)) throw new Error("hook paths must be absolute");
  }
  const relativeState = path.relative(workspaceRoot, stateDir);
  if (!relativeState || (!relativeState.startsWith("..") && !path.isAbsolute(relativeState))) {
    throw new Error("OpenViking state must be outside the Kafka workspace");
  }
  if (!fs.existsSync(node) || !fs.existsSync(dispatcher)) throw new Error("hook runtime file is missing");
  fs.mkdirSync(stateDir, { recursive: true });
  const lock = path.join(stateDir, "hooks-install.lock");
  fs.mkdirSync(lock);
  try {
    const { manifest } = loadManifest(manifestFile);
    const installed = [];
    const plans = [];
    for (const repository of manifest.hookRepositories) {
    const root = path.resolve(workspaceRoot, repository.root);
    const top = path.resolve(git(root, ["rev-parse", "--show-toplevel"]));
    if (top.toLowerCase() !== root.toLowerCase()) throw new Error(`source is not a canonical Git root: ${repository.id}`);
    const hooksRoot = path.resolve(root, git(root, ["rev-parse", "--git-path", "hooks"]));
    for (const name of hookNames) {
      const target = path.join(hooksRoot, name);
      const foreign = `${target}.kafka-user`;
      const existing = fs.existsSync(target) ? fs.readFileSync(target) : null;
      const managed = existing?.includes(Buffer.from(marker)) ?? false;
      if (existing !== null && !managed) {
        if (fs.existsSync(foreign)) throw new Error(`cannot preserve two existing hooks: ${target}`);
      }
      plans.push({ repository: repository.id, hook: name, target, foreign, existing, managed,
        mode: existing === null ? null : fs.statSync(target).mode });
    }
    }
    const applied = [];
    try {
    for (const plan of plans) {
      applied.push(plan);
      fs.mkdirSync(path.dirname(plan.target), { recursive: true });
      if (plan.existing !== null && !plan.managed) fs.renameSync(plan.target, plan.foreign);
      const body = hookBody({ node, dispatcher, workspaceRoot, stateDir, hook: plan.hook });
      if (!fs.existsSync(plan.target) || fs.readFileSync(plan.target, "utf8") !== body) writeAtomic(plan.target, body);
      installed.push({ repository: plan.repository, hook: plan.hook,
        preservedForeign: fs.existsSync(plan.foreign) });
    }
    return installed;
    } catch (error) {
      const rollbackErrors = [];
      for (const plan of applied.reverse()) {
        try {
        if (fs.existsSync(plan.target)) fs.unlinkSync(plan.target);
        if (plan.existing !== null && !plan.managed && fs.existsSync(plan.foreign)) {
          fs.renameSync(plan.foreign, plan.target);
        } else if (plan.existing !== null) {
          fs.writeFileSync(plan.target, plan.existing, { mode: plan.mode });
        }
        } catch (rollbackError) { rollbackErrors.push(rollbackError.message); }
      }
      if (rollbackErrors.length) {
        throw new Error(`hook installation failed: ${error.message}; rollback failed: ${rollbackErrors.join(" | ")}`);
      }
      throw error;
    }
  } finally {
    fs.rmdirSync(lock);
  }
}

function option(argv, name) {
  const index = argv.indexOf(name);
  return index < 0 ? undefined : argv[index + 1];
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const workspaceRoot = option(process.argv, "--workspace-root");
    const stateDir = option(process.argv, "--state-dir");
    if (!workspaceRoot || !stateDir) throw new Error("--workspace-root and --state-dir are required");
    const result = installHooks({ workspaceRoot: path.resolve(workspaceRoot), stateDir: path.resolve(stateDir) });
    process.stdout.write(`${JSON.stringify({ status: "ready", installed: result.length })}\n`);
  } catch (error) {
    process.stderr.write(`openviking-hooks: ${error.message}\n`);
    process.exitCode = 1;
  }
}
