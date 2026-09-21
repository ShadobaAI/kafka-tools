import fs from "node:fs";
import path from "node:path";
import net from "node:net";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline/promises";
import { OpenVikingClient } from "./git-sync.mjs";

const directory = path.dirname(fileURLToPath(import.meta.url));
export const project = "kafka-openviking";
export const models = { embedding: "qwen3-embedding:0.6b", vlm: "qwen3.5:4b" };
const digestPattern = /^sha256:[a-f0-9]{64}$/;

export async function provisionAccount(stateDir, rootClient) {
  const keyFile = path.join(stateDir, "tenant-api-key");
  let key;
  if (fs.existsSync(keyFile)) key = fs.readFileSync(keyFile, "utf8").trim();
  else {
    const accounts = await rootClient.request("GET", "/api/v1/admin/accounts?name=kafka");
    if (!Array.isArray(accounts.result)) throw new Error("Invalid OpenViking account inventory");
    if (accounts.result.some((account) => account.account_id === "kafka")) {
      throw new Error("OpenViking Kafka account exists but tenant-api-key is missing; restore its saved key before setup.");
    }
    const created = await rootClient.request("POST", "/api/v1/admin/accounts", {
      account_id: "kafka", admin_user_id: "git-sync",
    });
    key = created.result?.user_key;
    if (typeof key !== "string" || !key.trim()) throw new Error("OpenViking did not issue a tenant API key");
    fs.writeFileSync(keyFile, key, { flag: "wx", mode: 0o600 });
  }
  // ROOT keys cannot access data APIs. Check the actual tenant scope before
  // publishing a ready runtime, including on repeat installations.
  const tenant = new OpenVikingClient(undefined, key);
  const scope = await tenant.request("GET", "/api/v1/fs/stat?uri=viking%3A%2F%2Fresources");
  if (scope.status !== "ok" || scope.result?.isDir !== true) {
    throw new Error("OpenViking Kafka resource scope is not ready");
  }
}

export function normalizeOllamaUrl(value) {
  const url = new URL(value);
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password ||
      url.pathname !== "/" || url.search || url.hash) {
    throw new Error("Ollama URL must be an HTTP(S) origin without credentials, path or query.");
  }
  return url.origin;
}

export function configuration(apiKey, ollamaUrl = "http://ollama:11434") {
  ollamaUrl = normalizeOllamaUrl(ollamaUrl);
  return {
    server: { host: "0.0.0.0", port: 1933, root_api_key: apiKey },
    storage: { workspace: "/var/lib/openviking" },
    embedding: { dense: { provider: "ollama", model: models.embedding,
      api_base: `${ollamaUrl}/v1`, dimension: 1024, input: "text" } },
    vlm: { provider: "litellm", model: `ollama/${models.vlm}`, api_key: "no-key",
      api_base: ollamaUrl, temperature: 0, max_retries: 2,
      extra_request_body: { num_ctx: 16384, think: false } },
  };
}

export function composeDocument({ openvikingImage, ollamaImage, configFile, gpu = false, externalOllama = false, configDigest }) {
  const document = { name: project, services: {
    ollama: {
      image: ollamaImage, restart: "unless-stopped",
      environment: { OLLAMA_NUM_PARALLEL: "1", OLLAMA_MAX_LOADED_MODELS: "1" },
      volumes: ["ollama-models:/root/.ollama"],
      healthcheck: { test: ["CMD", "ollama", "list"], interval: "10s", timeout: "5s", retries: 12 },
      ...(gpu ? { deploy: { resources: { reservations: { devices: [
        { driver: "nvidia", count: "all", capabilities: ["gpu"] },
      ] } } } } : {}),
    },
    openviking: {
      image: openvikingImage, restart: "unless-stopped",
      ...(configDigest ? { labels: { "io.kafka.openviking.config-sha256": configDigest } } : {}),
      entrypoint: ["python", "-m", "openviking_cli.server_bootstrap"],
      command: ["--config", "/etc/openviking/ov.conf", "--host", "0.0.0.0", "--port", "1933"],
      ports: ["127.0.0.1:1933:1933"],
      volumes: ["openviking-data:/var/lib/openviking",
        { type: "bind", source: configFile, target: "/etc/openviking/ov.conf", read_only: true }],
      depends_on: { ollama: { condition: "service_healthy" } },
    },
  }, volumes: { "ollama-models": {}, "openviking-data": {} } };
  if (externalOllama) {
    delete document.services.ollama;
    delete document.services.openviking.depends_on;
    delete document.volumes["ollama-models"];
  }
  return document;
}

