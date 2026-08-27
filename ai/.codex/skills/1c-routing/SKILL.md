---
name: 1c-routing
description: Route work with a concrete 1C:Enterprise project or a general question about 1C between the assigned EDT-MCP, read-only code-index, optional BSL LS, and v8std. Use only for 1C project work or general 1C questions; do not use for unrelated workspace, tooling, Git, documentation, or engineering requests merely because they occur in a repository containing 1C.
---

# 1C Routing

Choose the source by the kind of fact or operation, not by which tool looks shorter.

| Need | Primary route | Supplementary route |
|---|---|---|
| Read-only project information, source/metadata search, or analysis where slight index staleness is acceptable | read-only code-index | EDT only when authoritative live confirmation is required |
| Authoritative live source/metadata state, semantic navigation unavailable in the index, or platform fact | assigned EDT-MCP | code-index/BSL LS evidence when useful |
| Any persistent 1C mutation | assigned EDT-MCP only | none |
| Primary validation/build/test/debug | assigned EDT-MCP | focused BSL LS diagnostics when configured |
| Focused BSL symbols, references, types, diagnostics | repository BSL LS | EDT for authoritative confirmation |
| General or corporate development policy | v8std | EDT project evidence when applicable |

## Invariants

- Never list, search, read, parse, patch, create, move, rename, or delete files in configuration/extension `src/**` through filesystem, shell, generic file, or patch tools.
- Never use code-index daemon/CLI mutation commands through MCP. Its exposed MCP surface is an explicit read-only allowlist; the daemon may write only `.code-index/` data in configured repository roots and coordination/runtime files in `CODE_INDEX_HOME`.
- Use BSL LS only through the repository-local MCP and only for focused read-only diagnostics or semantic navigation.
- Use the configured MCP named `v8std` for standards and snippet analysis. Endpoint selection belongs to the user's MCP configuration; do not switch endpoints or reject content based on agent-side source classification.
- Check availability only for MCPs required by the selected route. If a required assigned EDT-MCP, `code-index`, `v8std`, or repository BSL LS endpoint, project, alias, or root is unavailable, report an explicit error and stop the MCP-dependent work. Do not substitute another MCP, workspace, filesystem/shell access, copied source, or model memory.
- If EDT and an index/analyzer disagree about project state, EDT wins. Check `code-index` health and index freshness; use EDT `resync_to_disk` only when model-to-disk reconciliation is actually needed.
- Run focused EDT diagnostics after every 1C mutation. Do not disable, suppress, filter out, or hide them.
- Treat an EDT finding as a confirmed defect only after checking it against the current source and metadata context. Leave it unfixed only when evidence supports a false-positive classification; otherwise keep it unresolved and report the finding with its evidence.
- Progressive disclosure is context control, not authorization. Keep EDT `git` and `ask_workmate` disabled.

## Route the task

- For a code or metadata change, use `$1c-code-change`.
- For platform APIs, built-in types, methods, properties, or version compatibility, use `$1c-platform-docs`.
- For standards, diagnostic meaning, patterns, or architecture policy, use `$1c-standards`.
- For read-only project information, search, discovery, structure, graph, references, or impact analysis where slight index staleness is acceptable, use `$1c-code-index` for both narrow and broad questions. Confirm through EDT only when the conclusion requires authoritative live state.
- For focused BSL diagnostics or a specific symbol/reference/type question in a configured repository, use `$bsl-ls-mcp`.
- Use EDT for a read-only lookup only when the task requires authoritative live state, platform truth, primary diagnostics, mutation preparation, or a fact that code-index cannot represent.

Establish server status and project identity only when not already known. Enable only the EDT toolset needed for the current decision. Use `get_tool_guide` for unclear or version-sensitive tool semantics rather than inventing arguments.

Read [references/tool-policy.md](references/tool-policy.md) only when exact code-index/BSL LS allowlist membership, EDT high-risk classification, or update auditing is relevant.
