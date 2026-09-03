---
name: 1c-routing
description: Route 1C project work to the authoritative MCP and a task-specific skill. Do not load for unrelated Git, documentation or tooling work.
---

# 1C Routing

Bind the exact project, alias or root from project instructions. Check only tools needed by the selected route; unavailable or mismatched required scope stops that route without substitution.

| Unresolved need | Authority / next skill |
|---|---|
| Indexed discovery, structure, references, impact | read-only code-index / $1c-code-index |
| Live source/metadata, primary diagnostics | assigned EDT-MCP |
| Source/metadata change or change review | assigned EDT-MCP / $1c-code-change |
| Platform API/version/context | assigned EDT-MCP / $1c-platform-docs |
| Focused BSL semantics/diagnostics | repository bsl-ls / $bsl-ls-mcp |
| Design or normative analysis, standards, work policy, diagnostic meaning, snippet rules | v8std / $1c-standards |
| YAxUnit authoring, review, execution | $yaxunit-tests |

Load only the current route. Design and change review must select applicable requirements before accepting a solution; implementation must do so before writing. Reuse that selection across phases. Pure source discovery needs no normative corpus; it must not silently become a design or compliance conclusion.

One fact has one primary authority. Do not repeat sufficient evidence in another MCP. EDT owns live state/platform truth; conflicting indexed/analyzer evidence is invalid until freshness is re-established. Reuse session evidence until a relevant mutation, restart, error or contradiction invalidates it.

For an explicit MCP surface/security audit only, read [references/tool-policy.md](references/tool-policy.md).
