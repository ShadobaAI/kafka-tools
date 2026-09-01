---
name: 1c-routing
description: Route 1C project work to the single MCP authoritative for the required fact or operation. Use for 1C tasks only; do not load for unrelated repository or tooling work.
---

# 1C Routing

One question has one primary MCP. Do not repeat an answered lookup in another MCP for reassurance.

| Need | Primary MCP |
|---|---|
| Indexed source/metadata search, structure, references, graphs, impact | read-only `code-index` |
| Live source/metadata, platform APIs, mutation, primary diagnostics, build, test, debug | assigned EDT-MCP |
| Focused BSL symbols, types, references, diagnostics | repository `bsl-ls` |
| Standards, policy, diagnostic meaning, short snippet rules | `v8std` |

Use another MCP only for a different fact outside the primary MCP's authority. If sources conflict, EDT wins for live project state and platform truth.

Bind the exact project, alias, or root from workspace instructions. Check only MCPs required by the selected route; if one is unavailable or mismatched, stop that route without substitution.

Load one narrower skill or reference only when a concrete unresolved question requires it; never preload a bundle. Do not reread content already available in context unless it changed or became insufficient. Reuse established session facts until a relevant state change or failure makes them stale.

For an explicit MCP surface/security audit only, load [references/tool-policy.md](references/tool-policy.md).
