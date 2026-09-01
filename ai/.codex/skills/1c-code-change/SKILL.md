---
name: 1c-code-change
description: Implement or review a scoped change to 1C BSL, queries, metadata, forms, rights, DCS, XDTO, translations, or related project behavior through the assigned EDT-MCP. Use for any 1C project mutation or change-focused review; do not use for a standalone platform documentation or standards lookup.
---

# 1C Code Change

Use `$1c-routing` invariants. EDT-MCP assigned by workspace instructions is the only writer and primary validation gate.

## Pipeline

```text
read exact current method/object through EDT
-> inspect only directly affected contracts
-> one logical EDT mutation
-> focused EDT validation and finding classification
-> focused behavior test when required
```

## Work narrowly

- Reuse session-established routing and facts. Resolve the exact project, logical object, module, and method through EDT only when not already established. Never inspect `src/**` through filesystem tools.
- Read the smallest current symbol or metadata fragment needed for the planned change. For a local change, normally inspect only that body, directly affected signatures/contracts, and one existing usage for an unfamiliar API.
- Perform broad impact analysis only for a public API or signature, shared contract, metadata structure, mass refactoring, behavior with many callers, or an explicit user request.
- Use code-index only for allowed read-only search, graph, structure, or impact evidence. Use BSL LS only for focused read-only BSL diagnostics or semantics in a configured repository.
- Before a non-trivial writer, obtain current metadata/source and use `get_tool_guide` only when the writer contract is genuinely unclear or version-sensitive.

## Mutation and validation

- Form the complete logically atomic change before writing. When several edits belong to one method or target fragment, prefer one guarded EDT mutation over multiple micro-mutations. Avoid full-module replacement or syntax-check bypass unless required and justified.
- After every actual mutation, run focused EDT revalidation for affected objects and inspect EDT project errors. Validate changed queries, XDTO, forms, templates, or tests with the specialized EDT capability when applicable. Reducing writer calls never permits combining or skipping the validation required after a writer.
- Do not reread source merely to confirm a successful writer. Reread only after an ambiguous result, when a new revision/hash is needed for a separate mutation, when a diagnostic points to the text, when EDT may have structurally transformed it, or when the next decision depends on the persisted text.
- Do not disable, suppress, filter out, or hide EDT diagnostics.
- Verify each relevant EDT finding against the current source and metadata context before treating it as a confirmed defect.
- Leave a finding unfixed only when relevant evidence such as platform documentation, content assist, a focused test, code-index context, or focused BSL LS diagnostics supports classifying it as a false positive. Otherwise keep it unresolved. Report its code, message, location, classification, evidence, and remaining uncertainty; do not claim a clean result while relevant findings remain unresolved.
- `update_database`, imports, deletes, `clean_project`, credential changes, runtime state changes, and branch operations are separate high-risk actions; do not infer them from a code-change request.
- Do not run `clean_project` after an EDT write. Use `resync_to_disk` only to reconcile authoritative EDT model state to disk.

When static validation is sufficient to run a safe focused behavior test, prefer that feedback over broader speculative research. Stop when the requested change and focused verification are complete. Report the outcome, material checks/findings, and verification gaps rather than tool-call chronology.
