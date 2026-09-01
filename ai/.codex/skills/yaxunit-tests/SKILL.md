---
name: yaxunit-tests
description: Create, change, find, analyze, review, run, and debug 1C modular tests built on YAxUnit. Use for YAxUnit test modules, registration, assertions, parameterization, test data, mocks, fixtures, execution, or reports; do not use for application behavior changes unrelated to tests or standalone platform API lookups.
---

# YAxUnit Tests

Use `$1c-routing` invariants. For any persistent 1C test mutation, also use `$1c-code-change`; the assigned EDT-MCP is the only writer and the primary validation gate.

## Establish once per session

- Resolve the YAxUnit core, tested product, test owner, launch configuration, application/infobase, and known fixtures from workspace instructions and live evidence only when not already established.
- Reuse these facts, confirmed API signatures/semantics, and project conventions across substeps. Recheck only after a relevant failure, restart/resync/reindex/update, user-reported change, conflicting evidence, or a genuinely volatile fact.
- The installed YAxUnit core implementation is the exact API truth; its documentation supplies conceptual guidance. Use the live core through the assigned EDT-MCP and its canonical read-only code-index alias for definitions, implementations, and real usages. In Kafka these are `unit-edt` on port `8768` and `kfk-yaxunit`.
- The live EDT model wins on current source, metadata, diagnostics, and platform-aware behavior. If EDT and the index disagree, EDT wins and index freshness must be checked.
- Assume only the YAxUnit core, tested product, and test owner are available. Do not require external manuals, role files, templates, downloaded examples, or auxiliary projects. Derive uncertain API behavior from the available core itself.

## Test ownership

YAxUnit permits test modules to live either with the YAxUnit core or in a separate test extension. Determine the owner from the current workspace instead of assuming one layout.

- When tests are owned by the core, keep test mutations in the core test scope selected by the workspace.
- When tests are owned by a separate extension, keep product tests in that extension and treat the YAxUnit project as a read-only framework dependency unless the user explicitly requests a core change.
- In Kafka, product modular tests are owned by the separate `unit` extension. It is both the test-module owner and an allowed white-box test harness over the base configuration. Use `unit-edt` for live changes and `kfk-unit` for supplementary read-only search; do not place Kafka product tests in the YAxUnit core.

## Load detail only when needed

- Read [references/workflows.md](references/workflows.md) only when the workflow is not already established, test architecture is being created or substantially changed, execution/debugging is unfamiliar, test ownership/layout is unresolved, or its detailed procedure is needed for the next decision.
- Read [references/authoring-basics.md](references/authoring-basics.md) once when creating a new YAxUnit test module or substantially rewriting test-data setup or database assertions, unless its stable defaults are already established in this session.
- Read [references/yaxunit-patterns.md](references/yaxunit-patterns.md) only when an unfamiliar choice about registration, naming, assertions, parameters, data isolation, hooks, contexts, or predicates affects the test.
- Read [references/testability.md](references/testability.md) only after a real testability obstacle appears: inaccessible meaningful logic, an uncontrollable dependency, heavy external infrastructure, nondeterminism, excessive cost, or a proposed product-only seam/unsupported conclusion.
- Do not reread a skill/reference merely because a new module or substep began while its content remains available in the session.

Reuse stable authoring defaults from this skill and its references without repeatedly researching the core. When a YAxUnit API was confirmed in the installed core or used successfully in a focused runtime test in this session, reuse that contract. Reinspect it only for an exact unknown signature, rare method, new API/semantic question, context difference, unexpected failure, disputed evidence, or suspected incompatibility.

Keep changes in the resolved test owner. Do not change the tested product or YAxUnit core unless the user explicitly grants that additional repository scope.

## Completion gate

After every actual 1C mutation, run focused EDT diagnostics for the affected objects and inspect the findings. Before declaring newly created or materially changed tests ready, perform the local mandatory authoring review in [references/workflows.md](references/workflows.md); if it leads to another mutation, validate that mutation again. Then call the canonical runtime operation `run_yaxunit_tests` at the narrowest relevant scope supported by the configured environment. A green run proves covered executable behavior but not authoring quality, and an unexpected `0` discovered tests is a failure rather than green verification. Broaden only at an acceptance checkpoint. Report changed logical objects, material diagnostics/tests, results, and verification gaps; never claim an unperformed run.
