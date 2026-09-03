---
name: 1c-code-change
description: Implement or review a scoped 1C source or metadata change through the assigned EDT-MCP. Use for mutations and change-focused review; do not use for standalone search, standards, or platform API questions.
---

# 1C Code Change

Use the assigned EDT-MCP as the only writer and primary validation source. Use the required `v8std` MCP as the only source for general 1C standards and additional work policy.

## Knowledge gate

Before mutation, classify the request by operation (`create`, `modify`, `bugfix`, `refactor`, `review`), artifact, change shape (`local-body`, `new-method`, `new-export`, `new-object`, `restructure`), and standards-sensitive mechanisms. Load every matching known ID below once with `v8std_get_page` and retain the complete pages for final validation. Use `$1c-standards` search only for a standards or corporate-policy question that remains unresolved. Do not mutate when `v8std` is unavailable, a required ID is missing, the returned body is incomplete, or the applicable requirement set remains uncertain.

| Scenario or mechanism | Required IDs |
|---|---|
| Any new or changed BSL | `corporate:work:bsl-change-policy:overview`, `corporate:work:bsl-type-transparency:overview`, `corporate:work:bsl-readability:overview`, `corporate:work:bsl-formatting:overview`, `std444` |
| Add or change a method signature or documentation | `std453`, `std640`, applicable `std641`, `std647` |
| Create or materially restructure a module; add a method | `std455` |
| Create a common module | `std455`, `std469` |
| Change common-module properties or execution context | `std469` |
| Add or change an export | `corporate:work:module-organization:overview`, `std453`, `std544` |
| Add or change a query | `corporate:work:query-conventions:overview`, `std436`, `std438`, `std725` |
| Form client/server interaction | `corporate:work:module-organization:overview`, `std487`, `std636` |
| Catch or present an error | `corporate:work:error-reporting:overview`, `std499` |
| Explicit transaction | `std783` |
| Temporary files, streams, or other resources | `std542` |
| Session or current time | `std643` |
| Predefined values | `std443`, `std697` |
| Privileged mode | `std485` |
| Full-access common module | `std469`, `std488` |
| Query uses `ВЫБРАТЬ РАЗРЕШЕННЫЕ` | `std415`, `std437`, `std444` |
| Localized or technical text | applicable `std761`, `std762`, `std764`, `std765` |

For a new export, also inspect the public contract and affected callers; do not infer that impact from standards alone. Add requirements implied by the actual target even when the user did not name the mechanism explicitly. Load known additional work policy by exact `corporate:work:*` ID; search only `collections=["corporate"]` for an unresolved policy question and reject results outside the `corporate:work` namespace.

1. Read the smallest live target: method before module, object fragment before object. Inspect only directly affected contracts.
2. Use `$1c-code-index` only when impact/search is required; broaden only for public contracts, shared metadata, many callers, or explicit scope.
3. Form one guarded, logically atomic EDT mutation. Never rebuild a whole module for a local change.
4. After every mutation, run focused EDT diagnostics and the specialized validation required by the changed artifact.
5. Validate against the same loaded requirements without searching for or rereading them, then run the smallest behavior test that proves the requested outcome.

Do not reread after an unambiguous successful write. Never suppress diagnostics. Classify each relevant finding from current evidence; keep unresolved findings visible.

Database updates, imports, deletes, `clean_project`, credentials, runtime state, and branch operations are separate authorization scopes. Never run `clean_project` after a write.
