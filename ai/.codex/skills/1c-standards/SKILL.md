---
name: 1c-standards
description: Retrieve and apply general 1C standards and mandatory additional work policy through v8std. Use for every Kafka 1C design, implementation, change review, standards question, diagnostic interpretation, or short snippet analysis; do not use for project source, platform APIs, or YAxUnit facts.
---

# 1C Standards

Use only the configured `v8std` MCP. It supplies standards and policy, not live project or platform truth.

The calling subject skill owns task classification and mandatory-ID selection. Do not start a search merely because the task is design, implementation, or review. Load known `corporate:work:*` or `v8std` page IDs directly and reuse sufficient evidence. Before a persistent 1C mutation, every matching required page must be loaded completely; an unavailable MCP, missing page, truncated body, or unresolved applicability question stops the mutation.

## Route evidence

| Input | Route |
|---|---|
| Known page ID, alias, path, or URL | `v8std_get_page` |
| Unknown standards or policy topic | one narrow `v8std_search` in the exact required collection(s), then `v8std_get_page` |
| Analyzer diagnostic codes | `v8std_explain_diagnostics` filtered to the exact collection(s) |
| Short BSL/SDBL fragment | `v8std_explain_snippet` filtered to the exact collection(s) |
| Related requirements can materially change the conclusion | `v8std_get_related` within the selected collection(s) |

Never make an unfiltered request. Fetch each known ID once, read material search results through `v8std_get_page`, and stop when evidence is sufficient. Search and related traversal are discovery fallbacks, not mandatory workflow stages. Do not repeat sufficient v8std evidence in EDT, code-index, BSL LS, or web search. Never invent a rule when no material result exists. Apply precedence: explicit user/project constraints, mandatory additional work rules, recommended additional work rules, general 1C, advisory material.
