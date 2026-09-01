# YAxUnit Authoring Patterns

These are stable decision rules, not a substitute for checking the installed core when an API detail is uncertain.

Reuse an API signature or behavior already confirmed in the installed core or by a successful focused runtime test in this session. Do not search for its implementation again unless a new semantic/context question or incompatible failure appears.

## Module structure and registration

- Put tests in non-borrowed common modules of the resolved test owner. The owner may be the YAxUnit core or a separate test extension; in Kafka it is the separate `unit` extension. Default to one test common module for one tested object module; combine targets only when one coherent behavior area cannot be named or maintained meaningfully as separate modules.
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

## Helper extraction in tests

Apply the general `$1c-code-change` method-extraction gate. In tests, keep the arrange-act-assert flow, tested action, and decisive expectations visible. A helper is justified for a reusable semantic fixture, repeated non-trivial setup/assertion contract, complex fluent construction, or explicit interaction boundary; prefer a local variable, compact chain, or parameterized registration when it expresses the scenario directly. Name the helper by the specific domain/test concept and outcome, not generic mechanics such as `ПодготовитьДанные`, `СоздатьОбъект`, or `ПроверитьРезультат`.

## Naming and reports

- Name a test common module as `<project test namespace><object-type prefix><checked object name><module-type suffix when applicable>`. In Kafka, keep `кфк_т_` as the project namespace before the YAxUnit descriptor: for example, `кфк_т_ОМ_<ИмяОбщегоМодуля>` or `кфк_т_РС_<ИмяРегистра>_НЗ`. A generic category/container name such as `кфк_т_РегистрыСведений` is insufficient when the tests target a specific register or its module.
- Use the established object-type prefix and module suffix mapping. Common-module tests have no module suffix; object, manager, and record-set modules use `_МО`, `_ММ`, and `_НЗ` respectively. Resolve other object-type prefixes from the established project/core mapping instead of inventing or omitting them.
- Test-set representation: `Тип объекта ИмяОбъекта. [Тип модуля.] ИмяМетода()`.
- Test procedure: `ИмяМетода_Сценарий`.
- Test representation: `ИмяМетода(). Описание ожидаемого поведения`.
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

### Semantic object-fill gate

Before assigning object attributes or table-part rows, derive the smallest semantic model required by the scenario from the tested behavior, metadata contract, and established domain fixtures:

- Treat a value as material when it controls a branch/result, makes the object a valid domain state, links the object to another fixture, participates in grouping/order/uniqueness/totals, or establishes the intended boundary or negative condition. A field can be material even when it is not asserted directly.
- Keep related values coherent across the object graph: header attributes, references, table-part rows, register dimensions/resources, registrar/period, statuses, quantities, prices, amounts, and other dependent values must describe one meaningful scenario rather than individually type-correct random data.
- Design table parts from behavior: choose row count, order, duplicates, differing values, cross-row relationships, and totals because they exercise the scenario. Do not add one arbitrary row merely because the table part must be non-empty.
- For a negative or boundary test, violate only the intended invariant while keeping unrelated data valid, so the observed failure has one explainable cause.
- Generate only truly incidental leaf values. Do not independently fake references or row attributes when their identity or relationship affects the scenario. When significance is unclear, inspect the exact consumer/metadata constraint instead of inferring semantics from a field name or satisfying write validation with arbitrary literals.

### Object-builder generation pattern

Apply this pattern when `КонструкторОбъекта(...)` is the suitable operation:

