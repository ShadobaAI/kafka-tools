import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { hookBody, installHooks } from "../openviking/install-hooks.mjs";
import { dispatch } from "../openviking/hook-dispatch.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-hooks-"));
const stateRoot = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-state-"));
try {
  const repositories = [];
  for (const name of ["repo-a", "repo-b"]) {
    const repository = path.join(root, name);
    fs.mkdirSync(repository);
    execFileSync("git", ["init", "--quiet", repository], { windowsHide: true });
    repositories.push({ id: name, root: name, include: ["README.md"], exclude: [] });
  }
  const manifest = path.join(root, "sources.json");
  fs.writeFileSync(manifest, JSON.stringify({ schemaVersion: 1,
    namespace: "viking://resources/kafka-git",
    hookRepositories: repositories.map(({ id, root: repositoryRoot }) => ({ id, root: repositoryRoot })),
    repositories }));
  const hookRoot = path.join(root, "repo-a", ".git", "hooks");
  const original = "#!/bin/sh\necho foreign\nexit 7\n";
  fs.writeFileSync(path.join(hookRoot, "post-merge"), original, { mode: 0o755 });
  const dispatcher = path.join(root, "dispatcher.mjs");
  fs.writeFileSync(dispatcher, "process.exit(0);\n");
  const options = { workspaceRoot: root, stateDir: stateRoot,
    manifestFile: manifest, dispatcher, node: process.execPath };
  assert.throws(() => installHooks({ ...options, stateDir: path.join(root, "state") }), /outside the Kafka workspace/);
  const first = installHooks(options);
  assert.equal(first.length, 6);
  assert.equal(fs.readFileSync(path.join(hookRoot, "post-merge.kafka-user"), "utf8"), original);
  const installLock = path.join(stateRoot, "hooks-install.lock");
  fs.mkdirSync(installLock);
  assert.throws(() => installHooks(options), /EEXIST/);
  fs.rmdirSync(installLock);
  const gitShell = path.resolve(execFileSync("git", ["--exec-path"], { encoding: "utf8" }).trim(),
    "..", "..", "..", "bin", "sh.exe");
  assert.ok(fs.existsSync(gitShell), "Git for Windows hook shell is required");
  assert.throws(() => execFileSync(gitShell, [path.join(hookRoot, "post-merge")],
    { encoding: "utf8", windowsHide: true, timeout: 5000 }),
  (error) => error.status === 7 && error.stdout.includes("foreign"));
  const installed = fs.readFileSync(path.join(hookRoot, "post-merge"), "utf8");
  assert.match(installed, /KAFKA-OPENVIKING-HOOK v1/);
  assert.match(installed, /foreign_status/);
  assert.equal(installHooks(options).length, 6);
  assert.equal(fs.readFileSync(path.join(hookRoot, "post-merge"), "utf8"), installed,
    "reinstall must be byte-idempotent");
  assert.equal(fs.readFileSync(path.join(hookRoot, "post-merge.kafka-user"), "utf8"), original);

  const collision = path.join(root, "repo-b", ".git", "hooks", "post-checkout");
  fs.writeFileSync(collision, "#!/bin/sh\necho replacement\n");
  fs.writeFileSync(`${collision}.kafka-user`, "#!/bin/sh\necho already-preserved\n");
  const earlier = path.join(hookRoot, "post-checkout");
  fs.writeFileSync(earlier, "#!/bin/sh\n# KAFKA-OPENVIKING-HOOK v1\necho stale-wrapper\n");
  await assert.rejects(async () => installHooks(options), /cannot preserve two existing hooks/);
  assert.equal(fs.readFileSync(collision, "utf8"), "#!/bin/sh\necho replacement\n");
  assert.match(fs.readFileSync(earlier, "utf8"), /stale-wrapper/,
    "global preflight must reject before updating earlier hooks");

  const quoted = hookBody({ node: "C:/Program Files/node's/node.exe", dispatcher: "C:/tool/hook.mjs",
    workspaceRoot: "C:/work root", stateDir: "C:/state root", hook: "post-merge" });
  assert.match(quoted, /node'"'"'s/);
  const dispatched = path.join(root, "dispatched.txt");
  const fakeSync = path.join(root, "fake-sync.mjs");
  fs.writeFileSync(fakeSync, `import fs from 'node:fs'; fs.writeFileSync(${JSON.stringify(dispatched)}, 'ok');\n`);
  const dispatchedChild = dispatch({ workspaceRoot: root, stateDir: stateRoot,
    syncScript: fakeSync, detached: false });
  assert.ok(dispatchedChild.pid > 0);
  const childClosed = new Promise((resolve, reject) => {
    dispatchedChild.once("error", reject);
    dispatchedChild.once("close", resolve);
  });
  assert.throws(() => dispatch({ workspaceRoot: root, stateDir: path.join(root, "state"), syncScript: fakeSync }),
    /outside the Kafka workspace/);
  for (let attempt = 0; attempt < 50 && !fs.existsSync(dispatched); attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.equal(fs.readFileSync(dispatched, "utf8"), "ok");
  await childClosed;
  process.stdout.write("openviking-hooks: foreign preservation, collision refusal, and idempotency passed\n");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
  fs.rmSync(stateRoot, { recursive: true, force: true });
}
