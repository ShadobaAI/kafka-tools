---
name: 1c-code-change
description: Implement or review a scoped 1C source or metadata change through the assigned EDT-MCP. Use for mutations and change-focused review; do not use for standalone search, standards, or platform API questions.
---

# 1C Code Change

Use the assigned EDT-MCP as the only writer and primary validation source. Before design, review, or the first mutation, establish the relevant `v8std` diagnostics and patterns through `$1c-standards`; reuse sufficient evidence already in context.

1. Read the smallest live target: method before module, object fragment before object. Inspect only directly affected contracts.
2. Use `$1c-code-index` only when impact/search is required; broaden only for public contracts, shared metadata, many callers, or explicit scope.
3. Form one guarded, logically atomic EDT mutation. Never rebuild a whole module for a local change.
4. After every mutation, run focused EDT diagnostics and the specialized validation required by the changed artifact.
5. Run the smallest behavior test that proves the requested outcome.

Do not reread after an unambiguous successful write. Never suppress diagnostics. Classify each relevant finding from current evidence; keep unresolved findings visible.

Database updates, imports, deletes, `clean_project`, credentials, runtime state, and branch operations are separate authorization scopes. Never run `clean_project` after a write.
