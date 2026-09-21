---
name: 1c-code-index
description: Search and analyze indexed 1C source and metadata through read-only code-index when slight staleness is acceptable. Use for discovery, structure, references, graphs, and impact; never for writes, platform APIs, live truth, or primary diagnostics.
---

# 1C code-index

Bind the exact alias from the workspace mapping; never infer one from filesystem proximity. Call `health` only when status/freshness is unknown or a state change/failure invalidated it. Report stale, incomplete, or errored coverage.

Use the first sufficient route:

```text
structured metadata/symbol query
-> exact function/symbol
-> bounded BSL callers/callees/references at depth 1
-> bounded grep/read_file
-> bounded bsl_sql only when no named tool fits
```

Prefer BSL-specific call tools. Empty call graphs cover indexed static calls only; check string dispatch only when plausible. `get_register_writers` covers declarative edges only. For large modules, inspect the symbol inventory and selected bodies, never the full module first.

## Bounded reuse

For standalone reusable behavior, express purpose as 1–3 terms for `search_terms`.
Use the current scope's mapped alias and only evidenced dependencies: adapter uses
its applicable `kfk`/`kfk-base`/`kfk-examples`, conversion `kfk-conv`/`kfk-conv-kd`,
unit `kfk-unit` plus required canonical tested aliases; upstream `kfk-yaxunit` is read-only.
Never search the whole workspace by default or infer dependencies from proximity.

Inspect at most 5 relevant candidates by default with `get_function`; inspect only
those that can change the decision. Check semantic purpose, parameters, return
contract, client/server context, export availability and repository ownership.
Use depth-1 callers/callees/references only for an ambiguous contract/use. One
justified escalation per unresolved fact; exceeding 5 requires ambiguity,
insufficient coverage or conflicting candidates. Stop at a suitable implementation.
A further expansion requires a new unresolved fact.

Reuse a compatible method. For a non-exported candidate, first consider its owner
and whether a separately justified contract change is allowed; do not duplicate it
automatically. New logic requires no suitable candidate or an evidenced contract,
context, ownership or coverage mismatch. Empty results prove absence only within
ready, complete documented search coverage. Record a brief decision, not raw traces.
Finding another repository's candidate never expands mutation scope.

## Authority boundary

Stop when the indexed answer is sufficient; do not repeat it in EDT. Use EDT only for a distinct authoritative fact: exact pre-mutation target, live state, platform truth or primary diagnostics. Stale/incomplete required index stops indexed work; no duplicate EDT discovery fallback. Conflicting index evidence is invalid until freshness is re-established; contradictory required authoritative results stop the task.

Report only the result and material truncation, coverage, health, or staleness limits.
