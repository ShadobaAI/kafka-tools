# Requirements for a 1C change

Select once the target or proposed artifact is understood, before choosing a solution or judging compliance. Use artifact invariants + operation + mechanisms, not just words in the request. For design select only decision-relevant requirements; for creation/full review consider the entire requested artifact; for a local change consider the changed part and enclosing invariants, not unrelated legacy code.

## Selection and verification

- Match all applicable rows below, plus the specialized artifact skill (for example $yaxunit-tests). An absent row is not an exemption: resolve uncovered mechanisms through $1c-standards before the dependent decision. Do not search again when exact evidence already covers the question.
- Check role/context, enclosing structure, contracts and effects as applicable to scope. A method-only read is insufficient when placement or module context matters; obtain the narrow enclosing outline, not the whole module by default.
- Treat a minimal example as an illustration of its mechanism, not a complete artifact template or an exception to other applicable rules.
- Retain a compact association: requirement/source and completeness -> affected decision/construct -> passed, violated or unresolved. Exclude a candidate only with an applicability reason. No separate file or exhaustive final checklist is required.
- Before delivery/apply, check the actual proposal against this association. After writing, check the result, not just tool success. Mandatory violations/unresolved requirements block the dependent outcome; recommendations retain their stated strength. Diagnostics/tests do not prove all normative checks.
- When scope changes, add only new requirements and invalidate only affected checks. Reuse unchanged source evidence while current; a code edit alone does not invalidate the text of a standard. Report material deviations and verification gaps.

## Retrieval contract

Document keys below expand to `corporate:work:<key>:overview`. Text after `/` is the exact `heading` for `v8std_get_section`; semicolons separate headings.

- Select the union of matching rows. Fetch each section once. When most of a short document is needed, use its complete compact body via `v8std_get_summary(body_limit=6000)`; it subsumes all sections.
- Evidence requires `found=true` and `body_truncated=false`. A summary is a bounded body, not proof that omitted text is irrelevant. If a section cannot be returned, a complete `v8std_get_page` of the same document is valid; another source is not.
- Fetch general IDs with `v8std_get_page`, or a self-contained exact section including applicable conditions/exceptions. Follow required normative dependencies for the affected mechanism; background/example links do not require recursive loading.
- Use $1c-standards to resolve uncovered applicability; a resolved selection needs no repeated search. Ranked `v8std_get_requirements_for_context` candidates do not prove exhaustive coverage.

## Corporate selectors

| Affected construct | Document / exact headings |
|---|---|
| Any BSL, query text or documenting comment | `bsl-change-policy` (whole) |
| Executable BSL | `bsl-type-transparency / Общий принцип`; `bsl-formatting / Длина строки; Операторы и этапы`; `bsl-readability / Временный код` |
| New method or affected parameters/signature/documentation | `bsl-type-transparency / Контракты методов`; `bsl-readability / Параметры` |
| Local assignment/type/lifetime | `bsl-type-transparency / Локальные переменные` |
| Module variable | `bsl-type-transparency / Переменные модуля` |
| Structure/collection/element types | `bsl-type-transparency / Структуры и коллекции` |
| Value table/tree, columns, data constructor | `bsl-type-transparency / Табличные данные и конструкторы` |
| Temporary storage/universal container result | `bsl-type-transparency / Универсальные контейнеры` |
| New module or strict-types directive | `bsl-type-transparency / Строгая типизация` |
| Branches, loops, exits, boolean conditions | `bsl-readability / Поток управления; Булевы условия`; `bsl-formatting / Многострочные блоки` |
| Add/split/restructure a method | `bsl-readability / Границы метода`; `module-organization / Области` |
| Comments/TODO/FIXME | `bsl-readability / Комментарии; Временный код`; `bsl-formatting / Длина строки` |
| Literal values | `bsl-readability / Литералы` |
| Function result/output parameter | `bsl-readability / Результат функции`; `bsl-type-transparency / Контракты методов` |
| Multiline parameter/argument list | `bsl-formatting / Параметры` |
| Module creation, placement/regions or structural review | `module-organization / Области` |
| Export contract | `module-organization / Экспорт` |
| Form client/server interaction | `module-organization / Клиент-серверное взаимодействие` |
| Query text/fields/parameters | `query-conventions / Параметры и поля; Форматирование; Установка параметров` |
| Temporary query tables | `query-conventions / Временные таблицы` |
| Existence-only query | `query-conventions / Проверка наличия` |
| Query result processing | `query-conventions / Обработка результата` |
| Query in a loop/batching | `query-conventions / Запросы в цикле` |
| Predefined values | `query-conventions / Предопределенные значения` |
| Catch/classify an exception | `error-reporting / Перехват; Классификация ошибки` |
| Suppress/log/present an error | `error-reporting / Представление и журнал; Классификация ошибки` |

## General standards

| Affected mechanism | IDs |
|---|---|
| BSL/query formatting | `std444` |
| New method or affected signature/documentation | `std453`, `std640`; `std641` for complex types; `std647` for naming |
| New method/module, placement/regions or structural review | `std455` |
| Common module creation/properties/context | `std469` |
| Export | `std453`, `std544` |
| Query text | `std437` |
| Existence-only query | `std438` |
| Query in a loop/batching | `std436` |
| Potentially unbounded query result | `std725` |
| Form client/server interaction | `std487`, `std636` |
| Exception handling | `std499` |
| Explicit transaction | `std783` |
| Files, streams, resource lifetime | `std542` |
| Session/current time | `std643` |
| Predefined values | `std443`, `std697` |
| Privileged mode / full-access common module | `std485` / `std469`, `std488` |
| Query uses ВЫБРАТЬ РАЗРЕШЕННЫЕ | `std415`, `std437`, `std444` |
| Localized/technical text | applicable `std761`, `std762`, `std764`, `std765` |

Inspect affected public-contract callers. Metadata-only changes skip the BSL baseline, but require standards for the actual object/properties.
