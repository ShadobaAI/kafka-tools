# Git-backed OpenViking sources

`sources.json` lists only document paths within the fixed Kafka repositories. Entries are evaluated against tracked files at each repository's committed `HEAD`; dirty and untracked files are never source material. The `viking://resources/kafka-git` namespace is a disposable local read-model, not canonical storage. It excludes protected `src/**`, Codex skills, and the v8std corpus.

`version.json` defines latest-stable against PyPI and the official GHCR image. Docker Compose is the only runtime; Windows Python is not used. Configuration and API credentials remain outside Git.

Every full installation pulls the official image, records its digest and verifies its package version against latest-stable PyPI metadata. A mismatch fails setup. Semantic readiness requires embedding, VLM, vector DB and AGFS filesystem checks. Health/readiness requests have a 15-second limit. Retrieval quality and completed ingestion require separate acceptance.

The installer pulls the release tag `v<resolved-version>` from GHCR. If Docker
cannot pull from GHCR, it reads and hashes the official release index via the
GHCR API, selects the Linux platform digest and pulls that exact digest from
`docker.io/openviking/openviking`. The mirror tag is never trusted. Both the
source GHCR reference and actual image reference are recorded; missing official
metadata, ambiguous architecture or a digest mismatch blocks this fallback.

`git-sync.mjs` reads selected blobs from committed Git trees, reconciles them to the selected local server version recorded in derived state, and stores revision state outside Git. A failed or partial sync leaves a dirty marker and forces a later rebuild. `read-only-mcp.mjs` exposes exactly `find`, `search`, `read`, `list`, and `tree`, with pre-use reconciliation and bounded results. Static and mock tests cover this behavior.

Each document write waits up to 600 seconds for semantic/vector processing, with
a 630-second HTTP deadline covering the response body. Long writes use Node HTTP
so the native fetch response-header timeout does not cut ingestion short.
Write failures identify the document and are not retried automatically: a timeout
does not prove that the server stopped processing. A failed installation remains
incomplete; verify that server processing has finished before rerunning setup,
which rebuilds dirty Git state. Health/readiness limits remain 15 seconds.

`install-hooks.mjs` prepares `post-checkout`, `post-merge`, and `post-rewrite`
wrappers for all nine Kafka-owned repositories declared in `hookRepositories`.
The upstream `tests/unit/yaxunit` checkout is explicitly excluded. Installation performs a global
preflight, uses a cross-process lock, is byte-idempotent, and preserves an existing
hook beside the wrapper as `<hook>.kafka-user`; a collision fails before mutation.
The wrapper keeps the foreign hook's exit status and dispatches hidden asynchronous
reconciliation afterwards. Hook failure never makes stale context ready: every MCP
read still performs synchronous pre-use reconciliation. OpenViking state is rejected
inside the Kafka workspace. Full `install.cmd` invokes this manager only after runtime
readiness, initial sync, and MCP smoke checks succeed.

Full `install.cmd` invokes `docker-runtime.mjs`. Prerequisites: Docker Desktop
with Linux containers, Compose, free disk/RAM and optional NVIDIA GPU.
The bootstrap offers qwen3-embedding:0.6b (~0.64 GB) and qwen3.5:4b (~3.4 GB),
shows Docker RAM and requests confirmation before downloads. CPU is the default;
`-OpenVikingGpu` enables GPU reservation. Other containers share the same RAM budget.
Models are loaded sequentially. No nested Ollama installer or cloud wizard runs.

For a GPU host outside the VM, pass its reachable Ollama origin:

See the [Windows host + Hyper-V VM installation guide (Russian)](INSTALL-WINDOWS-HYPERV.md)
for host GPU setup, model downloads, firewall rules and troubleshooting.

```powershell
.\tools\ai\install.cmd -OllamaUrl http://gpu-host:11434
```

