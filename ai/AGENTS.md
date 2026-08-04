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

Before analysis or changes, identify every affected repository and read its local `AGENTS.md`. Instruction precedence is: current user instructions, local repository `AGENTS.md`, then this file.

## Bounded Navigation

The workspace and its repositories are large. Never recursively scan an entire repository or the whole workspace.

- Start from the repository README, a known path, local documentation, a bounded MCP query, or a path supplied by the user.
- Request only required objects, methods, sections, files, or line ranges and set narrow result limits.
- Do not load a complete large module or file when a smaller fragment is sufficient.
- If the relevant location is unknown, ask the user for a directory or file instead of discovering it through a broad scan.

## Repository Scope

- Change multiple repositories only when the user explicitly defines multi-repository scope or an approved SDD lists every affected repository.
- Otherwise, limit changes to the current repository and report required dependent work separately.
- Preserve unrelated user changes.
- Do not use destructive Git or filesystem operations without explicit authorization.

## 1C MCP Routing

| Scope | Editing and current state | Additional navigation |
|---|---|---|
| `adapter/adapter` | `kfk_edt` | `code-metadata-mcp`, `graph-metadata-mcp` |
| `adapter/base` | `kfk_edt` | `kfk_edt` only |
| `adapter/examples` | `kfk_edt` | `kfk_edt` only |
| `conversion/KFK` | `conv_edt` | `conv_edt` only |
| `tests/unit/unit` | `kfk-unit-edt` | `kfk-unit-edt` only |

- Use `code-metadata-mcp` and `graph-metadata-mcp` only to navigate and analyze impact in `adapter/adapter`. Current information and all edits come from `kfk_edt`.
- Use the assigned EDT MCP for every 1C change under `src/**`.
- If the assigned EDT MCP is unavailable, report an error and stop the 1C edit.
- Never patch `.bsl`, `.mdo`, `.form`, `.rights`, XDTO, or any other 1C file under `src/**` directly as text.
- Do not use destructive EDT operations for analysis.
- Use available MCP services when they apply; do not route a project through another project's MCP.

## 1C Development and Validation

- Use `SyntaxCheckServer` to validate changed BSL code.
- Use `HelpSearchServer` for 1C syntax and platform API guidance.
- Use `v8std` as the baseline standard for code, methods, identifiers, procedures, functions, variables, and metadata objects.
- Within valid `v8std` alternatives, preserve the established project source style.

After a 1C change:

1. Run focused diagnostics through the assigned EDT MCP.
2. Validate changed BSL with `SyntaxCheckServer`.
3. Run focused `v8std` checks.
4. Run relevant YAxUnit or UI tests when they cover the change and the required environment is available.

EDT diagnostics can contain false positives. If a diagnostic remains after one focused correction iteration, stop and ask the user how to handle it. Do not repeatedly modify code to silence it.

## Editing Non-1C Files

- Edit non-1C files directly only within task scope.
- Preserve UTF-8, existing style, naming, interfaces, line endings, and operational defaults.
- Do not manually edit generated release artifacts, generated reports, `*.cf`, `*.cfe`, archives, runtime data, or generated project output.
- Do not invent build or test commands. Use commands documented by README, CI, or existing scripts.

## SDD and ADR Workflow

Write all SDD documents in Russian. Preserve technical identifiers, commands, and paths.

An approved SDD is required before implementing:

- a non-trivial behavior change;
- a public API change;
- a data-schema change;
- a multi-repository change.

An agent may create a `draft` SDD but must not implement it before explicit user approval. No additional confirmation is required for an already approved SDD. Use `tasks/sdd`; if it is missing, report a workspace-layout error instead of inventing another canonical location.

Routine local bug fixes, focused tests, documentation-only changes, and tooling corrections need no SDD unless they change a listed contract. Create an ADR only for a durable architecture decision or component-boundary change; store it under `tasks/adr`.

## Documentation and Completion

- Update the owning repository README or documentation with changes to public interfaces, configuration, deployment, constraints, commands, or user-visible behavior.
- Do not update product documentation for internal refactoring with no behavior change.
- Record actual implementation results, executed checks, unresolved verification, and deviations in the approved SDD.
- Update an ADR only when its accepted decision changes.
- Report every check executed, its result, and every relevant check that could not run with the reason.

## Network, Secrets, and Destructive Operations

The download limit applies to every artifact fetched from the global internet, including direct files, package-manager dependencies, release artifacts, base images, and container layers.

- If an artifact is larger than 100 MB or its size cannot be established before download, do not start it.
- Ask the user to provide the artifact locally or explicitly authorize the download.
- Locally cached files, dependencies, and images may be used.
- Do not read, expose, or commit secrets, tokens, credentials, passwords, `.env` contents, or personal configuration.
- Destructive operations affecting files, volumes, databases, caches, services, remote state, or generated history require explicit user authorization.
