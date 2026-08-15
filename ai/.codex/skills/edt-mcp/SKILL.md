---
name: edt-mcp
description: Work with the live 1C:Enterprise project model through EDT-MCP. Use when a task needs 1C source or semantic navigation, metadata, forms, project-aware source reading or mutation, EDT diagnostics, query validation, tests, or EDT-dependent platform information. Do not activate for a standalone 1C standards lookup that does not require project state.
---

# EDT MCP

Use the EDT-MCP assigned by workspace instructions as the source of truth for the current project state, 1C source and metadata, mutations, and EDT diagnostics. Never substitute another project or filesystem copies of `src/**`.

## Establish only missing context

- Reuse a server and project already established in the current task.
- Check server status when availability is unknown or a call fails. List projects only when the target project is ambiguous.
- Start with currently exposed core tools. Enable only an additional toolset required by the task.
- If a stable required toolset ID is known, enable it directly. Use `list_toolsets` only when the set is unknown, the server/version changed, the capability is absent, or there is real ambiguity. Refresh the tool list only when the client requires it after enablement.
- Use `get_tool_guide` only for unclear parameters, non-trivial preconditions, a failed call caused by parameters, or a rare/risky operation. A sufficient schema needs no guide.

## Navigate narrowly

| Known state | Next action |
|---|---|
| Method is known | Read that method |
| Module is known, method is not | Inspect module structure or run a targeted search |
| Location is unknown | Run a bounded project search |
| A fragment is insufficient | Read the necessary module range; read the whole module only as a last resort |

Use semantic references, metadata details, content assist, platform documentation, query validation, or diagnostics only when they answer a concrete task question. Do not run several discovery methods for the same fact.

## Change and verify

Use the shortest safe path:

```text
read affected current source or metadata
→ mutate through EDT
→ run focused diagnostics for affected objects
→ inspect remaining relevant findings
```

- Prefer narrow semantic mutations and a supported lost-update guard. Avoid full-module replacement or syntax-check bypass unless required and justified.
- Do not re-read merely to confirm a successful mutation result. Re-read when validation found a problem, the mutation may rewrite source automatically, the next operation needs updated state, or concurrent/stale-state risk exists.
- Validate changed queries and run relevant documented tests only when affected. Do not run routine project-wide cleanup or scans.
- Activate v8std or BSL LS independently only when the task or repository policy requires them.
- After one focused correction for an ambiguous diagnostic, stop the retry loop and report the remaining finding according to workspace policy.

For destructive, irreversible, or direction-sensitive operations, inspect the exact target, read the guide when needed, use preview if supported, and obtain required authorization. After timeout or interruption, inspect operation state before retrying.

Report changed logical objects, focused EDT checks and tests, relevant findings, and any verification gap; do not claim project-wide validity from scoped checks.
