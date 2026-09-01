# YAxUnit Workflows

Use the smallest workflow that satisfies the request. Preserve Russian 1C identifiers and the established style of the owning test project.

Reuse session-established owner/core mapping, aliases, runner, infobase, fixtures, and YAxUnit API facts. Before another lookup, require a concrete unresolved question whose answer can change the next test, mutation, or decision.

## Find or analyze tests

1. Identify only still-unknown items among the core, tested product, test owner, object/module, method, and expected behavior. The owner may be the core or a separate test extension.
2. Use the test repository code-index alias to locate registrations, test procedures, fixtures, helpers, and related coverage. In the Kafka unit checkout this is `kfk-unit`.
3. Use the alias mapped to the tested repository only when analysis must cross into application behavior. In the Kafka unit workspace these may be `kfk`, `kfk-base`, and `kfk-examples` according to the workspace mapping.
4. Use the core index for an unfamiliar YAxUnit API definition, implementation, or real usage. In Kafka its alias is `kfk-yaxunit`. Prefer one exact symbol or path-filtered query and stop when it answers the question.
5. Confirm through the assigned EDT-MCP when the conclusion depends on authoritative live source, metadata, platform semantics, diagnostics, or a fact the index cannot represent.

Static index results do not prove absence of dynamic string/reflection calls. Report that limitation when it affects the conclusion.

## Create or change tests

1. Reuse the resolved test owner. Inspect the exact current live target through EDT and locate one nearby test through its index when a local convention is still unknown. In Kafka the owner is the separate `unit` extension, not the YAxUnit core.
2. Define observable behavior, execution context, inputs, expected result or side effect, and isolation strategy. Add only the cases needed for the requested behavior and important boundaries.
3. Before creating data, run one exact search for an existing shared semantic fixture API in the test owner and relevant `examples`; do not scan all examples. In Kafka check `кфк_т_ТестовыеДанные` first. If session context establishes that `кфк_т_ТестовыеДанные.ИнициализацияДанных()` runs during test-infobase creation, treat those data as ready and do not initialize them again. Reuse such a fixture when it represents the domain object/configuration the scenario needs. If none exists, stop widening the search; create unique records, edge cases, and other local scenario data through the appropriate `ЮТест.Данные()` builder/generator by default, with low-level setup only as an evidence-backed fallback.
4. After selecting the suitable YAxUnit builder/generator, read [testability.md](testability.md) only if a real obstacle remains, such as still-large setup or real external infrastructure, and stop at the first adequate seam. Otherwise create only the smallest local builder-based fixture. Do not propose product refactoring merely because a method is private or a dependency is inconvenient.
5. Confirm only unfamiliar or version-sensitive YAxUnit calls against the installed core. Reuse calls already confirmed or proven by focused runtime execution in this session.
6. Form one atomic test change where practical, then create or mutate common modules and BSL only through the assigned EDT-MCP. Never access or patch serialized `src/**` through filesystem or shell tools.
7. Keep `ИсполняемыеСценарии` declarative and create common-module top-level regions according to the std455 baseline before the first write. Keep each test independent, prepare only its required data, perform one behavior, and assert observable outcomes through the most specific YAxUnit assertion; database state defaults to the specialized table/database API rather than a hand-written inspection query.
8. After every actual mutation, run focused EDT validation and inspect relevant findings without suppression.
9. Perform the mandatory authoring review below on the changed module/fragment. Fix authoring issues before runtime completion; every resulting mutation requires focused EDT validation again.
10. Run the narrowest supported runtime scope: test procedure, then test set, then module. Broaden to tags/suite only after local green and only when acceptance criteria require it. A second broad run is justified only for repeatability/isolation, transaction/cleanup/shared-state risk, an explicit checkpoint, or an explicit user request.

## Mandatory authoring review

Before declaring newly created or materially changed tests ready, review only the changed test module/fragment:

- **Structure and naming:** std455/project top-level structure is respected; there are no arbitrary top-level functional regions; the common-module name identifies the tested object type, checked object, and applicable module type after the `кфк_т_` namespace; `ИсполняемыеСценарии()` remains declarative.
- **Assertions:** each check uses the most specific YAxUnit assertion; no query exists only to inspect/count table rows; assertions target observable state rather than an avoidable intermediate value.
- **Test data:** shared semantic fixtures are used where appropriate; object attributes, references, and table-part rows form one coherent scenario with intentional cardinality, order, relationships, and dependent values; a negative case breaks only its target invariant; scenario-local data uses the suitable public `ЮТест.Данные()` operation; a `КонструкторОбъекта` chain has the required terminal/result semantics and is not unintentionally reused with retained data; only truly incidental fields are generated, and low-level setup has an evidence-backed reason.
- **Isolation:** the test is independent; transaction/cleanup scopes match the side effects; order, collisions, and pre-existing data cannot silently determine the result.
- **Maintainability:** every helper satisfies the general `$1c-code-change` method-extraction gate; tested actions and decisive expectations remain visible; setup is minimal, names/report labels explain behavior, and each test covers one coherent behavior.

A green YAxUnit run does not replace this authoring review.

## Review tests

Review in this order: behavior/requirement, test-data correctness, assertions, isolation, module structure/baseline conventions, maintainability, then cosmetics. Confirm registration and variants, contexts and hooks, material negative paths/boundaries/side effects, and that mocks isolate a real boundary without replacing the behavior under test.

For a change-focused review, use live EDT diagnostics as the primary gate and corroborate with `kfk-yaxunit` or focused tests. Report actionable findings with exact logical locations and evidence.

## Debug or run tests

- Start from the smallest failing test and inspect registration, parameters, hooks, contexts, data, assertion message, and application path.
- If a non-empty focused scope was expected, `0` discovered tests is a failed verification, not green. Check registration/module visibility and the persisted changed method/registration fragment, classify runner/registration/source-propagation causes, fix the cause, revalidate every mutation, and repeat until the expected non-zero scope runs.
- Distinguish test defects, application defects, environment/data failures, and runner/configuration failures before changing code.
- After static validation, prefer a safe focused runtime run over speculative broad source research. Search again only after the failure classification identifies a concrete unresolved question.
- Use the runner and launch configuration exposed by the available core, test owner, and assigned EDT workspace. Do not invent launch parameters. EDT no-restart execution may propagate only the current test module text; do not assume metadata or dependency changes are loaded without the required restart/update.
- A run may modify infobase data. Use only the isolation mechanism selected by the test and do not infer authorization for database updates, destructive cleanup, or environment reconfiguration.
- When execution is unavailable, complete safe static analysis and state which runtime conclusion remains unverified.