Replace `gpu-host` with the host name or IP reachable from both Windows and Docker.
`KAFKA_OLLAMA_URL` is the equivalent environment setting. This mode starts only
OpenViking locally: no Ollama image, container, model volume or model downloads
are created in the VM. Both named models must already be installed on the remote
host. The bootstrap checks its model inventory and makes embedding/generation
requests from the OpenViking container before reporting readiness. Do not combine
this option with `-OpenVikingGpu`; GPU belongs to the remote host.
The endpoint is saved in Docker runtime state and reused on subsequent runs.
Only provider URLs are updated when switching endpoints; credentials are retained.
Restrict the remote Ollama port to the VM in the host firewall. No documents are
sent to any endpoint until it is explicitly configured.

In managed-local mode, Compose project `kafka-openviking` owns separate `openviking-data` and `ollama-models`
volumes. Data is stored at `/var/lib/openviking`, models at `/root/.ollama`.
The host API binds only `127.0.0.1:1933`; Ollama is reachable as `ollama:11434`
inside the Compose network. The bundled bot is not launched. Neither repositories
nor the Docker socket are mounted into services.

`<CodexHome>/openviking-docker` contains generated `compose.json`, `ov.conf`,
`api-key`, `tenant-api-key` and Docker-only `runtime.json`. Do not print or commit configuration or
keys. The root `api-key` is used only for server administration. Setup creates the
`kafka` account with the `git-sync` admin user and verifies data access before
reporting readiness. MCP, doctor and sync use `tenant-api-key`; OpenViking rejects
root keys on data APIs. Repeat setup preserves both keys. If only one of `api-key`
and `ov.conf` remains after an interrupted setup, repeat setup restores the missing
file using the surviving root key. Existing configuration is validated before
recovery; empty keys, conflicting keys and unsupported configuration stop setup
without replacing credentials. If a Kafka account exists
but its local tenant key is missing, restore that key; setup does not rotate it or
delete account data automatically. Git reconciliation prints progress per document.
`-OpenVikingStateDir` selects an
external directory. Old venv metadata is rejected; there is no migration or native
mode. Old Windows environments are not deleted. Failed setup retains volumes;
it never runs `down -v`, prune or automatic data rollback.

For an existing index, the installer checks saved Git state, every document,
and filesystem/vector consistency before changing the image. A compatible
0.4.20 to 0.4.21 update keeps the same Docker volume and index; unchanged
documents are not re-embedded. Only changed committed Git documents are
synchronized. Other version pairs, changed model digests or provider settings,
missing state, and failed consistency checks stop the update without deleting
or rebuilding the index. Pending updates block context reads until recovery.
The first installation still builds the initial index.

Diagnostics (substitute your state directory):

```powershell
docker compose -f <state-dir>/compose.json ps
docker compose -f <state-dir>/compose.json logs --tail 100 openviking ollama
node tools/ai/openviking/probe.mjs --state-dir <state-dir>
```

Component checks from the Kafka root:

```powershell
node tools/ai/tests/test-openviking-docker.mjs
node tools/ai/tests/test-openviking-manifest.mjs
node tools/ai/tests/test-openviking-sync.mjs
node tools/ai/tests/test-openviking-mcp.mjs
```

Live acceptance is recorded in `tasks/sdd/spec-0012-docker-runtime-addendum.md`.
Static checks alone do not prove successful provider setup or deployment.

After installation, `tools\ai\update-openviking.cmd` can be run from any Kafka
repository or the workspace root to update the derived state incrementally.
The launcher resolves `--state-dir` from the installed shared `kafka-openviking`
MCP using Codex CLI and rejects a mismatching `--workspace-root`. An absolute
`KAFKA_OPENVIKING_STATE_DIR` explicitly overrides this lookup. The console waits
for a key afterwards unless `KAFKA_AI_NO_PAUSE=1` is set.
The command verifies the selected local server version/readiness, then writes only
new or changed committed Git blobs and deletes removed documents. Unchanged documents
are checked for existence but are not re-embedded. It prints the planned write/delete
counts before processing. Use `update-openviking.cmd --rebuild` explicitly to recreate
the entire Kafka Git namespace. Missing, dirty or incompatible state makes the default
launcher stop before changing the index and request this explicit rebuild.
It does **not** install or restart OpenViking. Installer, hooks, and MCP reads
also stop when a full rebuild would be required; use the explicit manual
`--rebuild` operation after reviewing the reason.
