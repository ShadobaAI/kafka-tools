import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { composeDocument, configuration, install, normalizeOllamaUrl, resolveOpenVikingImage, provisionAccount } from "../openviking/docker-runtime.mjs";
import { inventory, localClient, loadManifest, plan } from "../openviking/git-sync.mjs";
import { beginIndexReuse, finishIndexReuse, prepareIndexReuse } from "../openviking/index-preservation.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "kafka-docker-test-"));
const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
function seedIndexState(stateDir) {
  const { manifest, runtime, digest } = loadManifest(undefined, path.join(stateDir, "runtime.json"));
  const current = inventory(workspaceRoot, manifest);
  fs.writeFileSync(path.join(stateDir, "state.json"), JSON.stringify({
    schemaVersion: 1, manifestDigest: digest, runtimeVersion: runtime.version,
    repositories: Object.fromEntries(Object.values(current).map((item) => [item.id, {
      revision: item.revision, files: item.files,
    }])),
  }));
}
const originalFetch = globalThis.fetch;
try {
  const image = `ghcr.io/volcengine/openviking@sha256:${"a".repeat(64)}`;
  const options = { openvikingImage: image, ollamaImage: `ollama/ollama@sha256:${"b".repeat(64)}`,
    configFile: path.join(root, "configuration with spaces.conf") };
  const config = configuration("test-only-key");
  fs.writeFileSync(options.configFile, JSON.stringify(config));
  const compose = composeDocument(options);
  assert.deepEqual(compose.services.openviking.ports, ["127.0.0.1:1933:1933"]);
  assert.equal(compose.services.ollama.ports, undefined);
  assert.equal(compose.services.ollama.deploy, undefined);
  assert.equal(composeDocument({ ...options, gpu: true }).services.ollama.deploy.resources.reservations.devices[0].driver, "nvidia");
  assert.equal(config.storage.workspace, "/var/lib/openviking");
  assert.equal(config.embedding.dense.api_base, "http://ollama:11434/v1");
  assert.ok(!JSON.stringify(compose).includes("test-only-key"));
  assert.equal(normalizeOllamaUrl("http://GPU-HOST:11434/"), "http://gpu-host:11434");
  for (const url of ["file:///tmp/test", "http://user:password@gpu-host", "http://gpu-host/api", "http://gpu-host?key=x"]) {
    assert.throws(() => normalizeOllamaUrl(url), /Ollama URL/);
  }
  const remoteCompose = composeDocument({ ...options, externalOllama: true });
  assert.equal(remoteCompose.services.ollama, undefined);
  assert.equal(remoteCompose.services.openviking.depends_on, undefined);
  assert.equal(remoteCompose.volumes["ollama-models"], undefined);
  assert.equal(configuration("test-only-key", "http://gpu-host:11434").embedding.dense.api_base, "http://gpu-host:11434/v1");
  const composeFile = path.join(root, "compose.json");
  fs.writeFileSync(composeFile, JSON.stringify(compose));
  const validated = spawnSync("docker", ["compose", "-f", composeFile, "config", "--quiet"], { encoding: "utf8", windowsHide: true });
  assert.equal(validated.status, 0, validated.error?.message ?? validated.stderr);
  fs.writeFileSync(composeFile, JSON.stringify(remoteCompose));
  const remoteValidated = spawnSync("docker", ["compose", "-f", composeFile, "config", "--quiet"], { encoding: "utf8", windowsHide: true });
  assert.equal(remoteValidated.status, 0, remoteValidated.error?.message ?? remoteValidated.stderr);
  const runtimeFile = path.join(root, "runtime.json");
  fs.writeFileSync(runtimeFile, JSON.stringify({ schemaVersion: 1, version: "0.4.20", runtimeRoot: root }));
  assert.throws(() => loadManifest(undefined, runtimeFile), /unsupported/);
  await assert.rejects(install({ stateDir: root, yes: true }), /Legacy runtime/);
  fs.writeFileSync(runtimeFile, JSON.stringify({ schemaVersion: 2, backend: "docker", version: "0.4.20", project: "kafka-openviking", image }));
  assert.equal(loadManifest(undefined, runtimeFile).runtime.version, "0.4.20");
  const client = localClient(root);
  await assert.rejects(client.request("GET", "/health"), /ENOENT/);
  fs.writeFileSync(path.join(root, "api-key"), "root-must-not-access-data");
  fs.writeFileSync(path.join(root, "tenant-api-key"), "test-only-key");
  globalThis.fetch = async (url, options) => {
    assert.equal(options.headers["X-Api-Key"], "test-only-key");
    assert.equal(url, "http://127.0.0.1:1933/health");
    return { ok: true, json: async () => ({ status: "ok" }) };
  };
  await client.request("GET", "/health");
  const calls = [];
  const runtimeState = path.join(root, "deployment");
  let packageVersion = "0.4.20";
  let metadataVersion = "0.4.20";
  let activeServerVersion = "0.4.20";
  let consistent = true;
  let missingDocument = false;
  let failModel = false;
  const fakeDocker = (args) => {
    calls.push(args);
    if (args[0] === "info") return JSON.stringify({ OSType: "linux", Architecture: "x86_64", MemTotal: 8 * 2 ** 30 });
    if (args[0] === "ps") return "";
    if (args[0] === "image") return JSON.stringify([`${args[2].replace(/:[^/:]+$/, "")}@sha256:${"a".repeat(64)}`]);
    if (args[0] === "run") return packageVersion;
    if (args[0] === "compose" && args.includes("up") && args.includes("openviking")) activeServerVersion = packageVersion;
    if (args.includes("pull") && args.includes("ollama") && failModel) throw new Error("model unavailable");
    if (args.includes("run")) return JSON.stringify({ models: [
      { name: "qwen3-embedding:0.6b", digest: "embedding-digest" }, { name: "qwen3.5:4b", digest: "vlm-digest" },
    ] });
    return "";
  };
  const args = { stateDir: runtimeState, yes: true, docker: fakeDocker, checkPort: async () => false };
  await assert.rejects(install({ ...args, docker: () => { throw new Error("engine unavailable"); } }), /engine unavailable/);
  await assert.rejects(install({ ...args, checkPort: async () => true }), /Port 1933/);
  assert.equal(calls.some((args) => args[0] === "pull"), false);
  let accountCreations = 0;
  globalThis.fetch = async (url, options) => ({ ok: true, json: async () => {
    if (url.includes("pypi.org")) return { info: { version: metadataVersion } };
    if (url.endsWith("/health")) return { status: "ok", healthy: true, version: activeServerVersion };
    if (url.endsWith("/admin/accounts?name=kafka")) return { status: "ok", result: [] };
    if (url.endsWith("/admin/accounts")) {
      assert.equal(options.method, "POST");
      assert.deepEqual(JSON.parse(options.body), { account_id: "kafka", admin_user_id: "git-sync" });
      accountCreations += 1;
      return { status: "ok", result: { user_key: "tenant-test-key" } };
    }
    if (url.includes("/system/consistency")) return { status: "ok", result: {
      ok: consistent, expected_count: 100, missing_record_count: consistent ? 0 : 1, missing_records_truncated: false,
    } };
    if (url.includes("/fs/stat?")) {
      assert.equal(options.headers["X-Api-Key"], "tenant-test-key");
      return { status: "ok", result: { isDir: url.endsWith("viking%3A%2F%2Fresources") || missingDocument } };
    }
    return { status: "ready", checks: { embedding: "ok", vectordb: "ok",
      agfs: { status: "ok", checks: { filesystem: "ok", multiwrite_sync: "not_supported" } } } };
  } });
  packageVersion = "0.4.19";
  await assert.rejects(install(args), /does not match latest stable/);
  assert.equal(fs.existsSync(path.join(runtimeState, "runtime.json")), false);
  packageVersion = "0.4.20";
  failModel = true;
  await assert.rejects(install(args), /model unavailable/);
  assert.equal(fs.existsSync(path.join(runtimeState, "runtime.json")), false);
  await assert.rejects(localClient(runtimeState).request("GET", "/health"), /setup is incomplete/);
  assert.throws(() => loadManifest(undefined, path.join(runtimeState, "runtime.json")), /setup is incomplete/);
  failModel = false;
  await install(args);
  assert.equal(fs.existsSync(path.join(runtimeState, "docker-install.pending")), false);
  const firstRuntime = fs.readFileSync(path.join(runtimeState, "runtime.json"), "utf8");
  const firstConfig = fs.readFileSync(path.join(runtimeState, "ov.conf"), "utf8");
  seedIndexState(runtimeState);
  consistent = false;
  const callsBeforeUnsafeUpdate = calls.length;
  await assert.rejects(install(args), /consistency is not confirmed/);
  assert.equal(calls.slice(callsBeforeUnsafeUpdate).some((args) => args.includes("pull") || args.includes("up")), false,
    "unsafe update must stop before Docker pull or Compose up");
  consistent = true;
  missingDocument = true;
  await assert.rejects(install(args), /source is missing/);
  missingDocument = false;
  await install(args);
  assert.equal(accountCreations, 1, "repeat setup must reuse the tenant key");
  assert.equal(fs.readFileSync(path.join(runtimeState, "runtime.json"), "utf8"), firstRuntime);
  assert.equal(fs.readFileSync(path.join(runtimeState, "ov.conf"), "utf8"), firstConfig);
  assert.equal(calls.some((args) => args.includes("down") || args.includes("prune")), false);
  metadataVersion = "0.4.21";
  packageVersion = "0.4.21";
  const originalIndex = JSON.parse(fs.readFileSync(path.join(runtimeState, "state.json"), "utf8"));
  await install(args);
  const upgradedIndex = JSON.parse(fs.readFileSync(path.join(runtimeState, "state.json"), "utf8"));
  const upgradedManifest = loadManifest(undefined, path.join(runtimeState, "runtime.json"));
  assert.equal(upgradedIndex.runtimeVersion, "0.4.21");
  assert.deepEqual(upgradedIndex.repositories, originalIndex.repositories);
  assert.equal(plan(inventory(workspaceRoot, upgradedManifest.manifest), upgradedIndex,
    upgradedManifest.digest, "0.4.21").writes.length, 0);
  assert.equal(fs.existsSync(path.join(runtimeState, "index-update.json")), false);
  assert.equal(fs.existsSync(path.join(runtimeState, "docker-install.pending")), false);
  const interrupted = path.join(root, "interrupted-update");
  fs.mkdirSync(interrupted);
  fs.writeFileSync(path.join(interrupted, "runtime.json"), firstRuntime);
  fs.writeFileSync(path.join(interrupted, "state.json"), JSON.stringify(originalIndex));
  const indexClient = { ready: async () => {}, exists: async () => true };
  const consistencyClient = { request: async () => ({ status: "ok", result: {
    ok: true, expected_count: 100, missing_record_count: 0, missing_records_truncated: false,
  } }) };
  const reuseOptions = { stateDir: interrupted, workspaceRoot, targetVersion: "0.4.21",
    ollamaUrl: "http://ollama:11434", client: indexClient, consistencyClient };
  const beforeInterrupt = await prepareIndexReuse(reuseOptions);
  beginIndexReuse(interrupted, beforeInterrupt);
  fs.writeFileSync(path.join(interrupted, "docker-install.pending"), "pending\n");
  fs.writeFileSync(path.join(interrupted, "runtime.json"), JSON.stringify({
    ...JSON.parse(firstRuntime), version: "0.4.21",
  }));
  const resumed = await prepareIndexReuse(reuseOptions);
  assert.equal(resumed.resumed, true);
  await finishIndexReuse({ stateDir: interrupted, proof: resumed, models: resumed.oldModels,
    client: indexClient, consistencyClient });
  const migratedState = fs.readFileSync(path.join(interrupted, "state.json"), "utf8");
  await finishIndexReuse({ stateDir: interrupted, proof: await prepareIndexReuse(reuseOptions),
    models: resumed.oldModels, client: indexClient, consistencyClient });
  assert.equal(fs.readFileSync(path.join(interrupted, "state.json"), "utf8"), migratedState);
  fs.unlinkSync(path.join(interrupted, "docker-install.pending"));
  await prepareIndexReuse(reuseOptions);
  assert.equal(fs.existsSync(path.join(interrupted, "index-update.json")), false);
  fs.writeFileSync(path.join(runtimeState, "dirty"), "dirty\n");
  await assert.rejects(install(args), /missing or dirty/);
  fs.unlinkSync(path.join(runtimeState, "dirty"));
  metadataVersion = "0.4.22";
  const stateBeforeUnsupported = fs.readFileSync(path.join(runtimeState, "state.json"), "utf8");
  await assert.rejects(install(args), /no approved index compatibility/);
  assert.equal(fs.readFileSync(path.join(runtimeState, "state.json"), "utf8"), stateBeforeUnsupported);
  metadataVersion = "0.4.21";
  const remoteArgs = { ...args, stateDir: path.join(root, "remote"), ollamaUrl: "http://gpu-host:11434" };
  const providerFetch = globalThis.fetch;
  let missingEmbedding = true;
  let remoteEmbeddingDigest = "embedding-digest";
  globalThis.fetch = async (url, options) => url.endsWith("/api/tags") ? {
    ok: true, json: async () => ({ models: missingEmbedding ? [{ name: "qwen3.5:4b", digest: "vlm-digest" }] :
      [{ name: "qwen3.5:4b", digest: "vlm-digest" }, { name: "qwen3-embedding:0.6b", digest: remoteEmbeddingDigest }] }),
  } : providerFetch(url, options);
  calls.length = 0;
  await assert.rejects(install(remoteArgs), /missing qwen3-embedding/);
  assert.equal(calls.some((args) => args[0] === "pull"), false);
  await assert.rejects(install({ ...remoteArgs, gpu: true }), /Configure GPU on the external host/);
  missingEmbedding = false;
  await install(remoteArgs);
  seedIndexState(remoteArgs.stateDir);
  remoteEmbeddingDigest = "changed-embedding-digest";
  await assert.rejects(install(remoteArgs), /model qwen3-embedding:0.6b changed/);
  remoteEmbeddingDigest = "embedding-digest";
  assert.equal(calls.some((args) => args.includes("ollama/ollama:latest") || args.includes("ollama")), false);
  assert.ok(calls.some((args) => args.includes("run") && args.at(-1) === remoteArgs.ollamaUrl));
  const remoteState = JSON.parse(fs.readFileSync(path.join(remoteArgs.stateDir, "runtime.json"), "utf8"));
  assert.equal(remoteState.ollamaUrl, remoteArgs.ollamaUrl);
  assert.equal(remoteState.ollamaImage, null);
  await install({ ...remoteArgs, ollamaUrl: undefined });
  assert.equal(JSON.parse(fs.readFileSync(path.join(remoteArgs.stateDir, "runtime.json"), "utf8")).ollamaUrl, remoteArgs.ollamaUrl);
  const officialIndex = Buffer.from(JSON.stringify({ manifests: [{ platform: { os: "linux", architecture: "amd64" }, digest: `sha256:${"c".repeat(64)}` }] }));
  let badDigest = false;
  globalThis.fetch = async (url) => url.includes("/token?") ? { ok: true, json: async () => ({ token: "anonymous-test-token" }) } : {
    ok: true, arrayBuffer: async () => officialIndex,
    headers: new Headers({ "docker-content-digest": badDigest ? `sha256:${"0".repeat(64)}` : `sha256:${createHash("sha256").update(officialIndex).digest("hex")}` }),
  };
  const registryCalls = [];
  const deniedGhcr = (args) => {
    registryCalls.push(args);
    if (args[1].startsWith("ghcr.io/")) throw new Error("denied");
  };
  const mirrored = await resolveOpenVikingImage("0.4.20", "x86_64", deniedGhcr);
  assert.equal(mirrored.image, `docker.io/openviking/openviking@sha256:${"c".repeat(64)}`);
  assert.equal(mirrored.sourceImage, `ghcr.io/volcengine/openviking@sha256:${"c".repeat(64)}`);
  fs.writeFileSync(runtimeFile, JSON.stringify({ schemaVersion: 2, backend: "docker", version: "0.4.20", project: "kafka-openviking", ...mirrored }));
  assert.equal(loadManifest(undefined, runtimeFile).runtime.image, mirrored.image);
  fs.writeFileSync(runtimeFile, JSON.stringify({ schemaVersion: 2, backend: "docker", version: "0.4.20", project: "kafka-openviking", ...mirrored, sourceImage: image }));
  assert.throws(() => loadManifest(undefined, runtimeFile), /unsupported/);
  badDigest = true;
  registryCalls.length = 0;
  await assert.rejects(resolveOpenVikingImage("0.4.20", "amd64", deniedGhcr), /digest mismatch/);
  assert.equal(registryCalls.length, 1);
  const missingKey = path.join(root, "missing-tenant-key");
  fs.mkdirSync(missingKey);
  await assert.rejects(provisionAccount(missingKey, { request: async () => ({ result: [{ account_id: "kafka" }] }) }),
    /restore its saved key/);
  console.log("openviking-docker: Compose validation, isolation, persistent mounts, GPU profile, legacy rejection and local authentication passed");
  console.log("openviking-docker: missing Engine, occupied port, version/model failure, recovery and repeat-install checks passed (Docker/provider calls mocked)");
  console.log("openviking-docker: external endpoint persistence, model preflight and no managed Ollama downloads/services passed");
  console.log("openviking-docker: registry fallback pins official platform digest and rejects mismatches");
} finally {
  globalThis.fetch = originalFetch;
  fs.rmSync(root, { recursive: true, force: true });
}
