---
name: v8std-mcp
description: Retrieve and apply authoritative v8std.ru 1C development standards and diagnostic explanations. Use for a standards question, a known or suspected 1C rule, standards-compliance review, or interpretation of ACC/APK, BSLLS, EDT, or v8-code-style diagnostics. Do not activate merely because a task involves 1C or EDT.
---

# v8std MCP

Use `v8std` as a read-only source for how 1C code and metadata are recommended to be designed. It does not inspect a project, validate platform APIs, or prove that a retrieved rule applies.

## Route the request

| Input | Action |
|---|---|
| Known page ID, alias, path, or URL | Get that page or required section |
| Known analyzer diagnostic code | Explain that diagnostic |
| Unknown applicable standard | Search by a narrow topic |
| Short fragment needing standards guidance | Explain the smallest self-contained fragment |
| Relations may change a conclusion | Get related pages for the known rule |

Use the MCP tool exposed for that action; tool schemas are authoritative.

## Retrieve minimal evidence

- Request only decision-relevant fields, sections, snippets, or compact output when the tool schema supports bounds such as `limit`, `fields`, or `max_chars`. Never invent unsupported parameters.
- Do not load a full page automatically. Open more content only when the current result omits applicability, obligation level, exceptions, remediation, or evidence needed for a precise citation.
- Do not collect related standards or additional examples “just in case.”
- For diagnostic interpretation, preserve the analyzer family and code exactly; look up only IDs that can affect the task.

## Apply the result

Compare the rule with actual code, metadata, execution context, compatibility, and project configuration obtained from the appropriate project tool when needed. Classify a finding as confirmed, possible, not applicable, or pre-existing; search ranking and lexical similarity are not proof.

Do not activate EDT solely to answer a standards question. Conversely, use EDT/platform documentation—not v8std—to establish available APIs or live project state. Do not activate BSL LS unless actual static analysis is required.

Do not invent IDs, clauses, URLs, wording, or obligation levels, and do not weaken behavior, security, permissions, transactions, consistency, or validation to satisfy a rule. If v8std is unavailable, mark standards verification incomplete and distinguish verified guidance from model knowledge.

Report the material conclusion, classification, applicable rule or diagnostic identifier and URL, concise remediation risk, and remaining uncertainty. Avoid weak-result dumps.
