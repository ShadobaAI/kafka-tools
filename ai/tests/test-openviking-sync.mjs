import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { documentUri, inventory, loadManifest, plan, reconcile, OpenVikingClient } from "../openviking/git-sync.mjs";

const aiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.resolve(aiRoot, "..", "..");
const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-sync-"));
const runtimeFile = path.join(stateDir, "runtime.json");
fs.writeFileSync(runtimeFile, `${JSON.stringify({
  schemaVersion: 2, backend: "docker", version: "9.9.9", project: "kafka-openviking",
  image: `ghcr.io/volcengine/openviking@sha256:${"a".repeat(64)}`,
}, null, 2)}\n`);
const { manifest, runtime, digest } = loadManifest(undefined, runtimeFile);
// Only a typed missing-resource response is an idempotent removal. Never
// swallow authentication, authorization, transport or unrelated 404 failures.
const originalFetch = globalThis.fetch;
try {
  const removalClient = new OpenVikingClient(undefined, "test-tenant-key");
  for (const [status, code, allowed] of [[404, "NOT_FOUND", true], [403, "PERMISSION_DENIED", false],
    [401, "UNAUTHENTICATED", false], [500, "INTERNAL", false], [404, undefined, false]]) {
    globalThis.fetch = async () => ({ ok: false, status, json: async () => ({ status: "error", error: { code } }) });
    if (allowed) await removalClient.remove(manifest.namespace, true);
    else await assert.rejects(removalClient.remove(manifest.namespace, true), new RegExp(`HTTP ${status}`));
  }
} finally { globalThis.fetch = originalFetch; }
const readiness = { status: "ready", checks: { embedding: "ok", vectordb: "ok",
  agfs: { status: "ok", checks: { filesystem: "ok", multiwrite_sync: "not_supported" } } } };
const readinessClient = new OpenVikingClient();
let readyResponse = readiness;
let healthVersion = runtime.version;
readinessClient.request = async (_, route, body, timeout) => {
  assert.equal(body, undefined);
  assert.equal(timeout, 15000);
  return route === "/health" ? { status: "ok", healthy: true, version: healthVersion } : readyResponse;
};
await readinessClient.ready(runtime.version);
healthVersion = `v${runtime.version}`;
await readinessClient.ready(runtime.version);
healthVersion = `v${runtime.version}.dev1`;
await assert.rejects(readinessClient.ready(runtime.version), /not ready at the selected latest version/);
healthVersion = runtime.version;
for (const mutate of [
  (item) => { delete item.checks; },
  (item) => { item.checks.embedding = "not_configured"; },
  (item) => { item.checks.vectordb = "not_configured"; },
  (item) => { item.checks.agfs.checks.filesystem = "error"; },
  (item) => { item.checks.agfs.checks.multiwrite_sync = "error"; },
]) {
  readyResponse = structuredClone(readiness);
  mutate(readyResponse);
  await assert.rejects(readinessClient.ready(runtime.version), /readiness is incomplete/);
}
const current = inventory(workspaceRoot, manifest);
assert.equal(Object.keys(current).length, 9);
assert.ok(Object.values(current).reduce((total, item) => total + Object.keys(item.files).length, 0) > 0);
for (const item of Object.values(current)) {
  for (const file of Object.keys(item.files)) documentUri(manifest.namespace, item.id, file);
}

const previous = {
  schemaVersion: 1, manifestDigest: digest, runtimeVersion: runtime.version,
  repositories: Object.fromEntries(Object.values(current).map((item) => [item.id, {
    revision: item.revision, files: item.files,
  }])),
};
let changes = plan(current, previous, digest, runtime.version);
assert.equal(changes.rebuild, false);
assert.equal(changes.writes.length, 0);
assert.equal(changes.deletes.length, 0);

