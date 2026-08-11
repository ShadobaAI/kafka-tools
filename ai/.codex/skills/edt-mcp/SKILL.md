---
name: edt-mcp
description: Develop, inspect, refactor, diagnose, and test 1C:Enterprise projects through EDT-MCP. Use for any task involving 1C source or metadata in an EDT workspace, including BSL/SDBL navigation and edits, metadata or form changes, platform API lookup, query validation, EDT diagnostics, YAxUnit, debugging, or implementation verification. Also use when repository rules require EDT-MCP instead of direct text edits under src/**.
---

# EDT MCP

Treat the selected EDT-MCP as the source of truth for the live 1C model. Never assume a server name, port, plugin version, tool set, or project layout is universal.

## Establish the correct context

1. Read workspace and repository `AGENTS.md`, then the affected component documentation.
2. Identify exactly one target repository, EDT project, and MCP server. Follow repository routing; never substitute another reachable workspace.
3. Check `get_server_status` when available and confirm the project with `list_projects`. Stop 1C edits if the required server or project is unavailable.
4. Call `list_toolsets`. If progressive disclosure is on, enable only required groups with `enable_toolset`, then refresh the tool list. Otherwise do not toggle toolsets.
5. Call `get_tool_guide` before any mutating, destructive, uncommon, or unclear operation. Current tool schemas and guides override static skill details.

## Research before editing

Collect the smallest sufficient context:

- module shape with `get_module_structure`; implementation with `read_method_source` or a bounded `read_module_source` range;
- metadata with `get_metadata_details` and narrowly filtered object/subsystem queries;
- dependencies with call hierarchy, outgoing structures, references, definitions, and bounded code search;
- inferred types and valid calls with `get_symbol_info`, `get_content_assist`, and `get_platform_documentation`;
- a scoped diagnostic baseline with `get_project_errors` or `get_problem_summary`.

Avoid whole modules, broad searches, and architecture inferred only from names or comments.

## Design for project quality

1. Find 2–3 correct nearby examples matching responsibility, layer, and execution context.
2. Extract stable conventions: logic placement, client/server boundaries, exported APIs, errors, transactions, permissions, queries, localization, and tests. Do not copy an existing defect or obsolete pattern.
3. For every unfamiliar, ambiguous, or version-sensitive platform API, call `get_platform_documentation` in the target project context and requested language when supported. Confirm the type, method, property, constructor, or built-in function with contextual `get_content_assist` and, when useful, `get_symbol_info`. Never rely on memory when platform docs are available.
4. Validate queries with `validate_query` in the target project and correct DCS mode.
5. Use `$v8std-mcp` before editing for applicable constraints and patterns, then after editing for diagnostics and code review. Open the full standard page; lexical retrieval is not proof.
6. Choose the smallest change preserving architecture and contracts. Follow required SDD/ADR workflow before contract or architecture changes.

Keep evidence roles distinct: platform docs define API contracts; v8std defines standards and patterns; correct project examples define local architecture and style. Prefer correctness and requirements, then mandatory standards, compatibility and architecture, then style.

## Edit safely

- Edit 1C model files in an EDT workspace only through the assigned EDT-MCP. Never text-patch `.bsl`, `.mdo`, `.form`, `.rights`, XDTO, or other `src/**` model files. If no safe MCP operation exists, stop and report the limitation.
- Re-read the target immediately before writing. Prefer `write_module_source` with `searchReplace` and the latest `expectedHash` or supported lost-update guard.
- Avoid full-module replacement, `overwrite`, and `skipSyntaxCheck` unless technically required and justified.
- Use semantic create/modify/rename/adopt tools for metadata so EDT updates references and persists the model. Re-read the changed object.
- Preserve public signatures, types, compatibility mode, extension boundaries, and client/server separation unless the requirement says otherwise.
- Never add silent fallbacks or weaken permissions, validation, transactions, consistency, or error handling.
- Apply one logical change per iteration so diagnostics remain attributable.

## Run the quality loop

After each logical change:

1. Re-read the changed method, module, or metadata object.
2. Run `revalidate_objects` for exact FQNs. Do not use `clean_project` routinely; it performs a full disk → model refresh and revalidation.
3. Read scoped project/object diagnostics and compare them with the baseline. Separate new from pre-existing findings.
4. Re-check used platform APIs with `get_platform_documentation`; re-run `validate_query` for changed queries.
5. Resolve EDT/v8-code-style codes through `$v8std-mcp`, open linked pages, and verify applicability.
6. Make one focused correction for a confirmed issue. If a likely false positive remains, show evidence and follow repository escalation rules instead of repeatedly rewriting code.
7. Run the smallest relevant documented YAxUnit/UI test, then broader checks only when impact warrants it. Never invent launch configurations, suites, or commands.
8. Inspect the target repository diff for unrelated changes.

Zero diagnostics does not prove correct behavior; also verify requirements, data flow, and relevant tests when available.

## Guard risky operations

- Treat metadata/project/infobase deletion, database update, full synchronization, overwriting import/export, branch switching, and forced termination as high risk.
- Read the tool guide, use preview when supported, identify the exact target, and obtain required confirmation before irreversible work.
- Preserve synchronization direction: `clean_project` is disk → model; `resync_to_disk` is model → disk. Do not use either to guess at an unexplained mismatch.
- After interruption or timeout, inspect status/history before retrying; the EDT job may still run in the background.
- Never reroute work to another EDT-MCP when the assigned server is unavailable.

## Report evidence

Report the EDT project and logical objects changed; the design decision and project fit; platform documentation/API checks; EDT diagnostics; v8std page or diagnostic IDs; query checks; tests; new, pre-existing, or inapplicable findings; and anything unverified with its reason. Never claim behavior or compliance that was not actually checked.
