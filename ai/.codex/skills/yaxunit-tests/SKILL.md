---
name: yaxunit-tests
description: Create, review, run, and debug Kafka YAxUnit tests using the mandatory v8std YAxUnit corpus. Use only for test modules, registration, assertions, data, mocks, fixtures, execution, or reports.
---

# Kafka YAxUnit Tests

Before test analysis, authoring, or review, classify the operation and mechanisms. Load each matching known pattern ID below exactly once with `v8std_get_page`; reuse it before implementation and during the authoring gate. Search `collections=["yaxunit"]` only when classification cannot determine the relevant pattern or API concept. Never query or apply `corporate`.

| Scenario or mechanism | Required pattern IDs |
|---|---|
| Create a test in an existing module | `yaxunit:patterns:authoring-baseline` |
| Create a test common module | `authoring-baseline`, `test-module`, `naming` |
| Change registration or use parameters | `registration-and-parameters` |
| Assertion-focused or non-trivial assertion change | `assertions` |
| Assert database/register presence, absence, count, fields, or rows | `assertions`; add `predicates-and-queries` only for a non-trivial predicate |
| Create objects or persistent records | `test-data`, `data-isolation` |
| Configure `ВТранзакции` or `УдалениеТестовыхДанных` | `data-isolation` |
| Use mocks | `mocking` |
| Use predicates or query helpers | `predicates-and-queries` |
| Use file or XDTO test dependencies | `dependencies` |
| Use hooks or client/server context state | `lifecycle-and-contexts` |
| Review, debug, or migrate an existing test | `test-analysis-and-migration` |

Unqualified short names in the table use the `yaxunit:patterns:` prefix. Review does not automatically load `authoring-baseline`; add only pages for mechanisms found in the code.

Project naming override: a YAxUnit test module follows the object-based scheme from `yaxunit:patterns:naming` without `кфк_т_`. Use `кфк_т_` only for a meaningfully named auxiliary extension module such as an override or testability seam.

Keep the three MCP roles disjoint:

- `v8std`: known YAxUnit patterns by direct ID and discovery for unresolved API guidance.
- `code-index`: read-only definitions and real usages in `kfk-yaxunit`, plus bounded product/test search through their assigned aliases.
- `unit-edt`: live state, an exact installed-version signature only when unknown or conflicting with v8std, all mutations, diagnostics, and test runs.

Tests belong to the `unit` extension. Do not mutate product code or YAxUnit core without separate authorization. Load `$1c-code-change` only when a mutation is required; its knowledge gate supplies any applicable general 1C standards without searching merely because this is a test task.

Load [references/workflows.md](references/workflows.md) only when creating/changing/running tests. Load [references/testability.md](references/testability.md) only after a concrete testability obstacle. Do not reread either while its content remains available.

For a change, completion requires focused EDT diagnostics, validation against the same loaded pattern set, the authoring gate, and the narrowest `run_yaxunit_tests`. Unexpected `0` discovered tests is failure. Report only material findings, results, and verification gaps.
