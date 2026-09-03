---
name: 1c-standards
description: Resolve 1C standards, corporate work policy, diagnostic meaning and snippet-rule questions through v8std. Use for unresolved knowledge questions, not ordinary source discovery, platform APIs or YAxUnit API facts.
---

# 1C Standards

Use the configured v8std MCP for standards/policy, never as live-project or platform authority. A classified change already has its selector in $1c-code-change; do not repeat that lookup or start a search just because work is implementation or review.

| Evidence needed | Retrieval |
|---|---|
| Known short document, complete body | v8std_get_summary with body_limit=6000; require body_truncated=false |
| Known exact heading | v8std_get_section |
| Full document not covered compactly | v8std_get_page |
| Unknown topic/applicability | one bounded v8std_search OR v8std_get_requirements_for_context, then exact evidence |
| Diagnostic codes / short fragment | v8std_explain_diagnostics / v8std_explain_snippet |
| Material linked requirement still unresolved | v8std_get_related |

Filter discovery by the required collections: v8std for general standards; corporate for additional work rules, restricted to corporate:work:* results. Exact-ID tools need no collection filter. Search/ranked candidates are not exhaustive; a truncated body is not complete evidence. Missing, ambiguous or incomplete required evidence blocks the dependent conclusion or mutation.

Follow only links relevant to the actual mechanism. Do not recursively preload related pages. Reuse complete documents/sections already in context. Precedence: explicit user/project constraints, mandatory work rules, recommended work rules, general standards, advisory material.
