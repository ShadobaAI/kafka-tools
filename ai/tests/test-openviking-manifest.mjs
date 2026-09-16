import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.resolve(aiRoot, "..", "..");
const manifest = JSON.parse(fs.readFileSync(path.join(aiRoot, "openviking", "sources.json"), "utf8"));
const policy = JSON.parse(fs.readFileSync(path.join(aiRoot, "openviking", "version.json"), "utf8"));
const bootstrap = fs.readFileSync(path.join(aiRoot, "openviking", "docker-runtime.mjs"), "utf8");

assert.equal(manifest.schemaVersion, 1);
assert.equal(manifest.namespace, "viking://resources/kafka-git");
assert.equal(policy.schemaVersion, 3);
assert.equal(policy.package, "openviking");
assert.equal(policy.releasePolicy, "latest-stable");
assert.equal(policy.platform, "linux");
assert.equal(policy.metadataUrl, "https://pypi.org/pypi/openviking/json");
assert.equal(policy.image, "ghcr.io/volcengine/openviking");
assert.equal(Object.hasOwn(policy, "version"), false);
for (const fragment of [
  "fetch(policy.metadataUrl",
  "metadata.info.version",
  "image version",
  "RepoDigests",
  "Persistent volumes retained",
]) assert.ok(bootstrap.includes(fragment), `missing latest-release bootstrap fragment: ${fragment}`);
assert.ok(!bootstrap.includes("0.4.19"));

const expected = new Map([
  ["kfk-tasks", "tasks"],
  ["kafka-adapter", "adapter/adapter"],
  ["kafka-adapter-base", "adapter/base"],
  ["kafka-adapter-examples", "adapter/examples"],
  ["kafka-adapter-conv", "conversion/KFK"],
  ["kafka-adapter-tests-unit", "tests/unit/unit"],
  ["kafka-adapter-tests-reports", "tests/reports"],
  ["kafka-adapter-tests-ui", "tests/ui"],
  ["kafka-tools", "tools"],
]);
assert.equal(manifest.repositories.length, expected.size);
for (const repository of manifest.repositories) {
  assert.equal(repository.root, expected.get(repository.id), `unexpected root for ${repository.id}`);
  assert.ok(fs.statSync(path.join(workspaceRoot, repository.root)).isDirectory());
  assert.ok(repository.include.length > 0);
  for (const pattern of [...repository.include, ...repository.exclude]) {
    assert.ok(!path.isAbsolute(pattern) && !pattern.includes("..") && !pattern.includes("\\"), pattern);
    assert.ok(!pattern.startsWith("src/") && !pattern.includes("/src/"), pattern);
    assert.ok(!pattern.startsWith(".codex/skills/"), pattern);
  }
  expected.delete(repository.id);
}
assert.equal(expected.size, 0);
assert.ok(manifest.repositories.find((item) => item.id === "kfk-tasks").exclude.includes("work/template.md"));
const expectedHookRoots = [
  "adapter/adapter", "adapter/base", "adapter/examples", "conversion/KFK",
  "tests/reports", "tests/ui", "tests/unit/unit", "tools", "tasks",
];
assert.deepEqual(manifest.hookRepositories.map((item) => item.root).sort(), expectedHookRoots.sort());
assert.equal(manifest.hookRepositories.some((item) => item.root === "tests/unit/yaxunit"), false);
process.stdout.write("openviking-manifest: fixed roots, latest-stable policy, and protected-source exclusions passed\n");