const firstId = Object.keys(current)[0];
const firstFile = Object.keys(current[firstId].files)[0];
const previousModified = structuredClone(previous);
previousModified.repositories[firstId].files[firstFile] = "0".repeat(40);
changes = plan(current, previousModified, digest, runtime.version);
assert.equal(changes.rebuild, false);
assert.deepEqual(changes.writes, [[firstId, firstFile, current[firstId].files[firstFile]]]);
assert.equal(plan(current, previous, "changed-manifest", runtime.version).rebuild, true);
assert.equal(plan(current, previous, digest, "changed-runtime").rebuild, true);
assert.equal(plan(current, previous, digest, runtime.version, true).rebuild, true);

class MockOpenViking {
  constructor() { this.documents = new Map(); this.removals = []; this.writes = []; this.failAfter = Infinity; }
  async ready(version) { assert.equal(version, runtime.version); }
  async remove(uri, recursive = false) {
    this.removals.push([uri, recursive]);
    if (recursive) this.documents.clear();
    else this.documents.delete(uri);
  }
  async write(uri, content) {
    if (this.writes.length >= this.failAfter) throw new Error("simulated partial sync failure");
    assert.equal(typeof content, "string");
    this.writes.push(uri);
    this.documents.set(uri, content);
  }
  async exists(uri) { return this.documents.has(uri); }
}

const client = new MockOpenViking();
await assert.rejects(reconcile({ workspaceRoot, stateDir, client, allowRebuild: false }), /--rebuild/);
assert.equal(client.writes.length, 0);
assert.equal(client.removals.length, 0);
assert.equal(fs.existsSync(path.join(stateDir, "dirty")), false);
assert.equal(fs.existsSync(path.join(stateDir, "sync.lock")), false);
const first = await reconcile({ workspaceRoot, stateDir, client });
assert.equal(first.status, "ready");
assert.equal(first.mode, "rebuild");
assert.equal(first.writes, client.documents.size);
assert.deepEqual(client.removals, [[manifest.namespace, true]]);
const stateFile = path.join(stateDir, "state.json");
const stateBefore = fs.readFileSync(stateFile, "utf8");

const second = await reconcile({ workspaceRoot, stateDir, client, allowRebuild: false });
assert.equal(second.mode, "incremental");
assert.equal(second.writes, 0);
assert.equal(second.deletes, 0);
assert.equal(fs.readFileSync(stateFile, "utf8"), stateBefore);

fs.writeFileSync(stateFile, JSON.stringify(previousModified));
const writesBefore = client.writes.length, removalsBefore = client.removals.length;
const incremental = await reconcile({ workspaceRoot, stateDir, client, allowRebuild: false });
assert.equal(incremental.mode, "incremental");
assert.equal(incremental.writes, 1);
assert.equal(client.writes.length, writesBefore + 1);
assert.equal(client.removals.length, removalsBefore);

client.failAfter = client.writes.length;
await assert.rejects(reconcile({ workspaceRoot, stateDir, client, forceRebuild: true }),
  /simulated partial sync failure/);
assert.equal(fs.readFileSync(stateFile, "utf8"), stateBefore, "partial failure must not publish a new revision");
assert.equal(fs.existsSync(path.join(stateDir, "sync.lock")), false);
assert.equal(fs.existsSync(path.join(stateDir, "dirty")), true);
const failedWrites = client.writes.length, failedRemovals = client.removals.length;
await assert.rejects(reconcile({ workspaceRoot, stateDir, client, allowRebuild: false }), /--rebuild/);
assert.equal(client.writes.length, failedWrites);
assert.equal(client.removals.length, failedRemovals);
assert.equal(fs.existsSync(path.join(stateDir, "dirty")), true);
client.failAfter = Infinity;
const recovered = await reconcile({ workspaceRoot, stateDir, client });
assert.equal(recovered.mode, "rebuild");
assert.equal(fs.existsSync(path.join(stateDir, "dirty")), false);

process.stdout.write("openviking-sync: committed inventory, initial build, no-op, failed rebuild, and recovery passed\n");
