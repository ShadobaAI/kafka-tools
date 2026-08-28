---
name: yaxunit-tests
description: Create, change, find, analyze, review, run, and debug 1C modular tests built on YAxUnit. Use for YAxUnit test modules, registration, assertions, parameterization, test data, mocks, fixtures, execution, or reports; do not use for application behavior changes unrelated to tests or standalone platform API lookups.
---

# YAxUnit Tests

Use `$1c-routing` invariants. For any persistent 1C test mutation, also use `$1c-code-change`; the assigned EDT-MCP is the only writer and the primary validation gate.

## Sources of truth

- Resolve the exact YAxUnit core, tested product, and test owner from workspace instructions before searching or changing anything.
- The YAxUnit core implementation is the API truth. Use its live project through the assigned EDT-MCP and its canonical read-only code-index alias for definitions, implementations, and real usages. In the Kafka unit workspace these are `unit-edt` on port `8768` and `kfk-yaxunit`.
- The live EDT model wins on current source, metadata, diagnostics, and platform-aware behavior. If EDT and the index disagree, EDT wins and index freshness must be checked.
- Assume only the YAxUnit core, tested product, and test owner are available. Do not require external manuals, role files, templates, downloaded examples, or auxiliary projects. Derive uncertain API behavior from the available core itself.

## Test ownership

YAxUnit permits test modules to live either with the YAxUnit core or in a separate test extension. Determine the owner from the current workspace instead of assuming one layout.

- When tests are owned by the core, keep test mutations in the core test scope selected by the workspace.
- When tests are owned by a separate extension, keep product tests in that extension and treat the YAxUnit project as a read-only framework dependency unless the user explicitly requests a core change.
- In the Kafka workspace, product modular tests are owned by the separate `unit` extension. Use `unit-edt` for live changes and `kfk-unit` for supplementary read-only search; do not place Kafka product tests in the YAxUnit core.

## Route the request

- For discovery, impact analysis, or locating examples, read [references/workflows.md](references/workflows.md) and use the exact repository aliases defined by the workspace.
- For creating, changing, reviewing, or debugging tests, read [references/workflows.md](references/workflows.md).
- When choosing registration, naming, assertions, parameters, data isolation, hooks, predicates, or mocks, read [references/yaxunit-patterns.md](references/yaxunit-patterns.md).

Keep changes in the resolved test owner. Do not change the tested product or YAxUnit core unless the user explicitly grants that additional repository scope.

## Completion gate

After every 1C mutation, run focused EDT diagnostics for the affected objects and inspect the findings. Run the narrowest relevant YAxUnit tests when the configured environment supports execution. Report the logical test objects changed, checks actually run, relevant findings, test result, and any verification gap; never claim a test or diagnostic run that did not occur.
