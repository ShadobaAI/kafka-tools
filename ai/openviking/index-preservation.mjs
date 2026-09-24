import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { documentUri, inventory, loadManifest, plan } from "./git-sync.mjs";

const directory = path.dirname(fileURLToPath(import.meta.url));
// v0.4.21 changes Docker's default cwd; our storage.workspace is absolute.
// Review each later release before adding another pair:
// https://github.com/volcengine/OpenViking/releases/tag/v0.4.21
const compatibleUpgrades = new Set(["0.4.20->0.4.21"]);

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sourceDigest() {
  return sha256(Buffer.concat([
    fs.readFileSync(path.join(directory, "sources.json")),
    fs.readFileSync(path.join(directory, "version.json")),
  ]));
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
}

function writeJson(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx", mode: 0o600 });
  fs.renameSync(temporary, file);
}

export function checkModels(before, after) {
  const digests = (items) => new Map((items ?? []).map(({ name, digest }) => [name, digest]));
  const oldModels = digests(before);
  const newModels = digests(after);
  for (const name of ["qwen3-embedding:0.6b", "qwen3.5:4b"]) {
    if (!oldModels.get(name) || oldModels.get(name) !== newModels.get(name)) {
      throw new Error(`OpenViking model ${name} changed or has no verified digest; existing index cannot be reused.`);
    }
  }
}

async function verifyIndex({ manifest, state, client, consistencyClient }) {
  const report = await consistencyClient.request("POST", "/api/v1/system/consistency", { uri: manifest.namespace });
  if (report.status !== "ok" || report.result?.ok !== true ||
      !Number.isInteger(report.result.expected_count) || report.result.expected_count < 1 ||
      report.result.missing_record_count !== 0 || report.result.missing_records_truncated === true) {
    throw new Error("OpenViking filesystem/vector index consistency is not confirmed; existing index was not changed.");
  }
  for (const [repo, item] of Object.entries(state.repositories)) {
    for (const file of Object.keys(item.files)) {
      if (!await client.exists(documentUri(manifest.namespace, repo, file))) {
        throw new Error(`OpenViking source is missing: ${repo}:${file}. Existing index was not changed.`);
      }
    }
  }
}

export function compatibleIndexUpgrade(from, to) {
  return from === to || compatibleUpgrades.has(`${from}->${to}`);
}

