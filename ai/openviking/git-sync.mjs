import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import { request as httpRequest } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.join(moduleDir, "sources.json");
const releasePolicyPath = path.join(moduleDir, "version.json");
const STATE_SCHEMA = 1;
const INDEX_TIMEOUT_SECONDS = 600;

// Native fetch has a separate response-header timeout, shorter than ingestion.
// Use one explicit deadline for long requests, including the response body.
function longRequest(url, options) {
  return new Promise((resolve, reject) => {
    const request = httpRequest(url, options, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { body += chunk; });
      response.on("error", reject);
      response.on("end", () => resolve({
        ok: response.statusCode >= 200 && response.statusCode < 300,
        status: response.statusCode,
        json: async () => JSON.parse(body),
      }));
    });
    request.on("error", reject);
    request.end(options.body);
  });
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function globRegex(glob) {
  let result = "^";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    if (char === "*") {
      if (glob[index + 1] === "*") {
        index += 1;
        if (glob[index + 1] === "/") {
          index += 1;
          result += "(?:.*/)?";
        } else {
          result += ".*";
        }
      } else {
        result += "[^/]*";
      }
    } else {
      result += /[\\^$+?.()|{}\[\]]/.test(char) ? `\\${char}` : char;
    }
  }
  return new RegExp(`${result}$`);
}

export function loadManifest(manifestFile = sourcePath, runtimeFile) {
  const rawManifest = fs.readFileSync(manifestFile);
  const rawPolicy = fs.readFileSync(releasePolicyPath);
  const manifest = JSON.parse(rawManifest.toString("utf8"));
  const policy = JSON.parse(rawPolicy.toString("utf8"));
  if (manifest.schemaVersion !== 1 || policy.schemaVersion !== 3 ||
      policy.releasePolicy !== "latest-stable" || policy.package !== "openviking" ||
      manifest.namespace !== "viking://resources/kafka-git" ||
      !Array.isArray(manifest.hookRepositories) || manifest.hookRepositories.length === 0) {
    throw new Error("unsupported OpenViking manifest/release policy schema");
  }
  const hookIds = new Set();
  const hookRoots = new Set();
  for (const repository of manifest.hookRepositories) {
    if (!/^[a-z][a-z0-9-]*$/.test(repository.id) || hookIds.has(repository.id) ||
        typeof repository.root !== "string" || path.isAbsolute(repository.root) ||
        repository.root.includes("..") || repository.root.includes("\\") ||
        hookRoots.has(repository.root.toLowerCase())) {
      throw new Error(`invalid hook repository ${repository.id}`);
    }
    hookIds.add(repository.id);
    hookRoots.add(repository.root.toLowerCase());
  }
  const ids = new Set();
  for (const repository of manifest.repositories) {
    if (ids.has(repository.id) || !Array.isArray(repository.include) || repository.include.length === 0 ||
        !Array.isArray(repository.exclude) || !/^[a-z][a-z0-9-]*$/.test(repository.id) ||
        path.isAbsolute(repository.root) || repository.root.includes("..")) {
      throw new Error(`invalid source repository ${repository.id}`);
    }
    ids.add(repository.id);
    for (const pattern of [...repository.include, ...repository.exclude]) {
      if (typeof pattern !== "string" || pattern.includes("..") || pattern.includes("\\") ||
          pattern.startsWith("/") || pattern.startsWith("src/") || pattern.includes("/src/")) {
        throw new Error(`unsafe source pattern ${pattern}`);
      }
    }
  }
  for (const repository of manifest.repositories) {
    if (!hookIds.has(repository.id) ||
        !hookRoots.has(repository.root.toLowerCase())) {
      throw new Error(`source repository is missing from hook repositories: ${repository.id}`);
    }
  }
  let runtime;
  let rawRuntime = Buffer.alloc(0);
  if (runtimeFile) {
    if (fs.existsSync(path.join(path.dirname(runtimeFile), "docker-install.pending"))) {
      throw new Error("OpenViking Docker setup is incomplete; rerun the installer before reading context");
    }
    rawRuntime = fs.readFileSync(runtimeFile);
    runtime = JSON.parse(rawRuntime.toString("utf8").replace(/^\uFEFF/, ""));
    if (runtime.schemaVersion !== 2 || runtime.backend !== "docker" ||
        !/^\d+\.\d+\.\d+(?:\.post\d+)?$/.test(runtime.version) ||
        runtime.project !== "kafka-openviking" ||
        !(/^ghcr\.io\/volcengine\/openviking@sha256:[a-f0-9]{64}$/.test(runtime.image) ||
          (/^docker\.io\/openviking\/openviking@sha256:[a-f0-9]{64}$/.test(runtime.image) &&
           runtime.sourceImage === runtime.image.replace("docker.io/openviking/openviking@", "ghcr.io/volcengine/openviking@")))) {
      throw new Error("unsupported OpenViking active runtime record");
    }
  }
  return { manifest, policy, runtime,
    digest: sha256(Buffer.concat([rawManifest, rawPolicy, rawRuntime])) };
}

