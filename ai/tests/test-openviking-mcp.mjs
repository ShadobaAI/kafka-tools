import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { callTool, visibleTools } from "../openviking/read-only-mcp.mjs";
import { documentUri, inventory, loadManifest } from "../openviking/git-sync.mjs";

const aiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workspaceRoot = path.resolve(aiRoot, "..", "..");
const namespace = loadManifest().manifest.namespace;
const document = `${namespace}/kfk-tasks/sdd/spec-0011-code-index-bsl-ls-routing.md`;
assert.deepEqual(visibleTools().map((tool) => tool.name), ["find", "search", "read", "list", "tree"]);
assert.ok(visibleTools().every((tool) => tool.annotations.readOnlyHint &&
  !tool.annotations.destructiveHint));

class MockClient {
  constructor() { this.documents = new Map(); this.requests = []; }
  async ready() { return true; }
  async remove(uri, recursive) {
    if (recursive) this.documents.clear(); else this.documents.delete(uri);
  }
  async write(uri, content) { this.documents.set(uri, content); }
  async exists(uri) { return this.documents.has(uri); }
  async request(method, route, body) {
    this.requests.push([method, route, body]);
    if (route === "/api/v1/search/find") return { status: "ok", result: { resources: [
      { uri: document, level: 0, score: 0.9, abstract: "Kafka history" },
      { uri: `${namespace}/kfk-tasks/sdd/not-committed.md`, level: 0, score: 0.95, abstract: "untracked" },
      { uri: "viking://user/default/memories/private.md", level: 2, score: 1, abstract: "private" },
    ] } };
    if (route.startsWith("/api/v1/content/read?")) return { status: "ok", result: "# Kafka history" };
    if (route.startsWith("/api/v1/fs/ls?")) return { status: "ok", result: [
      { uri: `${namespace}/kfk-tasks`, isDir: true }, { uri: "viking://user/default/memories", isDir: true },
    ] };
    if (route.startsWith("/api/v1/fs/tree?")) return { status: "ok", result: [
      { uri: `${namespace}/kfk-tasks`, isDir: true },
    ] };
    throw new Error(`unexpected route ${route}`);
  }
}

const context = {
  workspaceRoot, stateDir: fs.mkdtempSync(path.join(os.tmpdir(), "kafka-openviking-mcp-")),
  client: new MockClient(),
};
fs.writeFileSync(path.join(context.stateDir, "runtime.json"), `${JSON.stringify({
  schemaVersion: 2, backend: "docker", version: "9.9.9", project: "kafka-openviking",
  image: `ghcr.io/volcengine/openviking@sha256:${"a".repeat(64)}`,
}, null, 2)}\n`);
const { manifest, runtime, digest } = loadManifest(undefined, path.join(context.stateDir, "runtime.json"));
const current = inventory(workspaceRoot, manifest);
fs.writeFileSync(path.join(context.stateDir, "state.json"), JSON.stringify({
  schemaVersion: 1, manifestDigest: digest, runtimeVersion: runtime.version,
  repositories: Object.fromEntries(Object.values(current).map((item) => [item.id, {
    revision: item.revision, files: item.files,
  }])),
}));
for (const item of Object.values(current)) {
  for (const file of Object.keys(item.files)) {
    context.client.documents.set(documentUri(namespace, item.id, file), "indexed");
  }
}
const found = await callTool("find", { query: "history", limit: 5 }, context);
assert.equal(found.entries.length, 1);
assert.ok(found.entries[0].uri.startsWith(namespace));
assert.equal(context.client.requests.at(-1)[2].target_uri, namespace);

const searched = await callTool("search", { query: "history", max_tokens: 100 }, context);
assert.ok(searched.text.includes("Kafka history"));
assert.ok(!searched.text.includes("private"));
await assert.rejects(callTool("search", { query: "history" }, context), /invalid tool arguments/);

const uri = document;
const read = await callTool("read", { uri, max_tokens: 100 }, context);
assert.equal(read.content, "# Kafka history");
await assert.rejects(callTool("read", { uri: "viking://user/default/memories/private.md", max_tokens: 100 }, context),
  /outside Git-backed Kafka context/);
await assert.rejects(callTool("remember", { messages: [] }, context), /unknown read-only tool/);

const listed = await callTool("list", { uri: namespace, limit: 5 }, context);
assert.equal(listed.entries.length, 1);
const tree = await callTool("tree", { uri: namespace, node_limit: 5 }, context);
assert.equal(tree.entries.length, 1);
process.stdout.write("openviking-mcp: five read-only tools, scoped results, and bounded search passed\n");
