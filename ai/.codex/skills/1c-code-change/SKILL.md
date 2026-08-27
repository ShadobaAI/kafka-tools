---
name: 1c-code-change
description: Implement or review a scoped change to 1C BSL, queries, metadata, forms, rights, DCS, XDTO, translations, or related project behavior through the assigned EDT-MCP. Use for any 1C project mutation or change-focused review; do not use for a standalone platform documentation or standards lookup.
---

# 1C Code Change

Use `$1c-routing` invariants. EDT-MCP assigned by workspace instructions is the only writer and primary validation gate.

## Pipeline

```text
inspect current EDT object/source
-> inspect semantic references and affected contracts
-> optionally add read-only code-index or BSL LS evidence
-> mutate through EDT-MCP
-> run focused EDT validation
-> inspect and classify relevant project errors
-> run behavior-specific tests when required
```

## Work narrowly

- Resolve the exact project, logical object, module, and method through EDT. Never inspect `src/**` through filesystem tools.
- Read only the source or metadata needed for the next decision. Use EDT definition, references, call hierarchy, outgoing structures, content assist, and query validation when they materially affect the change.
- Use code-index only for allowed read-only search, graph, structure, or impact evidence. Use BSL LS only for focused read-only BSL diagnostics or semantics in a configured repository.
- Before a non-trivial writer, obtain current metadata/source and use `get_tool_guide` when its contract is unclear or version-sensitive.

## Mutation and validation

- Prefer a narrow semantic mutation and supported revision/hash guard. Avoid full-module replacement or syntax-check bypass unless required and justified.
- After every mutation, run focused EDT revalidation for affected objects and inspect EDT project errors. Validate changed queries, XDTO, forms, templates, or tests with the specialized EDT capability when applicable.
- Do not disable, suppress, filter out, or hide EDT diagnostics.
- Verify each relevant EDT finding against the current source and metadata context before treating it as a confirmed defect.
- Leave a finding unfixed only when relevant evidence such as platform documentation, content assist, a focused test, code-index context, or focused BSL LS diagnostics supports classifying it as a false positive. Otherwise keep it unresolved. Report its code, message, location, classification, evidence, and remaining uncertainty; do not claim a clean result while relevant findings remain unresolved.
- `update_database`, imports, deletes, `clean_project`, credential changes, runtime state changes, and branch operations are separate high-risk actions; do not infer them from a code-change request.
- Do not run `clean_project` after an EDT write. Use `resync_to_disk` only to reconcile authoritative EDT model state to disk.

Stop when the requested change and required focused verification are complete. Report changed logical objects, checks actually run, relevant findings, and verification gaps.
