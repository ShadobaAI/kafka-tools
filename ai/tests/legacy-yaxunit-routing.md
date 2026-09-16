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