export async function prepareIndexReuse({ stateDir, workspaceRoot, targetVersion, ollamaUrl,
                                          client, consistencyClient }) {
  const stateFile = path.join(stateDir, "state.json");
  const runtimeFile = path.join(stateDir, "runtime.json");
  const pendingFile = path.join(stateDir, "docker-install.pending");
  const journalFile = path.join(stateDir, "index-update.json");
  if (!fs.existsSync(runtimeFile)) return null;
  if (!fs.existsSync(stateFile) || fs.existsSync(path.join(stateDir, "dirty"))) {
    throw new Error("Existing OpenViking index state is missing or dirty; update stopped without reindexing.");
  }
  const state = readJson(stateFile);
  let journal = fs.existsSync(journalFile) ? readJson(journalFile) : null;
  if (journal && !fs.existsSync(pendingFile)) {
    const completed = loadManifest(undefined, runtimeFile);
    const unchanged = state.runtimeVersion === journal.oldVersion &&
      completed.runtime.version === journal.oldVersion &&
      state.manifestDigest === journal.oldDigest &&
      sha256(fs.readFileSync(stateFile)) === journal.oldStateSha256;
    const updated = state.runtimeVersion === journal.targetVersion &&
      state.runtimeVersion === completed.runtime.version &&
      state.manifestDigest === completed.digest;
    if (journal.sourceDigest !== sourceDigest() || (!unchanged && !updated)) {
      throw new Error("Interrupted OpenViking update has an unverified completion journal; manual recovery is required.");
    }
    fs.unlinkSync(journalFile);
    journal = null;
  }
  if (fs.existsSync(pendingFile) !== Boolean(journal)) {
    throw new Error("Interrupted OpenViking setup has no matching update journal; manual recovery is required.");
  }
  const { manifest, runtime, digest } = loadManifest(undefined, runtimeFile, { allowPending: Boolean(journal) });
  if (runtime.ollamaUrl !== ollamaUrl) {
    throw new Error("Ollama endpoint changed; existing OpenViking index cannot be reused.");
  }
  const oldVersion = journal?.oldVersion ?? runtime.version;
  if (!compatibleIndexUpgrade(oldVersion, targetVersion)) {
    throw new Error(`OpenViking ${oldVersion} -> ${targetVersion} has no approved index compatibility; update stopped before changing the database.`);
  }
  if (journal) {
    if (journal.targetVersion !== targetVersion || journal.sourceDigest !== sourceDigest() ||
        ![oldVersion, targetVersion].includes(runtime.version) ||
        (state.runtimeVersion === oldVersion && sha256(fs.readFileSync(stateFile)) !== journal.oldStateSha256)) {
      throw new Error("Interrupted OpenViking update state changed; manual recovery is required.");
    }
  } else if (state.schemaVersion !== 1 || state.manifestDigest !== digest ||
             state.runtimeVersion !== runtime.version) {
    throw new Error("Existing OpenViking index does not match saved runtime metadata; update stopped without reindexing.");
  }
  const baselineDigest = journal?.oldDigest ?? digest;
  const changes = plan(inventory(workspaceRoot, manifest), state, baselineDigest, oldVersion);
  if (changes.rebuild && state.runtimeVersion === oldVersion) {
    throw new Error("Existing OpenViking Git state requires a rebuild; update stopped without reindexing.");
  }
  if (!journal) {
    await client.ready(oldVersion);
    await verifyIndex({ manifest, state, client, consistencyClient });
  }
  return { manifest, state, oldVersion, oldDigest: baselineDigest, sourceDigest: sourceDigest(),
    oldStateSha256: journal?.oldStateSha256 ?? sha256(fs.readFileSync(stateFile)),
    oldModels: journal?.oldModels ?? runtime.models, targetVersion, resumed: Boolean(journal) };
}

export function beginIndexReuse(stateDir, proof) {
  const journalFile = path.join(stateDir, "index-update.json");
  if (!proof.resumed) writeJson(journalFile, {
    oldVersion: proof.oldVersion, oldDigest: proof.oldDigest, oldStateSha256: proof.oldStateSha256,
    sourceDigest: proof.sourceDigest, oldModels: proof.oldModels, targetVersion: proof.targetVersion,
  });
}

export async function finishIndexReuse({ stateDir, proof, models, client, consistencyClient }) {
  checkModels(proof.oldModels, models);
  const runtimeFile = path.join(stateDir, "runtime.json");
  const stateFile = path.join(stateDir, "state.json");
  const { manifest, runtime, digest } = loadManifest(undefined, runtimeFile, { allowPending: true });
  if (runtime.version !== proof.targetVersion || sourceDigest() !== proof.sourceDigest) {
    throw new Error("OpenViking runtime or source policy changed during update; existing index was not changed.");
  }
  await verifyIndex({ manifest, state: proof.state, client, consistencyClient });
  const current = readJson(stateFile);
  if (current.runtimeVersion === proof.oldVersion && current.manifestDigest === proof.oldDigest) {
    if (sha256(fs.readFileSync(stateFile)) !== proof.oldStateSha256) {
      throw new Error("OpenViking sync state changed during update; existing index was not changed.");
    }
    writeJson(stateFile, { ...current, manifestDigest: digest, runtimeVersion: runtime.version });
  } else if (current.runtimeVersion !== runtime.version || current.manifestDigest !== digest) {
    throw new Error("OpenViking sync state has an unexpected version; existing index was not changed.");
  }
}

export function completeIndexReuse(stateDir) {
  const journalFile = path.join(stateDir, "index-update.json");
  if (fs.existsSync(journalFile)) fs.unlinkSync(journalFile);
}
