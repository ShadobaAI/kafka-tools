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

- Use the assigned EDT-MCP as the source of truth for the current EDT project state, 1C source and metadata, platform-aware navigation, mutations, and EDT diagnostics.
- Perform every change to 1C artifacts under `src/**` through the assigned EDT-MCP. Never text-patch `.bsl`, `.mdo`, `.form`, `.rights`, XDTO, or other 1C model files.
- If the assigned server or project is unavailable, report the failure and stop the 1C edit; never substitute another workspace.
- After a 1C change, run focused EDT diagnostics for the affected objects. Run additional analyzers or tests only when required by the local repository instructions or the task.
- Activate EDT, v8std, and BSL LS skills independently according to the concrete need; a generic 1C task does not require all of them.

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
- Do not start an internet download larger than 100 MB, or one whose size cannot be established, without explicit authorization. Locally cached artifacts may be used.