function runDocker(args, { capture = false, input, timeout = 1800000 } = {}) {
  const result = spawnSync("docker", args, { encoding: "utf8", windowsHide: true,
    timeout, maxBuffer: 4 * 1024 * 1024,
    stdio: [input === undefined ? "ignore" : "pipe", capture ? "pipe" : "inherit", capture ? "pipe" : "inherit"], input });
  if (result.error || result.status !== 0) {
    // Never include stdin or captured output: these may contain user configuration.
    throw new Error(`docker ${args.slice(0, 2).join(" ")} failed (${result.error?.code ?? result.status}). Check Docker Desktop and service logs.`);
  }
  return (result.stdout ?? "").trim();
}

function writeJson(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, file);
}

export async function portInUse(port = 1933) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    const done = (value) => { socket.destroy(); resolve(value); };
    socket.once("connect", () => done(true));
    socket.once("error", () => done(false));
    socket.setTimeout(2000, () => done(true));
  });
}

function resolveImage(repository, tag, docker) {
  const image = `${repository}:${tag}`;
  docker(["pull", image]);
  const digests = JSON.parse(docker(["image", "inspect", image, "--format", "{{json .RepoDigests}}"], { capture: true }));
  const selected = digests.find((item) => item.startsWith(`${repository}@`));
  if (!selected || !digestPattern.test(selected.split("@")[1])) throw new Error(`No verified image digest for ${repository}`);
  return selected;
}

