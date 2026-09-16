import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { installHooks } from "../openviking/install-hooks.mjs";
import { inventory } from "../openviking/git-sync.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-checkouts-"));
const stateOne = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-state-one-"));
const stateTwo = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-state-two-"));
const run = (cwd, args) => execFileSync("git", ["-C", cwd, ...args],
  { encoding: "utf8", windowsHide: true, timeout: 10000 }).trim();
const commit = (cwd, message) => run(cwd, ["-c", "user.name=Kafka Test", "-c",
  "user.email=kafka-test@example.invalid", "commit", "--quiet", "-am", message]);
const waitFor = async (predicate) => {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("hook event timed out");
};

try {
  const origin = path.join(root, "origin");
  fs.mkdirSync(origin);
  execFileSync("git", ["init", "--quiet", "--initial-branch=main", origin], { windowsHide: true });
  fs.writeFileSync(path.join(origin, "README.md"), "one\n");
  run(origin, ["add", "README.md"]);
  commit(origin, "initial");

  const workOne = path.join(root, "work-one");
  const workTwo = path.join(root, "work-two");
  fs.mkdirSync(workOne);
  fs.mkdirSync(workTwo);
  execFileSync("git", ["clone", "--quiet", origin, path.join(workOne, "repo")], { windowsHide: true });
  execFileSync("git", ["clone", "--quiet", origin, path.join(workTwo, "repo")], { windowsHide: true });
  const manifest = { schemaVersion: 1, namespace: "viking://resources/kafka-git",
    hookRepositories: [{ id: "fixture", root: "repo" }],
    repositories: [{ id: "fixture", root: "repo", include: ["README.md"], exclude: [] }] };
  const manifestOne = path.join(workOne, "sources.json");
  const manifestTwo = path.join(workTwo, "sources.json");
  fs.writeFileSync(manifestOne, JSON.stringify(manifest));
  fs.writeFileSync(manifestTwo, JSON.stringify(manifest));
  const eventsOne = path.join(root, "events-one.txt");
  const eventsTwo = path.join(root, "events-two.txt");
  const dispatcher = path.join(root, "dispatcher.mjs");
  fs.writeFileSync(dispatcher, `import fs from 'node:fs';\n` +
    `const value=(n)=>{const i=process.argv.indexOf(n);return i<0?'':process.argv[i+1]};\n` +
    `const file=value('--workspace-root').endsWith('work-one')?${JSON.stringify(eventsOne)}:${JSON.stringify(eventsTwo)};\n` +
    `fs.appendFileSync(file,value('--hook')+'\\n');\n`);
  installHooks({ workspaceRoot: workOne, stateDir: stateOne, manifestFile: manifestOne, dispatcher });
  installHooks({ workspaceRoot: workTwo, stateDir: stateTwo, manifestFile: manifestTwo, dispatcher });

  const snapshot = (workspace) => {
    const item = inventory(workspace, manifest).fixture;
    return { revision: item.revision, files: item.files };
  };
  assert.deepEqual(snapshot(workOne), snapshot(workTwo));
  fs.writeFileSync(path.join(workOne, "repo", "README.md"), "dirty working tree\n");
  fs.writeFileSync(path.join(workOne, "repo", "untracked.md"), "untracked\n");
  assert.deepEqual(snapshot(workOne), snapshot(workTwo), "inventory must use committed blobs only");
  run(path.join(workOne, "repo"), ["restore", "README.md"]);
  fs.unlinkSync(path.join(workOne, "repo", "untracked.md"));

  fs.writeFileSync(path.join(origin, "README.md"), "two\n");
  commit(origin, "second");
  run(path.join(workOne, "repo"), ["pull", "--quiet", "--ff-only"]);
  run(path.join(workTwo, "repo"), ["pull", "--quiet", "--ff-only"]);
  await waitFor(() => fs.existsSync(eventsOne) && fs.readFileSync(eventsOne, "utf8").includes("post-merge"));
  await waitFor(() => fs.existsSync(eventsTwo) && fs.readFileSync(eventsTwo, "utf8").includes("post-merge"));
  assert.deepEqual(snapshot(workOne), snapshot(workTwo));

  run(path.join(workOne, "repo"), ["checkout", "--quiet", "-b", "feature"]);
  await waitFor(() => fs.readFileSync(eventsOne, "utf8").includes("post-checkout"));
  fs.writeFileSync(path.join(workOne, "repo", "README.md"), "feature\n");
  commit(path.join(workOne, "repo"), "feature");
  fs.writeFileSync(path.join(origin, "other.md"), "main update\n");
  run(origin, ["add", "other.md"]);
  run(origin, ["-c", "user.name=Kafka Test", "-c", "user.email=kafka-test@example.invalid",
    "commit", "--quiet", "-m", "third"]);
  run(path.join(workOne, "repo"), ["fetch", "--quiet", "origin"]);
  run(path.join(workOne, "repo"), ["rebase", "origin/main"]);
  await waitFor(() => fs.readFileSync(eventsOne, "utf8").includes("post-rewrite"));

  assert.equal(run(path.join(workOne, "repo"), ["status", "--porcelain"]), "");
  assert.equal(run(path.join(workTwo, "repo"), ["status", "--porcelain"]), "");
  process.stdout.write("openviking-checkouts: two clones, committed inventory, pull, checkout, and rebase hooks passed\n");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
  fs.rmSync(stateOne, { recursive: true, force: true });
  fs.rmSync(stateTwo, { recursive: true, force: true });
}
