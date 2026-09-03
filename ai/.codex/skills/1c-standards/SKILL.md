---
name: 1c-standards
description: Apply v8std requirements to 1C design, normative analysis, diagnostics and snippets; resolve unknown standards and work policy. Not source discovery or platform/YAxUnit API lookup.
---

# 1C Standards

Use configured v8std for standards/policy, never live-project or platform truth. For design or normative analysis of an artifact, read the shared [requirements selector](../1c-code-change/references/requirements.md) once scope is known; apply only decision-relevant rows. A change already classified by $1c-code-change reuses that selection, without another search. Read-only design needs no mutation diagnostics or write steps.

| Evidence needed | Retrieval |
|---|---|
| Known short document, complete body | v8std_get_summary with body_limit=6000; require body_truncated=false |
| Known exact heading | v8std_get_section |
| Full document not covered compactly | v8std_get_page |
| Unknown topic/applicability | one bounded v8std_search OR v8std_get_requirements_for_context, then exact evidence |
| Diagnostic codes / short fragment | v8std_explain_diagnostics / v8std_explain_snippet |
| Material linked requirement still unresolved | v8std_get_related |

Filter discovery by the required collections: v8std for general standards; corporate for additional work rules, restricted to corporate:work:* results. Exact-ID tools need no collection filter. Search/ranked candidates are not exhaustive; a truncated body is not complete evidence. Missing, ambiguous or incomplete required evidence blocks the dependent conclusion or mutation.

Resolve links supplying applicable conditions, exceptions or required dependencies; skip background/example links. A self-contained section is sufficient, a clause without its conditions is not. Examples supplement requirements, not replace them. Reuse complete evidence. Precedence: explicit user/project constraints, mandatory work rules, recommended work rules, general standards, advisory material. Report unresolved conflicts; do not invent exceptions.
