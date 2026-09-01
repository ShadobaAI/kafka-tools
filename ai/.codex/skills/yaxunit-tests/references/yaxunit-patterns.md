# YAxUnit Authoring Patterns

These are stable decision rules, not a substitute for checking the installed core when an API detail is uncertain.

Reuse an API signature or behavior already confirmed in the installed core or by a successful focused runtime test in this session. Do not search for its implementation again unless a new semantic/context question or incompatible failure appears.

## Module structure and registration

- Put tests in non-borrowed common modules of the resolved test owner. The owner may be the YAxUnit core or a separate test extension; in Kafka it is the separate `unit` extension. Prefer one test module for one tested module or coherent behavior area.
- Create or materially restructure a test common module with the applicable std455 common-module structure, including only non-empty standard regions required by its actual exported and internal methods. Classify registration, test-only procedures, and helpers by their role; do not replace the standard top-level structure with arbitrary functional areas. Nest functional grouping inside the applicable standard region. If the mapping is unclear, consult `$1c-standards` once rather than guessing.
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
- For record presence/absence, count, field state, row-set correspondence, or another database-side predicate, default to `ЮТест.ОжидаетЧтоТаблицаБазы(...)` and the installed specialized table/database predicates. Do not write a `Новый Запрос` merely to read, count, or inspect rows when the specialized assertion API expresses the check.
- `ЮТест.ОжидаетЧто(...)` remains appropriate for ordinary values and objects. A query is also valid when it is itself an input to the tested public API; distinguish that from a query introduced only to avoid a specialized database assertion.
- In fluent property chains, property paths are evaluated from the original value passed to `ОжидаетЧто`; do not assume a previous `Свойство` changes the root for later paths.
- Prefer one cohesive expectation chain when it remains readable. Split unrelated requirements into separate assertions or tests.
- For a deliberate custom failure, use the public YAxUnit failure mechanism rather than raising an arbitrary application exception.

## Variants and predicates

- Prefer parameterized registrations when behavior is the same and only inputs or expected results differ. Add each parameter set with a separate `СПараметрами...` call; every set becomes an isolated test and report item.
- Use `ЮТест.Варианты(...)`, `Добавить(...)`, `ДобавитьКомбинации(...)`, and `СписокВариантов()` when the test itself needs to build and iterate dynamic cases. This loop is not a substitute for parameterized registration when separate report items and failure isolation matter.
- Do not create a parameter matrix whose failures are harder to understand than separate scenarios.
- Build predicates through `ЮТест.Предикат()`. When storing or passing more than one predicate, call `Получить()` for an independent value because the fluent builder uses shared context.
- Verify that the predicate is supported by the consuming API; not every predicate works in every query or assertion mechanism.

## Test data creation policy

- Use the public YAxUnit data API `ЮТест.Данные()` as the default mechanism for creating test data; do not call internal `ЮТТестовыеДанные` directly.
- Choose data in this order: an existing shared semantic project fixture when it represents the domain object/configuration the scenario needs; an installed YAxUnit builder/generator for scenario-specific data; low-level manual creation only as a justified fallback. In Kafka, distinguish shared fixtures from `кфк_т_ТестовыеДанные` from unique records and edge cases local to one test.
- For database objects, supported register records, document movements, XDTO, files, and other supported data, choose the narrowest suitable installed `ЮТест.Данные()` operation before direct platform or application creation APIs. Use `СоздатьЭлемент(...)`, `СоздатьДокумент(...)`, or `СоздатьГруппу(...)` when a minimally populated object/reference is sufficient; `КонструкторОбъекта(...)` when material attributes or write/post behavior must be controlled; `КонструкторДвижений(...)` for supported document movements/register records; and `КонструкторОбъектаXDTO(...)` for XDTO data. Use the public random-value generators for incidental values when a builder fixture operation is not the better fit. Confirm exact unfamiliar signatures or capability against the installed core instead of inventing them.
- Set behavior-material values explicitly with builder setters such as `Установить(...)` or `УстановитьРеквизиты(...)`. Generate incidental, technical, mandatory, uniqueness-only, or otherwise irrelevant values with the suitable installed operation: `Фикция(...)`, `ФикцияРеквизитов(...)`, `ФикцияОбязательныхПолей()`, `ФикцияНезаполненных()`, `ФикцияНезаполненныхИсключая(...)`, or a public random-value generator. Do not require every fixture method in one chain, and do not make random/generated values the expected behavior when the test depends on their exact value.
- Do not manually create/write fixtures with `СоздатьНаборЗаписей()`, `Добавить()` to a record set, direct object creation/write, invented technical keys, or manual mandatory-field initialization when an installed YAxUnit builder covers the scenario. Low-level setup is permitted only when that API is under test, the installed builder lacks the required structure/write mode, or exact low-level write semantics are material; establish the limitation from installed-core or runtime evidence and keep the reason concise.
- Choose each fixture value by its role in the scenario, not by the field name. When the exact value affects an input contract, branch, assertion, or observable behavior, set a deterministic value valid for the declared type and domain contract. When it is incidental setup, generate or fill it through the suitable public YAxUnit data operation. Do not invent arbitrary literals solely to satisfy write or mandatory-field requirements.
- Prefer builders and small reusable constructors over dependence on a large shared infobase. Use generated uniqueness only where needed and keep failures deterministic enough to diagnose. Do not test the builder instead of product behavior.

## Isolation

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
- A hand-written query only inspects/counts database rows although YAxUnit database assertions express the same check.
- `ЮТест.ОжидаетЧто(...)` is applied to an intermediate query result instead of asserting database state through the specialized API.
- Fixture data is created manually through platform record sets/objects although a YAxUnit builder supports the scenario.
- Arbitrary literals are invented for technical keys, mandatory fields, or uniqueness-only values instead of YAxUnit generation.
- Setup reimplements mandatory-field or record initialization already provided by a YAxUnit builder.
- Direct internal YAxUnit data modules are used instead of `ЮТест.Данные()`.
- A copied example calls an outdated or internal YAxUnit API.
- Transaction or tracked deletion is treated as complete rollback of all side effects.
- A client/server test assumes context values are synchronized automatically.
- Tests are edited through filesystem tools instead of the assigned EDT-MCP.
