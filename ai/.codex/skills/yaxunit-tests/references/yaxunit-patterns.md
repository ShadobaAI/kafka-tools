# YAxUnit Authoring Patterns

These are stable decision rules, not a substitute for checking the installed core when an API detail is uncertain.

Reuse an API signature or behavior already confirmed in the installed core or by a successful focused runtime test in this session. Do not search for its implementation again unless a new semantic/context question or incompatible failure appears.

## Module and registration

- Put tests in non-borrowed common modules of the resolved test owner. The owner may be the YAxUnit core or a separate test extension; in Kafka it is the separate `unit` extension. Prefer one test module for one tested module or coherent behavior area.
- Export `ИсполняемыеСценарии()` and always register a named test set, even when it contains one test.
- Register with `ЮТТесты.ДобавитьТестовыйНабор(...)` and `ДобавитьТест(...)`. Use `ДобавитьКлиентскийТест` or `ДобавитьСерверныйТест` only when context is part of the requirement.
- Registration supports a procedure name, representation, tags, and contexts. Parameterized registrations use `СПараметрами`, `СПараметрамиНаКлиенте`, or `СПараметрамиНаСервере`.

Minimal shape:

```bsl
Процедура ИсполняемыеСценарии() Экспорт

	ЮТТесты
		.ДобавитьТестовыйНабор("Общий модуль ИмяМодуля. ИмяМетода()")
		.ДобавитьТест("ИмяМетода_Сценарий", "ИмяМетода(). Ожидаемый результат");

КонецПроцедуры
```

Keep preparation and application calls out of this procedure.

## Naming and reports

- Test-set representation: `Тип объекта ИмяОбъекта. [Тип модуля.] ИмяМетода()`.
- Test procedure: `ИмяМетода_Сценарий`.
- Test representation: `ИмяМетода(). Описание ожидаемого поведения`.
- Follow object prefixes and module suffixes already established by the available core and test owner, such as `ОМ_` and `_МО`, `_ММ`, `_НЗ`. Confirm the exact mapping from existing core/test modules rather than guessing.
- Prefer a clear behavioral representation over encoding every detail into the procedure identifier.

## Assertions

- Start fluent assertions through `ЮТест.ОжидаетЧто(ФактическоеЗначение, Сообщение)` or the specialized database entry point. Do not call internal assertion modules directly.
- Assert the most specific observable property: value/type, collection contents, exception, database record, movement, or side effect.
- In fluent property chains, property paths are evaluated from the original value passed to `ОжидаетЧто`; do not assume a previous `Свойство` changes the root for later paths.
- Prefer one cohesive expectation chain when it remains readable. Split unrelated requirements into separate assertions or tests.
- For a deliberate custom failure, use the public YAxUnit failure mechanism rather than raising an arbitrary application exception.

## Variants and predicates

- Prefer parameterized registrations when behavior is the same and only inputs or expected results differ. Add each parameter set with a separate `СПараметрами...` call; every set becomes an isolated test and report item.
- Use `ЮТест.Варианты(...)`, `Добавить(...)`, `ДобавитьКомбинации(...)`, and `СписокВариантов()` when the test itself needs to build and iterate dynamic cases. This loop is not a substitute for parameterized registration when separate report items and failure isolation matter.
- Do not create a parameter matrix whose failures are harder to understand than separate scenarios.
- Build predicates through `ЮТест.Предикат()`. When storing or passing more than one predicate, call `Получить()` for an independent value because the fluent builder uses shared context.
- Verify that the predicate is supported by the consuming API; not every predicate works in every query or assertion mechanism.

## Test data and isolation

- Use `ЮТест.Данные()` as the public entry point for generated values, object builders, record sets, searches, files, and XDTO helpers. Do not bind tests to internal data modules.
- Prefer explicit builders and small reusable constructors over dependence on a large shared infobase. Use random data only when uniqueness matters and keep failures reproducible enough to diagnose.
- `ВТранзакции()` is for server tests. It covers the test and per-test hooks, not every module or suite hook.
- `УдалениеТестовыхДанных()` tracks objects created through the YAxUnit data API. It does not generally undo changes to existing objects and cannot guarantee cleanup of data created invisibly inside application code or unsupported client/server paths.
- Combine rollback and tracked deletion only when their scopes are understood. Never describe either mechanism as universal cleanup.
- Fixtures loaded from layouts or Markdown tables should make caches, replacements, types, object creation, and write behavior explicit when those choices affect the scenario.

## Hooks and contexts

- Lifecycle hooks exist before/after modules, test sets, and individual tests. Hooks may run in more than one client/server context; keep effects idempotent and correctly scoped.
- Use test, set, or module contexts only for data whose lifetime matches that level. Context state is not automatically synchronized between client and server.
- Prefer per-test preparation and cleanup. Promote state to a broader context only when the performance benefit is real and isolation remains deterministic.

## Common failure patterns

- Registration contains setup or application logic.
- One test depends on data, ordering, mocks, or context left by another test.
- Generic equality is used where a database or collection assertion would explain the failure better.
- A copied example calls an outdated or internal YAxUnit API.
- Transaction or tracked deletion is treated as complete rollback of all side effects.
- A client/server test assumes context values are synchronized automatically.
- Tests are edited through filesystem tools instead of the assigned EDT-MCP.
