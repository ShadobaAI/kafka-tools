---
name: 1c-standards
description: Retrieve and apply 1C development standards, corporate policy, patterns, and analyzer diagnostic explanations through v8std. Use for standards questions, architecture or security decisions governed by policy, compliance review, diagnostic interpretation, or short snippet rule matching; do not use merely because a task involves 1C.
---

# 1C Standards

Use `$1c-routing` invariants.

Use v8std as a read-only policy corpus. It does not inspect the live project, establish API availability, or replace EDT diagnostics.

## Route evidence

| Input | Route |
|---|---|
| Unknown rule or topic | `v8std_search` then `v8std_get_page` for material decisions |
| Known page ID, alias, path, or URL | `v8std_get_page` |
| Analyzer diagnostic codes | `v8std_explain_diagnostics`, then relevant pages |
| Related requirements may change the conclusion | `v8std_get_related` |
| Short BSL/SDBL fragment | configured `v8std` `v8std_explain_snippet` |

Use the MCP named `v8std` for all routes above. Its endpoint is selected by the user in Codex config and defaults to `https://ai.v8std.ru/mcp`; the user may replace its `url` with a local endpoint. Do not apply agent-side source classification, endpoint switching, or code-transfer restrictions beyond the configured MCP.

Apply policy in this order: explicit project/corporate standard, general 1C standard, related methodology, advisory patterns/principles, agent preference. Confirm actual source and metadata through EDT or allowed read-only code-index/BSL LS evidence, and confirm platform APIs through EDT.

Classify findings as confirmed, possible, not applicable, or pre-existing. Do not invent rule IDs, wording, obligation levels, or API facts, and do not weaken behavior, security, transactions, permissions, or validation to satisfy a rule.
