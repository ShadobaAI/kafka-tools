---
name: 1c-code-index
description: Retrieve read-only 1C project information and perform narrow or broad search and analysis through the federated code-index MCP when slight index staleness is acceptable. Use only after binding the exact repository alias; do not use for writes, authoritative live EDT state, platform API truth, or primary diagnostics.
---

# 1C code-index

Use `$1c-routing` invariants. `code-index` is the preferred eventually-consistent read-only project view when slight staleness is acceptable, not the live project model.

## Bind and verify

1. Resolve the exact canonical source repository and its configured alias before the first query. A composed EDT project may intentionally bind to more than one canonical source alias, and a secondary checkout may intentionally reuse a canonical alias; follow only the explicit workspace mapping. Never infer an alias from filesystem proximity or similar source content.
2. Call `health` only when daemon/index status or freshness has not already been established in the session. Reuse a successful health result across substeps unless a query error, restart, reindex/update, conflicting evidence, or another state-change signal makes it doubtful.
3. If the repository is absent, indexing, stale, or errored, report that state. Do not present incomplete index output as exhaustive.

## Structured-first queries

- For each lookup, state the unresolved question internally and stop as soon as enough evidence exists to choose the next action. Do not run parallel search mechanisms for reassurance.
- Use this escalation order: structured metadata/symbol query -> exact function/symbol -> bounded callers/callees/references -> bounded grep -> bounded `read_file` -> `bsl_sql` only as a specialized fallback.
- Start with `search_terms`, symbol/function lookup, object structure/profile, form handlers, event subscriptions, call/data graph, register writers, or references, whichever directly answers the question.
- For BSL call analysis, prefer `get_callers_bsl`, `get_callees_bsl`, `get_call_tree_bsl`, and `find_path_bsl`. They use `proc_call_graph`, preserve procedure keys and report coverage. Use the universal `get_callers`, `get_callees`, `get_call_tree`, and `find_path` only for non-BSL languages or explicit inspection of the core `calls` graph.
- Start BSL call analysis at depth 1. Increase depth only for a named unresolved dependency that depth 1 cannot answer.
- Treat `get_register_writers` as a query for declarative `RegisterRecords` metadata edges only. `writers_count=0` does not exclude programmatic writes through a record set or record manager; investigate those through bounded `find_references`/`grep_code` and confirm material conclusions in EDT.
- Use `grep_body`/`grep_code`, `list_files`, and `read_file` only when earlier structured routes cannot answer the question. Constrain repository, path, language, result count, and the minimum line range; do not read neighboring ranges without an established dependency.
- Use `bsl_sql` only for a concrete read-only question unsupported by named tools. Keep it bounded and never explore the schema when a named tool answers the question.
- Treat empty or truncated output according to returned status, caps, pagination, and index coverage. An empty BSL call-graph response covers only indexed static edges: search literal procedure-name strings with bounded `grep_body`/`grep_code` when dynamic dispatch is plausible, then confirm material conclusions through BSL LS or EDT.

For a large module, especially one over roughly 1500 lines, never begin with the full module. Obtain its function/symbol inventory, select the relevant functional area and exact functions, read only their bodies, inspect callers/callees at depth 1, and widen only for a specific unresolved dependency.

## Authority boundary

Use code-index alone for usage discovery, candidate lists, structure, and impact evidence when slight staleness is acceptable. Before mutation, read the exact current target through EDT. Use EDT for platform semantics, primary diagnostics, live-state conclusions, absent/doubtful index facts, and material staleness risk. Do not repeat an equivalent EDT search solely to reconfirm a sufficient index result. If EDT disagrees, EDT wins and the index is stale or incomplete until proven otherwise.

Report the material result and any truncation, coverage, health, or staleness limit that affects confidence. Omit routine alias, health, and tool chronology when they do not affect the conclusion.
