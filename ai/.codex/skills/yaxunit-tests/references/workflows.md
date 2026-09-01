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
3. Before creating a builder/fixture, run one exact search for an existing fixture API in the test owner and relevant `examples`; do not scan all examples. In Kafka check `кфк_т_ТестовыеДанные` first. If session context establishes that `кфк_т_ТестовыеДанные.ИнициализацияДанных()` runs during test-infobase creation, treat those data as ready and do not initialize them again. If the exact search finds no suitable fixture, stop searching rather than widening to all examples.
4. If a testability obstacle exists, including setup that would require a large fixture or real external infrastructure, read [testability.md](testability.md) before building it and stop at the first adequate seam. Otherwise create only the smallest local data builder. Do not propose product refactoring merely because a method is private or a dependency is inconvenient.
5. Confirm only unfamiliar or version-sensitive YAxUnit calls against the installed core. Reuse calls already confirmed or proven by focused runtime execution in this session.
6. Form one atomic test change where practical, then create or mutate common modules and BSL only through the assigned EDT-MCP. Never access or patch serialized `src/**` through filesystem or shell tools.
7. Keep `ИсполняемыеСценарии` declarative. Keep each test independent, prepare only its required data, perform one behavior, and assert observable outcomes.
8. After every actual mutation, run focused EDT validation and inspect relevant findings without suppression.
9. Run the narrowest supported runtime scope: test procedure, then test set, then module. Broaden to tags/suite only after local green and only when acceptance criteria require it. A second broad run is justified only for repeatability/isolation, transaction/cleanup/shared-state risk, an explicit checkpoint, or an explicit user request.

## Review tests

Review behavior before cosmetics:

- Does registration include the intended procedures and variants?
- Do assertions prove the requirement rather than merely confirm that code ran?
- Are client/server context, transaction support, cleanup lifetime, and hooks correct?
- Can results depend on pre-existing data, execution order, time, locale, or random collisions?
- Do mocks isolate a real boundary without replacing the behavior under test?
- Are material negative paths, boundaries, side effects, and database state covered?
- Do names and report representations explain the target method and scenario?

For a change-focused review, use live EDT diagnostics as the primary gate and corroborate with `kfk-yaxunit` or focused tests. Report actionable findings with exact logical locations and evidence.

## Debug or run tests

- Start from the smallest failing test and inspect registration, parameters, hooks, contexts, data, assertion message, and application path.
- Distinguish test defects, application defects, environment/data failures, and runner/configuration failures before changing code.
- After static validation, prefer a safe focused runtime run over speculative broad source research. Search again only after the failure classification identifies a concrete unresolved question.
- Use the runner and launch configuration exposed by the available core, test owner, and assigned EDT workspace. Do not invent launch parameters. EDT no-restart execution may propagate only the current test module text; do not assume metadata or dependency changes are loaded without the required restart/update.
- A run may modify infobase data. Use only the isolation mechanism selected by the test and do not infer authorization for database updates, destructive cleanup, or environment reconfiguration.
- When execution is unavailable, complete safe static analysis and state which runtime conclusion remains unverified.
