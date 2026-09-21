---
name: yaxunit-tests
description: Create, format, review, run, and debug Kafka YAxUnit tests using the mandatory v8std YAxUnit corpus. Use only for test modules, registration, assertions, data, mocks, fixtures, execution, or reports.
---

# Kafka YAxUnit Tests

## Pattern routing

For design, creation, change, review, debug, or migration, call policy MCP `select_yaxunit_requirements` with the operation and union of explicit, classified, and observed mechanisms. Load each returned exact ID once via `v8std_get_pattern`; require `found=true` and `body_truncated=false`, or read the complete same-ID page. A missing pattern or unknown mechanism blocks the dependent decision. Reuse a valid selection across phases. Run/report-only work needs no authoring patterns.

Before a test mutation, validate a complete ledger with `validate_compliance`, `phase: proposal`. After mutation, inspect the actual test, include newly observed mechanisms, and validate with `phase: result` against the same digest or reselect with an explicit applicability reason. Mandatory status is `passed`; recommended deviations need `deviated` and nonblank `reason`. Reuse complete pattern text without another retrieval. Pattern retrieval alone does not prove compliance. Use `v8std_get_api_card` for a known module/member; use bounded YAxUnit search only for an unresolved concept. General BSL change requirements still use $1c-standards/$1c-code-change, including its mandatory reuse-gate and conservative L/M/H tiers. Test-only wrappers/registration may qualify for L; queries, production contract changes, state and other excluded mechanisms do not.

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
