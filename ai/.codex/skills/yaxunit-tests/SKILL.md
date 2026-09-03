---
name: yaxunit-tests
description: Create, format, review, run, and debug Kafka YAxUnit tests using the mandatory v8std YAxUnit corpus. Use only for test modules, registration, assertions, data, mocks, fixtures, execution, or reports.
---

# Kafka YAxUnit Tests

## Pattern routing

Classify the operation and mechanisms first. Load matching pattern IDs once with `v8std_get_pattern`; require `found=true` and `body_truncated=false`, using `v8std_get_page` of the same ID if the compact body is truncated. Reuse complete patterns for implementation and gates. Search `collections=["yaxunit"]` only for an unresolved API concept; use `v8std_get_api_card` for a known module/member.

| Scenario or mechanism | Required pattern IDs |
|---|---|
| Create a test in an existing module | `yaxunit:patterns:authoring-baseline` |
| Create a test common module | `authoring-baseline`, `test-module`, `naming` |
| Change registration or use parameters | `registration-and-parameters` |
| Assertion-focused or non-trivial assertion change | `assertions` |
| Assert database/register presence, absence, count, fields, or rows | `assertions`; add `predicates-and-queries` only for a non-trivial predicate |
| Create or fill test data | `test-data`; add `data-isolation` for persistent records |
| Configure `ВТранзакции` or `УдалениеТестовыхДанных` | `data-isolation` |
| Use mocks | `mocking` |
| Use predicates or query helpers | `predicates-and-queries` |
| Use file or XDTO test dependencies | `dependencies` |
| Use hooks or client/server context state | `lifecycle-and-contexts` |
| Review, debug, or migrate an existing test | `test-analysis-and-migration` |

Unqualified IDs use the `yaxunit:patterns:` prefix. For review or migration, add pages only for mechanisms present in the code; do not load `authoring-baseline` by default.

## Authoring constraints

When filling attributes, tabular sections, or other test data, derive values from field semantics rather than primitive type alone: inspect names, metadata, domain formats or units, and relationships. Prefer a matching `ЮТПодражатель` generator or platform API over arbitrary literals, and keep related fields coherent.

Project naming override: a YAxUnit test module follows the object-based scheme from `yaxunit:patterns:naming` without `кфк_т_`. Use `кфк_т_` only for a meaningfully named auxiliary extension module such as an override or testability seam.

## Authority and scope

- `v8std`: known YAxUnit patterns by direct ID and discovery for unresolved API guidance.
- `code-index`: read-only definitions and real usages in `kfk-yaxunit`, plus bounded product/test search through their assigned aliases.
- `unit-edt`: live state, an exact installed-version signature only when unknown or conflicting with v8std, all mutations, diagnostics, and test runs.

Keep these roles disjoint. Tests belong to the `unit` extension. Do not mutate product code or YAxUnit core without separate authorization. Load `$1c-code-change` for mutation or BSL change review, not run/report-only work; it supplies applicable general standards and work policy.

## Fluent-chain gate

For every multiline fluent YAxUnit chain, derive `(call, input receiver, output receiver, depth)` from the loaded contract or exact installed signature before emitting or accepting it. Then format recursively:

- Calls on the same receiver are siblings and start in the same column.
- A call on a returned or selected child receiver starts one tab deeper.
- A call on an ancestor receiver resumes that ancestor's column.

Never infer a transition from a method name, semantic guess, leading dot, or neighboring line. An unknown transition, or mechanically aligned dots without verified sibling receivers, fails the authoring or review gate.

## References and completion

- Load [references/workflows.md](references/workflows.md) for creation, change, execution, or debugging.
- Load [references/testability.md](references/testability.md) only after a concrete testability obstacle.
- Do not reread a reference while its content remains available.

A change is complete only after focused EDT diagnostics, validation against the loaded patterns, the authoring gate, and the narrowest `run_yaxunit_tests`. Unexpected `0` discovered tests is failure. Report only material findings, results, and verification gaps.
