---
name: v8std-mcp
description: Apply the v8std MCP knowledge base to 1C:Enterprise design, implementation, review, and diagnostics. Use to find or verify 1C standards and patterns, review BSL/SDBL or metadata decisions, interpret ACC/APK, BSLLS, EDT, or v8-code-style diagnostics, validate remediation, or support an EDT-MCP quality workflow with authoritative v8std.ru pages and URLs.
---

# v8std MCP

Use `v8std` as a read-only knowledge base for 1C standards, patterns, and diagnostic links. It is retrieval, not a static analyzer: it cannot inspect the project or prove a violation from a match.

## Route requests

| Input | Tool |
| --- | --- |
| Exact page ID, alias, path, or v8std.ru URL | `v8std_get_page` |
| ACC/APK, BSLLS, EDT, or v8-code-style codes | `v8std_explain_diagnostics` |
| Short BSL/SDBL fragment | `v8std_explain_snippet` |
| Natural-language topic or unknown ID | `v8std_search` |
| Relations around a known page | `v8std_get_related` |

Use tools exposed by the `v8std` MCP server; callable prefixes may vary by client.

## Apply standards before implementation

1. Inspect requirements, architecture, metadata, and execution context through the relevant EDT/analyzer service.
2. Identify material risk topics only: client/server boundaries, permissions and privileged mode, transactions and locks, queries, logging, background work, modal calls, localization, error handling, form/business-logic separation, extensions, and compatibility.
3. Use a narrow `v8std_search` for unknown topics. Do not send whole projects or collect standards “just in case.”
4. Open every decision-relevant candidate with `v8std_get_page`; read scope, obligation, exceptions, and examples.
5. Use `v8std_get_related` only when linked standards or diagnostics may change the conclusion.
6. Convert confirmed rules into concrete design constraints and acceptance checks; do not attach citations after choosing a solution.

v8std does not replace project research. Preserve local architecture and style among standard-compliant options, but never preserve an anti-pattern merely because it is common locally.

## Review code and diagnostics

1. For files or projects, obtain real diagnostics from EDT, v8-code-style, BSLLS, or another analyzer first. Use v8std to interpret them, not simulate them.
2. Send only short, self-contained fragments to `v8std_explain_snippet`; split larger code by behavior or suspected issue.
3. Preserve diagnostic family and code exactly, then resolve them with `v8std_explain_diagnostics`.
4. Open every diagnostic or standard page used in the conclusion with `v8std_get_page`.
5. Compare the full rule with actual code, types, metadata, call path, execution context, and compatibility mode.
6. Classify each finding as `confirmed`, `possible`, `not applicable`, or `pre-existing`. Scores, `match_reasons`, and confidence are not proof.
7. Check remediation for behavior changes, compatibility, security, and project fit.

## Preserve evidence integrity

- Never present search or snippet results as analyzer output.
- Never infer a violation from lexical similarity alone; snippet retrieval uses indexed rules, not full program semantics.
- Never invent IDs, clauses, mappings, URLs, wording, or obligation level.
- Prefer the smallest directly applicable page set; avoid weak-result dumps.
- Paraphrase rules and include direct URLs. Quote briefly only when exact wording matters.
- Do not change code when the user requested analysis only.
- Do not weaken validation, authorization, permissions, transactions, consistency, or error handling to silence a diagnostic.
- If rules conflict, identify the more specific rule and applicability conditions.
- If v8std is unavailable, mark standards verification incomplete and separate model knowledge from verified guidance.

## Return auditable results

For each material conclusion, report code location and evidence; classification; standard or diagnostic ID, applicable clause, and URL; concise remediation and behavior risk; actual analyzer/EDT/query/test checks; and remaining uncertainty. For implementations, separately list standards that shaped the design and those checked after the change.