function git(repositoryRoot, args, options = {}) {
  return execFileSync("git", ["-c", `safe.directory=${repositoryRoot}`, "-C", repositoryRoot, ...args], {
    encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"], ...options,
  });
}

function safePathspec(pattern) {
  const wildcard = pattern.search(/[?*\[]/);
  const prefix = wildcard < 0 ? pattern : pattern.slice(0, wildcard);
  const result = prefix.endsWith("/") ? prefix.slice(0, -1) : prefix;
  if (!result || result === "." || result === "src" || result.includes("/src")) {
    throw new Error(`unsafe broad source pattern: ${pattern}`);
  }
  return result;
}

export function inventoryRepository(workspaceRoot, repository) {
  const repositoryRoot = path.resolve(workspaceRoot, repository.root);
  const expectedRoot = path.resolve(workspaceRoot);
  if (!repositoryRoot.startsWith(`${expectedRoot}${path.sep}`)) {
    throw new Error(`repository outside workspace: ${repository.id}`);
  }
  const revision = git(repositoryRoot, ["rev-parse", "HEAD"]).trim();
  if (!/^[a-f0-9]{40,64}$/.test(revision)) throw new Error(`invalid HEAD for ${repository.id}`);
  const pathspecs = [...new Set(repository.include.map(safePathspec))];
  const output = git(repositoryRoot, ["ls-tree", "-r", "-z", "HEAD", "--", ...pathspecs]);
  const included = repository.include.map(globRegex);
  const excluded = repository.exclude.map(globRegex);
  const files = {};
  for (const item of output.split("\0")) {
    if (!item) continue;
    const match = /^[0-7]+ blob ([a-f0-9]{40,64})\t(.+)$/s.exec(item);
    if (!match) throw new Error(`unsupported Git tree entry in ${repository.id}`);
    const file = match[2];
    if (!included.some((pattern) => pattern.test(file)) || excluded.some((pattern) => pattern.test(file))) continue;
    if (!file.endsWith(".md") || file.startsWith("src/") || file.includes("/src/")) {
      throw new Error(`unsafe indexed file ${repository.id}:${file}`);
    }
    files[file] = match[1];
  }
  return { id: repository.id, root: repositoryRoot, revision, files };
}

export function inventory(workspaceRoot, manifest) {
  return Object.fromEntries(manifest.repositories.map((repository) => {
    const item = inventoryRepository(workspaceRoot, repository);
    return [item.id, item];
  }));
}

function readState(stateFile) {
  try { return JSON.parse(fs.readFileSync(stateFile, "utf8")); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

function isAncestor(repositoryRoot, oldRevision, revision) {
  if (oldRevision === revision) return true;
  try { git(repositoryRoot, ["merge-base", "--is-ancestor", oldRevision, revision]); return true; }
  catch { return false; }
}

export function plan(current, previous, digest, runtimeVersion, forceRebuild = false) {
  const rebuild = forceRebuild || !previous || previous.schemaVersion !== STATE_SCHEMA ||
    previous.manifestDigest !== digest || previous.runtimeVersion !== runtimeVersion ||
    Object.keys(previous.repositories ?? {}).sort().join("|") !== Object.keys(current).sort().join("|") ||
    Object.values(current).some((item) => {
      const old = previous?.repositories?.[item.id];
      return !old || !isAncestor(item.root, old.revision, item.revision);
    });
  const deletes = [];
  const writes = [];
  for (const item of Object.values(current)) {
    const oldFiles = rebuild ? {} : previous.repositories[item.id].files;
    for (const file of Object.keys(oldFiles)) {
      if (!Object.hasOwn(item.files, file)) deletes.push([item.id, file]);
    }
    for (const [file, oid] of Object.entries(item.files)) {
      if (rebuild || oldFiles[file] !== oid) writes.push([item.id, file, oid]);
    }
  }
  return { rebuild, deletes, writes };
}

export function documentUri(namespace, repositoryId, file) {
  if (!/^[a-z][a-z0-9-]*$/.test(repositoryId) || !/^[\p{L}\p{N}_./ -]+\.md$/u.test(file) ||
      file.includes("..") || file.startsWith("/") || file.includes("\\")) {
    throw new Error("unsafe document URI");
  }
  return `${namespace}/${repositoryId}/${file}`;
}

export class OpenVikingClient {
  constructor(baseUrl = "http://127.0.0.1:1933", apiKey = process.env.OPENVIKING_API_KEY) {
    const url = new URL(baseUrl);
    if (url.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
      throw new Error("OpenViking URL must be local HTTP");
    }
    this.baseUrl = url.toString().replace(/\/$/, "");
    this.apiKey = apiKey;
  }

  async request(method, route, body, timeoutMs = 120000) {
    const headers = { ...(body === undefined ? {} : { "Content-Type": "application/json" }) };
    if (this.apiKey) headers["X-Api-Key"] = this.apiKey;
    const transport = timeoutMs > 120000 ? longRequest : fetch;
    const response = await transport(`${this.baseUrl}${route}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const value = await response.json();
    if (!response.ok || value.status === "error") {
      const error = new Error(`OpenViking ${route}: HTTP ${response.status}`);
      error.status = response.status;
      error.code = value.error?.code;
      throw error;
    }
    return value;
  }

  async ready(version) {
    const health = await this.request("GET", "/health", undefined, 15000);
    const readiness = await this.request("GET", "/ready", undefined, 15000);
    const serverVersion = typeof health.version === "string" ? health.version.replace(/^v/, "") : null;
    if (health.status !== "ok" || health.healthy !== true || serverVersion !== version ||
        readiness.status !== "ready") throw new Error("OpenViking runtime is not ready at the selected latest version");
    // Upstream /ready permits not_configured. Semantic retrieval requires both providers and storage.
    const checks = readiness.checks;
    if (checks?.embedding !== "ok" || checks?.vectordb !== "ok" ||
        checks?.agfs?.status !== "ok" || checks.agfs.checks?.filesystem !== "ok" ||
        !["ok", "not_supported"].includes(checks.agfs.checks?.multiwrite_sync)) {
      throw new Error("OpenViking embedding/vector/filesystem readiness is incomplete");
    }
  }

  async remove(uri, recursive = false) {
    const query = new URLSearchParams({ uri, recursive: String(recursive) });
    let result;
    try { result = await this.request("DELETE", `/api/v1/fs?${query}`); }
    catch (error) {
      if (error.status === 404 && error.code === "NOT_FOUND") return;
      throw error;
    }
    if (result.status !== "ok") throw new Error("OpenViking removal incomplete");
  }

  async write(uri, content) {
    let value;
    try {
      value = await this.request("POST", "/api/v1/content/write", {
        uri, content, mode: "replace", wait: true, timeout: INDEX_TIMEOUT_SECONDS,
      }, (INDEX_TIMEOUT_SECONDS + 30) * 1000);
    } catch (error) {
      throw new Error(`OpenViking indexing failed for ${uri} (server wait: ${INDEX_TIMEOUT_SECONDS}s; HTTP deadline: ${INDEX_TIMEOUT_SECONDS + 30}s): ${error.message}. Write outcome is unverified; no automatic retry.`, { cause: error });
    }
    const result = value.result ?? {};
    if (value.status !== "ok" || result.semantic_status !== "complete" || result.vector_status !== "complete") {
      throw new Error(`OpenViking indexing incomplete for ${uri}`);
    }
  }

  async exists(uri) {
    const value = await this.request("GET", `/api/v1/fs/stat?${new URLSearchParams({ uri })}`);
    return value.status === "ok" && value.result?.isDir === false;
  }
}

// Read the locally generated key only when a request is made; tools/list remains
// available during configuration-only installation, before Docker setup.
export function localClient(stateDir) {
  const client = new OpenVikingClient();
  Object.defineProperty(client, "apiKey", { get() {
    if (fs.existsSync(path.join(stateDir, "docker-install.pending"))) {
      throw new Error("OpenViking Docker setup is incomplete; context reads are blocked");
    }
    return fs.readFileSync(path.join(stateDir, "tenant-api-key"), "utf8").trim();
  } });
  return client;
}

export async function reconcile({ workspaceRoot, stateDir, client, forceRebuild = false, allowRebuild = true,
                                  manifestFile = sourcePath, runtimeFile, progress = () => {} }) {
  const activeRuntimeFile = runtimeFile ?? path.join(stateDir, "runtime.json");
  const { manifest, runtime, digest } = loadManifest(manifestFile, activeRuntimeFile);
  const current = inventory(workspaceRoot, manifest);
  await client.ready(runtime.version);
  fs.mkdirSync(stateDir, { recursive: true });
  const lock = path.join(stateDir, "sync.lock");
  fs.mkdirSync(lock);
  try {
    const stateFile = path.join(stateDir, "state.json");
    const dirtyFile = path.join(stateDir, "dirty");
    const previous = readState(stateFile);
    const changes = plan(current, previous, digest, runtime.version,
      forceRebuild || fs.existsSync(dirtyFile));
    if (changes.rebuild && !allowRebuild) {
      const error = new Error("Нужна полная перестройка: состояние отсутствует, незавершено или несовместимо с текущими Git/runtime/manifest. Индекс не изменён. Для явного запуска используйте update-openviking.cmd --rebuild.");
      error.code = "OPENVIKING_REBUILD_REQUIRED";
      throw error;
    }
    progress(`Режим: ${changes.rebuild ? "полная перестройка" : "инкрементальный"}; документов к записи: ${changes.writes.length}; отдельных удалений: ${changes.deletes.length}.`);
    if (changes.rebuild || changes.deletes.length || changes.writes.length) {
      fs.writeFileSync(dirtyFile, "rebuild-required\n");
    }
    if (changes.rebuild) await client.remove(manifest.namespace, true);
    else for (const [repo, file] of changes.deletes) await client.remove(documentUri(manifest.namespace, repo, file));
    let completed = 0;
    for (const [repo, file, oid] of changes.writes) {
      progress(`Indexing ${completed + 1}/${changes.writes.length}: ${repo}:${file}`);
      const content = git(current[repo].root, ["cat-file", "blob", oid]);
      await client.write(documentUri(manifest.namespace, repo, file), content);
      completed += 1;
    }
    for (const item of Object.values(current)) {
      for (const file of Object.keys(item.files)) {
        if (!await client.exists(documentUri(manifest.namespace, item.id, file))) {
          throw new Error(`OpenViking source missing: ${item.id}:${file}`);
        }
      }
    }
    // HEAD might change during a long rebuild; never publish a stale revision as ready.
    for (const item of Object.values(current)) {
      if (git(item.root, ["rev-parse", "HEAD"]).trim() !== item.revision) {
        throw new Error(`HEAD changed during sync: ${item.id}`);
      }
    }
    const next = {
      schemaVersion: STATE_SCHEMA, manifestDigest: digest, runtimeVersion: runtime.version,
      repositories: Object.fromEntries(Object.values(current).map((item) => [item.id, {
        revision: item.revision, files: item.files,
      }])),
    };
    const temporary = path.join(stateDir, `state.${process.pid}.tmp`);
    fs.writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`, { flag: "wx" });
    fs.renameSync(temporary, stateFile);
    if (fs.existsSync(dirtyFile)) fs.unlinkSync(dirtyFile);
    return { status: "ready", mode: changes.rebuild ? "rebuild" : "incremental",
      writes: changes.writes.length, deletes: changes.deletes.length,
      revisions: Object.fromEntries(Object.values(current).map((item) => [item.id, item.revision])) };
  } catch (error) {
    if (error.code !== "OPENVIKING_REBUILD_REQUIRED") fs.writeFileSync(path.join(stateDir, "dirty"), "rebuild-required\n");
    throw error;
  } finally {
    fs.rmdirSync(lock);
  }
}

function argument(argv, name) {
  const index = argv.indexOf(name);
  return index < 0 ? undefined : argv[index + 1];
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const workspaceRoot = argument(process.argv, "--workspace-root");
  const stateDir = argument(process.argv, "--state-dir");
  if (!workspaceRoot || !stateDir) {
    process.stderr.write("usage: node git-sync.mjs --workspace-root PATH --state-dir PATH [--rebuild]\n");
    process.exitCode = 2;
  } else {
    reconcile({ workspaceRoot, stateDir, client: localClient(stateDir),
      progress: (message) => process.stderr.write(`openviking-sync: ${message}\n`),
      forceRebuild: process.argv.includes("--rebuild") })
      .then((result) => process.stdout.write(`${JSON.stringify(result)}\n`))
      .catch((error) => { process.stderr.write(`openviking-sync: ${error.message}\n`); process.exitCode = 1; });
  }
}
