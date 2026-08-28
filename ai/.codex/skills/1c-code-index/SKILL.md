---
name: 1c-code-index
description: Retrieve read-only 1C project information and perform narrow or broad search and analysis through the federated code-index MCP when slight index staleness is acceptable. Use only after binding the exact repository alias; do not use for writes, authoritative live EDT state, platform API truth, or primary diagnostics.
---

# 1C code-index

Use `$1c-routing` invariants. `code-index` is the preferred eventually-consistent read-only project view when slight staleness is acceptable, not the live project model.

## Bind and verify

1. Resolve the exact canonical source repository and its configured alias before the first query. A composed EDT project may intentionally bind to more than one canonical source alias, and a secondary checkout may intentionally reuse a canonical alias; follow only the explicit workspace mapping. Never infer an alias from filesystem proximity or similar source content.
2. Call `health` when daemon/index status or freshness is not already established for the current task.
3. If the repository is absent, indexing, stale, or errored, report that state. Do not present incomplete index output as exhaustive.

## Query narrowly

- Start with the most structured tool that answers the question: `search_terms`, symbol/function lookup, object structure/profile, form handlers, event subscriptions, call/data graph, register writers, or references.
- For BSL call analysis, prefer `get_callers_bsl`, `get_callees_bsl`, `get_call_tree_bsl`, and `find_path_bsl`. They use `proc_call_graph`, preserve procedure keys and report coverage. Use the universal `get_callers`, `get_callees`, `get_call_tree`, and `find_path` only for non-BSL languages or explicit inspection of the core `calls` graph.
- Treat `get_register_writers` as a query for declarative `RegisterRecords` metadata edges only. `writers_count=0` does not exclude programmatic writes through a record set or record manager; investigate those through bounded `find_references`/`grep_code` and confirm material conclusions in EDT.
- Use `grep_body`/`grep_code`, `list_files`, and `read_file` only when a structured query cannot answer the question, and constrain repository, path, language, result count, and line range.
- Use `bsl_sql` only for a concrete read-only question unsupported by named tools. Keep the query bounded; never use it as schema exploration by default.
- Treat empty or truncated output according to returned status, caps, pagination, and index coverage. An empty BSL call-graph response covers only indexed static edges: search literal procedure-name strings with bounded `grep_body`/`grep_code` when dynamic dispatch is plausible, then confirm material conclusions through BSL LS or EDT.

## Authority boundary

Confirm any fact that drives a mutation, API decision, validation result, or current-state conclusion through the assigned EDT-MCP. If EDT disagrees, EDT wins and the index is classified as stale or incomplete until proven otherwise.

Report the alias, relevant health/freshness state, tools used, material result, truncation/coverage limits, and EDT confirmation when the result affected a decision.
