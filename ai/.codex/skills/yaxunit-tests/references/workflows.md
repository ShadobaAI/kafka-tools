# YAxUnit Workflows

Use the smallest workflow that satisfies the request. Preserve Russian 1C identifiers and the established style of the owning test project.

## Find or analyze tests

1. Identify the YAxUnit core project, tested product, test owner, object/module, method, and expected behavior. The test owner may be the core itself or a separate test extension.
2. Use the test repository code-index alias to locate registrations, test procedures, fixtures, helpers, and related coverage. In the Kafka unit checkout this is `kfk-unit`.
3. Use the alias mapped to the tested repository only when analysis must cross into application behavior. In the Kafka unit workspace these may be `kfk`, `kfk-base`, and `kfk-examples` according to the workspace mapping.
4. Use the core index for YAxUnit API definitions, implementations, and real usages. In Kafka its alias is `kfk-yaxunit`. Prefer a narrow symbol or path-filtered query over a repository-wide scan.
5. Confirm through the assigned EDT-MCP when the conclusion depends on authoritative live source, metadata, platform semantics, diagnostics, or a fact the index cannot represent.

Static index results do not prove absence of dynamic string/reflection calls. Report that limitation when it affects the conclusion.

## Create or change tests

1. Resolve the test owner first. Inspect its current live object/module through EDT and locate nearby tests through its index. In Kafka the owner is the separate `unit` extension, not the YAxUnit core.
2. Define observable behavior, execution context, inputs, expected result or side effect, and isolation strategy. Add only the cases needed for the requested behavior and important boundaries.
3. Confirm unfamiliar or version-sensitive YAxUnit calls against the available core implementation through its index and, when available, the live EDT core project.
4. Create or mutate common modules and BSL only through the assigned EDT-MCP. Never access or patch serialized `src/**` through filesystem or shell tools.
5. Keep `ИсполняемыеСценарии` declarative: register test sets, tests, variants, tags, contexts, hooks, and settings there; do not prepare data or execute application behavior in registration.
6. Keep each test independent. Prepare only the data it needs, perform one behavior, and assert observable outcomes. Use helpers for meaningful repeated setup rather than hiding the scenario in a large fixture.
7. Run focused EDT validation after each mutation. Inspect every relevant finding against current source and metadata; do not suppress diagnostics.
8. Run the affected test procedure, set, or module with the repository-documented YAxUnit runner. Do not invent launch parameters. Run broader scopes only when focused execution cannot establish the result.

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
- Use the runner and launch configuration exposed by the available core, test owner, and assigned EDT workspace. Do not invent launch parameters. EDT no-restart execution may propagate only the current test module text; do not assume metadata or dependency changes are loaded without the required restart/update.
- A run may modify infobase data. Use only the isolation mechanism selected by the test and do not infer authorization for database updates, destructive cleanup, or environment reconfiguration.
- When execution is unavailable, complete safe static analysis and state which runtime conclusion remains unverified.
