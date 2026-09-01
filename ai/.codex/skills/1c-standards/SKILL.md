---
name: 1c-standards
description: Retrieve and apply general 1C standards through v8std. Use for every Kafka 1C design, implementation, change review, standards question, diagnostic interpretation, or short snippet analysis; do not use for project source, platform APIs, or YAxUnit facts.
---

# 1C Standards

Use only the configured `v8std` MCP. It supplies standards, not live project or platform truth. Never query or apply the `corporate` collection.

For design, implementation, or change review, make one narrow search for the affected behavior with `collections=["v8std"]`, unless sufficient relevant evidence is already in context.

## Route evidence

| Input | Route |
|---|---|
| General 1C rule or topic | `v8std_search` with `collections=["v8std"]` |
| Known page ID, alias, path, or URL | `v8std_get_page` |
| Analyzer diagnostic codes | `v8std_explain_diagnostics` filtered to `v8std` |
| Related requirements may change the conclusion | `v8std_get_related` within `v8std` |
| Short BSL/SDBL fragment | `v8std_explain_snippet` filtered to `v8std` |

Never make an unfiltered request. Read every material search result through `v8std_get_page`, stop when the evidence is sufficient, and do not repeat the fact in another MCP. Do not invent rule IDs, wording, obligation levels, or API facts.