export async function resolveOpenVikingImage(version, architecture, docker) {
  const repository = "ghcr.io/volcengine/openviking";
  try {
    const image = resolveImage(repository, `v${version}`, docker);
    return { image, sourceImage: image };
  } catch {
    console.log("GHCR Docker pull failed. Verifying the official platform digest before trying Docker Hub...");
  }
  const arch = { x86_64: "amd64", amd64: "amd64", aarch64: "arm64", arm64: "arm64" }[architecture];
  if (!arch) throw new Error("Unsupported Docker architecture for verified registry fallback.");
  const access = await fetch("https://ghcr.io/token?service=ghcr.io&scope=repository:volcengine/openviking:pull",
    { signal: AbortSignal.timeout(30000) });
  if (!access.ok) throw new Error("Cannot verify the official GHCR release; registry fallback refused.");
  const { token } = await access.json();
  if (!token) throw new Error("GHCR anonymous access did not return a token.");
  const response = await fetch(`https://ghcr.io/v2/volcengine/openviking/manifests/v${version}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" },
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error("Official release manifest is unavailable; registry fallback refused.");
  const bytes = Buffer.from(await response.arrayBuffer());
  const digest = `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
  if (response.headers.get("docker-content-digest") !== digest) throw new Error("Official manifest digest mismatch.");
  const manifest = JSON.parse(bytes.toString("utf8"));
  const platforms = manifest.manifests?.filter((item) => item.platform?.os === "linux" && item.platform?.architecture === arch);
  if (platforms?.length !== 1 || !digestPattern.test(platforms[0].digest)) throw new Error("Official release has no unambiguous compatible platform manifest.");
  const platformDigest = platforms[0].digest;
  // Registry location changes, image bytes cannot: Docker verifies the same
  // manifest/layer hashes published by the official GHCR release.
  const image = `docker.io/openviking/openviking@${platformDigest}`;
  console.log(`Pulling the verified official ${arch} image through Docker Hub: ${platformDigest}`);
  docker(["pull", image]);
  return { image, sourceImage: `${repository}@${platformDigest}` };
}

export async function install({ stateDir, yes = false, gpu = false, ollamaUrl,
                                docker = runDocker, checkPort = portInUse }) {
  stateDir = path.resolve(stateDir);
  const workspace = path.resolve(directory, "../../..");
  const relative = path.relative(workspace, stateDir);
  if (!relative || (!relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative))) {
    throw new Error("Docker state must be outside the Kafka workspace.");
  }
  const runtimeFile = path.join(stateDir, "runtime.json");
  if (fs.existsSync(runtimeFile)) {
    const prior = JSON.parse(fs.readFileSync(runtimeFile, "utf8").replace(/^\uFEFF/, ""));
    if (prior.schemaVersion !== 2 || prior.backend !== "docker") {
      throw new Error("Legacy runtime state is unsupported. Select a fresh -OpenVikingStateDir; no migration is performed.");
    }
    ollamaUrl ??= prior.ollamaUrl;
  }
  const externalOllama = Boolean(ollamaUrl && normalizeOllamaUrl(ollamaUrl) !== "http://ollama:11434");
  ollamaUrl = normalizeOllamaUrl(ollamaUrl || "http://ollama:11434");
  if (externalOllama && gpu) throw new Error("-OpenVikingGpu applies only to managed Ollama. Configure GPU on the external host.");
  const info = JSON.parse(docker(["info", "--format", "{{json .}}"], { capture: true, timeout: 30000 }));
  if (info.OSType !== "linux") throw new Error("Docker Desktop must use Linux containers.");
  docker(["compose", "version"], { timeout: 30000 });
  const owners = docker(["ps", "--filter", `label=com.docker.compose.project=${project}`,
    "--filter", "label=com.docker.compose.service=openviking", "--format", "{{.ID}}"], { capture: true });
  if (owners) {
    const configurations = docker(["inspect", owners, "--format",
      '{{index .Config.Labels "com.docker.compose.project.config_files"}}'], { capture: true });
    if (path.resolve(configurations) !== path.join(stateDir, "compose.json")) {
      throw new Error("The Docker project belongs to another state directory. Reuse its -OpenVikingStateDir.");
    }
  }
  if (await checkPort() && !owners) throw new Error("Port 1933 is occupied by an unmanaged service. Stop it explicitly before setup.");
  console.log(`Docker memory: ${(info.MemTotal / 2 ** 30).toFixed(1)} GiB; mode: ${externalOllama ? "external Ollama" : gpu ? "NVIDIA GPU" : "CPU"}.`);
  if (externalOllama) {
    console.log(`Using existing models at ${ollamaUrl}. No Ollama image or models will be downloaded in this VM.`);
    const response = await fetch(`${ollamaUrl}/api/tags`, { signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("External Ollama model inventory failed.");
    const available = (await response.json()).models;
    for (const model of Object.values(models)) {
      if (!available?.some((item) => item.name === model)) throw new Error(`External Ollama is missing ${model}; install it on that host.`);
    }
  } else {
    console.log(`Models: ${models.embedding} (~0.64 GB) + ${models.vlm} (~3.4 GB), plus container images. Other containers share RAM.`);
  }
  if (!yes) {
    const reader = createInterface({ input: process.stdin, output: process.stdout });
    try {
      const prompt = externalOllama ? "Download/update the OpenViking image and connect to external Ollama? [y/N] " :
        "Download/update these images and models and start services? [y/N] ";
      if (!/^y(es)?$/i.test((await reader.question(prompt)).trim())) {
        throw new Error("Docker setup cancelled before downloads.");
      }
    } finally { reader.close(); }
  }
  fs.mkdirSync(stateDir, { recursive: true });
  const lock = path.join(stateDir, "docker-install.lock");
  fs.mkdirSync(lock);
  try {
    const pending = path.join(stateDir, "docker-install.pending");
    fs.writeFileSync(pending, "Docker setup must finish before context reads.\n");
    const policy = JSON.parse(fs.readFileSync(path.join(directory, "version.json"), "utf8"));
    if (policy.schemaVersion !== 3 || policy.releasePolicy !== "latest-stable" ||
        policy.metadataUrl !== "https://pypi.org/pypi/openviking/json" ||
        policy.image !== "ghcr.io/volcengine/openviking" || policy.platform !== "linux") {
      throw new Error("Unsupported Docker release policy.");
    }
    const response = await fetch(policy.metadataUrl, { signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error("Cannot resolve latest stable OpenViking release.");
    const metadata = await response.json();
    const version = metadata.info.version;
    if (!/^\d+\.\d+\.\d+(?:\.post\d+)?$/.test(version)) throw new Error("Latest release is not stable.");
    const { image: openvikingImage, sourceImage } = await resolveOpenVikingImage(version, info.Architecture, docker);
    const installed = docker(["run", "--rm", "--entrypoint", "python", openvikingImage,
      "-c", "import importlib.metadata; print(importlib.metadata.version('openviking'))"], { capture: true });
    if (installed !== version) throw new Error(`Official image version ${installed} does not match latest stable ${version}.`);
    const ollamaImage = externalOllama ? null : resolveImage("ollama/ollama", "latest", docker);
    const configFile = path.join(stateDir, "ov.conf");
    const keyFile = path.join(stateDir, "api-key");
    const hasConfig = fs.existsSync(configFile);
    const hasKey = fs.existsSync(keyFile);
    let saved;
    if (hasConfig) {
      try { saved = JSON.parse(fs.readFileSync(configFile, "utf8")); }
      catch { throw new Error("Cannot read Docker provider configuration; restore ov.conf before setup."); }
    }
    // A previous run can stop between writing the key and the configuration.
    // Recover the missing file using the surviving key, never rotating it.
    const key = hasKey ? fs.readFileSync(keyFile, "utf8").trim() :
      hasConfig ? saved?.server?.root_api_key : randomBytes(32).toString("hex");
    if (typeof key !== "string" || !key.trim() || key !== key.trim() ||
        (hasConfig && (saved?.server?.root_api_key !== key ||
          saved?.storage?.workspace !== "/var/lib/openviking" ||
          saved?.embedding?.dense?.model !== models.embedding || saved?.vlm?.model !== `ollama/${models.vlm}`))) {
      throw new Error("Docker provider configuration differs from the supported local setup; refusing to overwrite it.");
    }
    if (!hasKey) fs.writeFileSync(keyFile, key, { flag: "wx", mode: 0o600 });
    if (!hasConfig) {
      saved = configuration(key, ollamaUrl);
      writeJson(configFile, saved);
    }
    if (saved.embedding.dense.api_base !== `${ollamaUrl}/v1` || saved.vlm.api_base !== ollamaUrl) {
      saved.embedding.dense.api_base = `${ollamaUrl}/v1`;
      saved.vlm.api_base = ollamaUrl;
      writeJson(configFile, saved);
    }
    const composeFile = path.join(stateDir, "compose.json");
    const configDigest = createHash("sha256").update(fs.readFileSync(configFile)).digest("hex");
    writeJson(composeFile, composeDocument({ openvikingImage, ollamaImage, configFile, gpu, externalOllama, configDigest }));
    const compose = (...args) => docker(["compose", "-p", project, "-f", composeFile, ...args]);
    compose("config", "--quiet");
    if (!externalOllama) {
      compose("up", "-d", "--wait", "--wait-timeout", "120", "ollama");
      for (const model of Object.values(models)) compose("exec", "-T", "ollama", "ollama", "pull", model);
    }
    // Probe providers inside the Compose network, without publishing Ollama on the host.
    const probe = [
      "import json,sys,urllib.request",
      "def request(route,body=None):",
      " data=None if body is None else json.dumps(body).encode()",
      " return json.load(urllib.request.urlopen(urllib.request.Request(sys.argv[1]+'/api/'+route,data=data,headers={'Content-Type':'application/json'}),timeout=600))",
      `embedding=request('embed',{'model':'${models.embedding}','input':'Kafka context readiness','keep_alive':0})`,
      "assert len(embedding['embeddings'][0]) == 1024, 'Embedding dimension mismatch'",
      `vlm=request('generate',{'model':'${models.vlm}','prompt':'Reply with OK','stream':False,'think':False,'keep_alive':0,'options':{'num_ctx':16384,'num_predict':16}})`,
      "assert vlm.get('response'), 'VLM returned no text'",
      "print(json.dumps(request('tags')))",
    ].join("\n");
    console.log("Checking embedding and VLM inside Docker (up to 10 minutes per model on CPU)...");
    const tags = JSON.parse(docker(["compose", "-p", project, "-f", composeFile,
      "run", "--rm", "-T", "--no-deps", "--entrypoint", "python", "openviking", "-c", probe, ollamaUrl], { capture: true, timeout: 1250000 }));
    console.log("Embedding and VLM requests passed.");
    compose("up", "-d", "openviking");
    const client = new OpenVikingClient(undefined, fs.readFileSync(keyFile, "utf8").trim());
    const deadline = Date.now() + 600000;
    let ready = false;
    let lastError;
    let nextNotice = 0;
    while (Date.now() < deadline) {
      try { await client.ready(version); ready = true; break; }
      catch (error) {
        lastError = error.message;
        if (Date.now() >= nextNotice) { console.log(`Waiting for OpenViking: ${lastError}`); nextNotice = Date.now() + 30000; }
        await new Promise((resolve) => setTimeout(resolve, 3000));
      }
    }
    if (!ready) throw new Error(`OpenViking semantic readiness timed out (${lastError}). Use docker compose -f "${composeFile}" logs openviking.`);
    await provisionAccount(stateDir, client);
    writeJson(runtimeFile, { schemaVersion: 2, backend: "docker", version, project,
      image: openvikingImage, sourceImage, ollamaImage, ollamaUrl,
      models: tags.models.filter(({ name }) => Object.values(models).includes(name)).map(({ name, digest }) => ({ name, digest })) });
    fs.unlinkSync(pending);
    console.log(`OpenViking ${version} and Ollama are ready. Persistent volumes retained.`);
  } finally { fs.rmdirSync(lock); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const index = process.argv.indexOf("--state-dir");
  if (index < 0 || !process.argv[index + 1]) throw new Error("--state-dir is required");
  const urlIndex = process.argv.indexOf("--ollama-url");
  if (urlIndex >= 0 && (!process.argv[urlIndex + 1] || process.argv[urlIndex + 1].startsWith("--"))) throw new Error("--ollama-url requires an HTTP(S) origin");
  install({ stateDir: process.argv[index + 1], yes: process.argv.includes("--yes"), gpu: process.argv.includes("--gpu"),
    ollamaUrl: urlIndex < 0 ? process.env.KAFKA_OLLAMA_URL : process.argv[urlIndex + 1] })
    .catch((error) => { console.error(`openviking-docker: ${error.message}`); process.exitCode = 1; });
}
