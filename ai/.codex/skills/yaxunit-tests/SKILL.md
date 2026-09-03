---
name: yaxunit-tests
description: Create, format, review, run, and debug Kafka YAxUnit tests using the mandatory v8std YAxUnit corpus. Use only for test modules, registration, assertions, data, mocks, fixtures, execution, or reports.
---

# Kafka YAxUnit Tests

## Pattern routing

Select artifact invariants, operation and actual mechanisms before designing, changing or judging a test. Load the union of matching pattern IDs once with `v8std_get_pattern`; require `found=true` and `body_truncated=false`, falling back to the complete same-ID `v8std_get_page`. Missing required evidence blocks the dependent decision/change. Reuse patterns across phases; search `collections=["yaxunit"]` only for an unresolved concept, and use `v8std_get_api_card` for a known module/member.

| Scenario or mechanism | Required pattern IDs |
|---|---|
| Create a test or change its behavior | `yaxunit:patterns:authoring-baseline` |
| Create a test common module | `authoring-baseline`, `test-module`, `naming` |
| Design/change/review module structure, test/helper placement or exported test contract | `test-module` |
| Introduce/change/review module or test naming | `naming` |
| Design/change/review registration or parameters | `registration-and-parameters`; `test-module` for the registration entrypoint contract |
| Assertion-focused or non-trivial assertion change | `assertions` |
| Assert database/register presence, absence, count, fields, or rows | `assertions`; add `predicates-and-queries` only for a non-trivial predicate |
| Create or fill test data | `test-data`; add `data-isolation` for persistent records |
| Configure `ВТранзакции` or `УдалениеТестовыхДанных` | `data-isolation` |
| Use mocks | `mocking` |
| Use predicates or query helpers | `predicates-and-queries` |
| Use file or XDTO test dependencies | `dependencies` |
| Use hooks or client/server context state | `lifecycle-and-contexts` |
| Review, debug, or migrate an existing test | `test-analysis-and-migration` |

Unqualified IDs use the `yaxunit:patterns:` prefix. For review/migration, select mechanisms within requested scope; do not load `authoring-baseline` by default. Run/report-only work needs no authoring patterns. Resolve uncovered mechanisms instead of assuming the table is exhaustive. Minimal examples do not replace general standards or work policy.

## Authoring constraints

When filling attributes, tabular sections, or other test data, derive values from field semantics rather than primitive type alone: inspect names, metadata, domain formats or units, and relationships. Prefer a matching `ЮТПодражатель` generator or platform API over arbitrary literals, and keep related fields coherent.

## Authority and scope

- `v8std`: known YAxUnit patterns by direct ID and discovery for unresolved API guidance.
- `code-index`: read-only definitions and real usages in `kfk-yaxunit`, plus bounded product/test search through their assigned aliases.
- `unit-edt`: live state, an exact installed-version signature only when unknown or conflicting with v8std, all mutations, diagnostics, and test runs.

Keep these roles disjoint. Tests belong to the `unit` extension. Do not mutate product code or YAxUnit core without separate authorization. Use $1c-standards for design/normative analysis and $1c-code-change for mutation or BSL change review; reuse their shared selection of general standards/work policy. Run/report-only work needs neither gate.

## Fluent-chain gate

Indent multiline fluent YAxUnit chains by logical ownership documented in the applicable pattern/API semantics, never by return type or physical call receiver:

- Logical siblings start in the same column.
- A child or its settings start one tab deeper than their logical owner.
- Returning to an ancestor or adding another sibling restores that logical level.

For registration, follow module -> set -> test -> test settings; another test is a sibling of the previous test. Equal return types do not flatten this hierarchy; different types do not create nesting. Resolve genuinely unclear ownership from the relevant pattern/API semantics, not signature-only checks or method-name guesses.

## References and completion

- Load [references/workflows.md](references/workflows.md) for design, creation, change, review, execution, or debugging.
- Load [references/testability.md](references/testability.md) only after a concrete testability obstacle.
- Do not reread a reference while its content remains available.

A change is complete only after focused EDT diagnostics, validation against the loaded patterns, the authoring gate, and the narrowest `run_yaxunit_tests`. Unexpected `0` discovered tests is failure. Design/review remain read-only and use only applicable gates, without a test run merely to report findings. Report material findings, results and verification gaps.
