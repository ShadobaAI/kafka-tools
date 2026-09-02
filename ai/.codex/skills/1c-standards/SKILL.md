---
name: 1c-standards
description: Retrieve and apply general 1C standards through v8std. Use for every Kafka 1C design, implementation, change review, standards question, diagnostic interpretation, or short snippet analysis; do not use for project source, platform APIs, or YAxUnit facts.
---

# 1C Standards

Use only the configured `v8std` MCP. It supplies standards, not live project or platform truth. Never query or apply the `corporate` collection.

The calling subject skill owns task classification and mandatory-ID selection. Do not start a search merely because the task is design, implementation, or review. Reuse sufficient loaded evidence.

## Route evidence

| Input | Route |
|---|---|
| Known page ID, alias, path, or URL | `v8std_get_page` |
| Unknown 1C rule or topic | one narrow `v8std_search` with `collections=["v8std"]`, then `v8std_get_page` |
| Analyzer diagnostic codes | `v8std_explain_diagnostics` filtered to `v8std` |
| Short BSL/SDBL fragment | `v8std_explain_snippet` filtered to `v8std` |
| Related requirements can materially change the conclusion | `v8std_get_related` within `v8std` |

Never make an unfiltered request. Fetch each known ID once, read material search results through `v8std_get_page`, stop when the evidence is sufficient, and do not repeat the fact in another MCP. Search and related traversal are discovery fallbacks, not mandatory workflow stages. Do not invent rule IDs, wording, obligation levels, or API facts.
