---
name: 1c-code-change
description: Implement or review a scoped 1C source or metadata change through the assigned EDT-MCP. Use for mutations and change-focused review; do not use for standalone search, standards, or platform API questions.
---

# 1C Code Change

Use the assigned EDT-MCP as the only writer and primary validation source.

## Knowledge gate

Before project inspection or mutation, classify the request by operation (`create`, `modify`, `bugfix`, `refactor`, `review`), artifact, change shape (`local-body`, `new-method`, `new-export`, `new-object`, `restructure`), and standards-sensitive mechanisms. Resolve every matching known ID below, load it once with `v8std_get_page`, and retain the loaded requirements for final validation. Use `$1c-standards` search only for a standards question that remains unresolved; a simple local body change may require no v8std page.

| Scenario or mechanism | Required IDs |
|---|---|
| Create or materially restructure a module; add a method | `std455` |
| Create a common module | `std455`, `std469` |
| Change common-module properties or execution context | `std469` |
| Privileged mode | `std485` |
| Full-access common module | `std469`, `std488` |
| Query uses `ВЫБРАТЬ РАЗРЕШЕННЫЕ` | `std415`, `std437`, `std444` |
| Localized user-facing text | applicable `std761`, `std762`, `std765` |

For a new export, also inspect the public contract and affected callers; do not infer that impact from standards alone. Add requirements implied by the actual target even when the user did not name the mechanism explicitly.

1. Read the smallest live target: method before module, object fragment before object. Inspect only directly affected contracts.
2. Use `$1c-code-index` only when impact/search is required; broaden only for public contracts, shared metadata, many callers, or explicit scope.
3. Form one guarded, logically atomic EDT mutation. Never rebuild a whole module for a local change.
4. After every mutation, run focused EDT diagnostics and the specialized validation required by the changed artifact.
5. Validate against the same loaded requirements without searching for or rereading them, then run the smallest behavior test that proves the requested outcome.

Do not reread after an unambiguous successful write. Never suppress diagnostics. Classify each relevant finding from current evidence; keep unresolved findings visible.

Database updates, imports, deletes, `clean_project`, credentials, runtime state, and branch operations are separate authorization scopes. Never run `clean_project` after a write.
