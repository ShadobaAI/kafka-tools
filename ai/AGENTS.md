# Kafka Adapter Workspace Instructions

## Workspace Layout

This workspace is a fixed collection of independent Git repositories under `KAFKA_PROJECTS_ROOT`. Do not assume that the workspace root is a Git repository.

| Repository | Canonical path |
|---|---|
| `kafka-adapter` | `adapter/adapter` |
| `kafka-adapter-base` | `adapter/base` |
| `kafka-adapter-examples` | `adapter/examples` |
| `kafka-adapter-conv` | `conversion/KFK` |
| `kafka-adapter-tests-reports` | `tests/reports` |
| `kafka-adapter-tests-ui` | `tests/ui` |
| `kafka-adapter-tests-unit` | `tests/unit/unit` |
| `kafka-tools` | `tools` |
| `kfk-tasks` | `tasks` |

Before work, identify every affected repository and read its local `AGENTS.md` when present; otherwise use the relevant repository README. Instruction precedence is: current user instructions, local repository instructions, then this file.

## Bounded Navigation

- Start from a user-supplied or known path, relevant local documentation, or a bounded MCP query.
- Request only the objects, methods, sections, files, or line ranges needed for the next decision.
- When the location is unknown, search within the smallest plausible repository or project scope and widen only when evidence requires it.
- Do not recursively scan an entire repository or workspace, load a large complete module when a fragment is sufficient, or run multiple discovery methods for the same question.

## Repository Boundaries

- Change multiple repositories only when the user explicitly defines that scope or an approved SDD lists every affected repository.
- Otherwise, keep changes in the target repository and report dependent work separately.
- Preserve unrelated user changes.
- Keep repository-owned MCP configuration in its owning repository; do not route a project through another project's MCP.

## 1C Routing and Source Integrity

| Scope | EDT-MCP server | Configuration owner |
|---|---|---|
| `adapter/adapter` | `kfk-edt` | `adapter/adapter/.codex/config.toml` |
| `adapter/base` | `kfk-edt` | `adapter/adapter/.codex/config.toml` |
| `adapter/examples` | `kfk-edt` | `adapter/adapter/.codex/config.toml` |
| `conversion/KFK` | `conv-edt` | `conversion/KFK/.codex/config.toml` |
| `tests/unit/unit` | `kfk-unit-edt` | `tests/unit/unit/.codex/config.toml` |

- Use `$1c-routing` only when the request concerns work with a concrete 1C project or a general question about 1C. Do not load it for unrelated repository, tooling, Git, documentation, or engineering requests merely because the workspace contains 1C.
- Use the assigned EDT-MCP as the source of truth for the live EDT model, 1C source and metadata, platform-aware navigation, every persistent mutation, and primary diagnostics.
- Never access configuration or extension source trees under `src/**` directly through filesystem, shell, generic file, or patch tools. This prohibition includes list, find, glob, grep, read, parse, write, move, rename, and delete operations.
- Access 1C project source only through the assigned EDT-MCP or explicitly allowed read-only `code-index`/BSL LS MCP tools. Perform every change through EDT-MCP; never text-patch `.bsl`, `.mdo`, `.form`, `.rights`, DCS, XDTO, or other serialized 1C model files.
- Use the shared `code-index` MCP for broad indexed discovery, structure, call/data graphs, and impact analysis. Bind the exact repository alias, check `health` when freshness is not established, and treat the index as eventually consistent supplementary evidence.
- For BSL call graphs, use `get_callers_bsl`, `get_callees_bsl`, `get_call_tree_bsl`, or `find_path_bsl`; the universal call tools expose the less precise core graph. A zero-edge result covers only indexed static calls and does not exclude dynamic string/reflection dispatch.
- Use repository-local BSL LS only for focused BSL diagnostics and semantic navigation when that MCP is explicitly configured. It does not replace EDT diagnostics, metadata, platform documentation, or tests.
- The `bsl-indexer` daemon may write only its own `.code-index/` data in configured repository roots and coordination/runtime files under managed `CODE_INDEX_HOME`; do not expose daemon/index mutation commands through MCP.
- Use the MCP named `v8std` as the primary standards/policy corpus. Its endpoint is user-owned configuration: the default is `https://ai.v8std.ru/mcp`, and the user may replace its `url` with a local endpoint. Do not apply agent-side source classification, endpoint switching, or code-transfer restrictions beyond the configured MCP.
- For platform APIs and version-specific semantics, use EDT `get_platform_documentation` with `projectName`; use content assist and EDT validation when needed.
- After every 1C mutation, run focused EDT diagnostics for the affected objects and inspect the resulting findings.
- Do not disable, suppress, filter out, or hide EDT diagnostics.
- Do not treat an EDT finding as a confirmed defect until it is verified against the current source and metadata context.
- Leave a finding unfixed only when evidence supports classifying it as a false positive; otherwise keep it unresolved. Report its code, message, location, classification, and evidence. code-index, BSL LS, platform documentation, content assist, standards, and focused tests may corroborate the classification but never replace EDT diagnostics.
- If EDT and code-index/BSL LS disagree about project state, trust EDT, inspect index/analyzer freshness, and use EDT `resync_to_disk` only when model-to-disk reconciliation is actually required. Never run `clean_project` automatically after an EDT mutation.
- Keep EDT raw `git` and `ask_workmate` disabled. Treat database updates, destructive metadata/project operations, imports, credential changes, runtime variable changes, branch switching, and evaluation as explicit-context high-risk operations.
- If the assigned server or project is unavailable, report the failure and stop the 1C edit; never substitute another workspace.
- For unknown or version-sensitive EDT tool semantics, use `get_tool_guide` instead of guessing. Enable only the EDT toolset required for the task; progressive disclosure is context control, not authorization.
- Run additional tests only when required by the local repository instructions or the changed behavior.

## Non-1C Files

- Edit non-1C files directly only within task scope; preserve UTF-8, existing style, naming, interfaces, line endings, and operational defaults.
- Do not manually edit generated release artifacts, generated reports, `*.cf`, `*.cfe`, archives, runtime data, or generated project output.
- Do not invent build or test commands. Use commands documented by the affected repository.

## SDD and ADR

Write SDD documents in Russian while preserving technical identifiers, commands, and paths.

An approved SDD is required before implementing a non-trivial behavior change, public API change, data-schema change, or multi-repository change. A draft does not authorize implementation. Store SDDs under `tasks/sdd`; if it is missing, report a workspace-layout error. Routine local bug fixes, focused tests, documentation-only changes, and tooling corrections do not require an SDD unless they change one of those contracts.

Create an ADR only for a durable architecture or component-boundary decision and store it under `tasks/adr`.

## Documentation and Completion

- Update owning documentation when a public interface, configuration, deployment rule, constraint, command, or user-visible behavior changes; do not update product documentation for internal refactoring.
- Record implementation results, checks, unresolved verification, and deviations in an approved SDD when one governs the change.
- Report checks actually run and relevant checks that could not run. Do not claim unperformed verification.

## Safety

- Do not read, expose, or commit secrets, tokens, credentials, passwords, `.env` contents, or personal configuration.
- Do not use destructive Git, filesystem, EDT, database, volume, cache, service, remote-state, or history operations without explicit authorization.