1. Choose the required final state and return value before building the chain: persisted reference/object, posted document, recorded register data with continued chaining, unrecorded object, or data structure only.
2. Start from `ЮТест.Данные().КонструкторОбъекта("<ВидМетаданных>.<ИмяОбъекта>")` using the installed metadata-name form.
3. Apply the semantic object-fill gate, then choose the setter from the data already required by the scenario. Use `УстановитьРеквизиты(Значения)` when a compatible `Структура` already exists as scenario input, result, or fixture and several of its intended fields map directly to attributes of the current object or table-part row. Do not create a temporary collection solely to call `УстановитьРеквизиты(...)`; when no suitable structure already exists, keep clear direct `Установить(...)` calls. Also use `Установить(...)` for a single attribute, a clear per-field calculation or conversion, or selective mapping from a source with extra fields. Conversely, do not expand one already suitable structure into a chain that merely copies its fields one by one. Build each table-part row for its scenario role through `ТабличнаяЧасть(...)` and `ДобавитьСтроку(...)`; call `Объект()` before returning from a table-part row to object attributes.
4. Generate a technical, mandatory, uniqueness-only, or other value through the narrowest suitable `Фикция(...)`, `ФикцияРеквизитов(...)`, `ФикцияОбязательныхПолей()`, `ФикцияНезаполненных(...)`, or `ФикцияНезаполненныхИсключая(...)` only after the semantic object-fill gate classifies that value as truly incidental. Set every material value explicitly regardless of its field category. Ensure explicit material values win: apply them after broad generation, or set them first and use an operation that fills only unfilled attributes. Generated reference values may create related objects; account for their isolation and cleanup.
5. Finish with exactly the terminal that expresses the scenario:
   - `Записать(...)` for a persisted object/reference;
   - `Провести(...)` when document posting is material;
   - `ДобавитьЗапись(...)` when the supported record must be written while the fluent builder remains available, notably for an independent information-register record;
   - `НовыйОбъект()` when the test needs an object without a database write;
   - `ДанныеОбъекта()` or `ДанныеСтроки()` when the test needs prepared structural data rather than persistence.
6. Treat explicit reference identity, returning an object instead of a reference, and exchange-load write mode as scenario semantics, not defaults. Use `УстановитьСсылкуНового(...)`, terminal flags, or related options only when the behavior requires them and confirm an unfamiliar signature in the installed core.

Minimal shape:

```bsl
Результат = ЮТест.Данные()
	.КонструкторОбъекта("<ВидМетаданных>.<ИмяОбъекта>")
	.ФикцияОбязательныхПолей()
	.Установить("<ЗначимыйРеквизит>", ЗначимоеЗначение)
	.Записать();
```

`ДобавитьЗапись(...)` and `НовыйОбъект()` do not reset the configured builder data. Reinitialize `КонструкторОбъекта(...)` before creating a logically different record/object; repeat a terminal on the same configured builder only when deliberate duplication is the scenario.

- Do not manually create/write fixtures with `СоздатьНаборЗаписей()`, `Добавить()` to a record set, direct object creation/write, invented technical keys, or manual mandatory-field initialization when an installed YAxUnit builder covers the scenario. Low-level setup is permitted only when that API is under test, the installed builder lacks the required structure/write mode, or exact low-level write semantics are material; establish the limitation from installed-core or runtime evidence and keep the reason concise.
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
- A single-use helper wraps an obvious expression/call or exists only to divide the test into more methods.
- A helper hides the tested action or decisive expectation without providing a reusable, stable, well-named contract.
- The test common-module name omits the tested object type, checked object name, or applicable module suffix, or uses only a generic object category.
- One test depends on data, ordering, mocks, or context left by another test.
- Generic equality is used where a database or collection assertion would explain the failure better.
- A hand-written query only inspects/counts database rows although YAxUnit database assertions express the same check.
- `ЮТест.ОжидаетЧто(...)` is applied to an intermediate query result instead of asserting database state through the specialized API.
- Fixture data is created manually through platform record sets/objects although a YAxUnit builder supports the scenario.
- A temporary collection is created solely to replace clear direct `Установить(...)` calls with `УстановитьРеквизиты(...)`.
- Several intended attributes are copied one by one through `Установить(...)` from one already prepared compatible `Структура`, although `УстановитьРеквизиты(...)` would express the same mapping without hiding transformations or assigning extra fields.
- An incidental technical, mandatory, or uniqueness-only value is filled with an arbitrary literal instead of suitable YAxUnit generation, or a material value from the same field categories is generated instead of being set explicitly.
- Individually valid generated attributes or references form a semantically inconsistent object graph.
- A table part has arbitrary row count/content/order or lacks the relationships needed to exercise the scenario.
- Setup reimplements mandatory-field or record initialization already provided by a YAxUnit builder.
- A builder chain ends with a terminal whose persistence, posting, return type, or continuation semantics do not match the scenario.
- `ДобавитьЗапись(...)` or `НовыйОбъект()` is repeated on one configured builder unintentionally, duplicating the same prepared data.
- Direct internal YAxUnit data modules are used instead of `ЮТест.Данные()`.
- A copied example calls an outdated or internal YAxUnit API.
- Transaction or tracked deletion is treated as complete rollback of all side effects.
- A client/server test assumes context values are synchronized automatically.
- Tests are edited through filesystem tools instead of the assigned EDT-MCP.
