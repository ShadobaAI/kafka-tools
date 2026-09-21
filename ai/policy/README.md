# Детерминированный выбор требований

`registry.json` — версионированная миграция таблиц применимости из
`1c-code-change/references/requirements.md` и `$yaxunit-tests`. Каждая запись
возвращает точный ID стандарта, corporate-документ с заголовком или YAxUnit
pattern. Тексты норм здесь не копируются: их чтение и проверка полноты остаются
за `v8std`.

`detector.mjs` принимает уже полученное через назначенный EDT/code-index/BSL LS
доказательство, но никогда не читает файлы проекта. Текстовый признак подтверждает
только присутствие; отсутствие признака остаётся `unknown`, пока caller не передаст
обоснованную оценку `absent`. Для 13 критичных механизмов полнота detection
обязательна перед 1С selection и снова перед compliance. Противоречие между
оценкой `absent` и текстовым признаком блокирует выбор.

`selector.mjs` объединяет явные, классифицированные и подтверждённые механизмы,
добавляет логические следствия (например, `query_in_loop` подразумевает
`query_text`), дедуплицирует селекторы и вычисляет стабильный SHA-256 digest.
Неизвестный либо неразрешённый механизм блокирует выбор. Каждая строка registry
имеет явную `strength`. `std436` рекомендателен по полному тексту v8std с
допустимыми исключениями. Удалённые corporate-разделы заменены по таблице
`v8std/docs/corporate/work/README.md`; для запросов в цикле применяется
рекомендательный `std436`. Сила строки задаёт обязанность
проверки, а фактические условия и исключения берутся из полного текста v8std.
`validateCompliance` требует запись с целью и evidence для каждого выбранного
селектора; рекомендованное отклонение требует `reason`.
новый механизм или новая версия registry требует повторной выборки.

Локальный read-only stdio MCP:

```powershell
node .\tools\ai\policy\read-only-mcp.mjs
```

Он публикует `detect_1c_mechanisms`, `select_1c_requirements`,
`select_yaxunit_requirements` и `validate_compliance`. Не подменяйте им `v8std`: selector определяет *что*
читать, а нормативный текст и условия применения берутся по возвращённым
точным ID из `v8std`.

Для `select_yaxunit_requirements` MCP-схема массивов `mechanisms`,
`classifiedMechanisms` и `detectedMechanisms` содержит `items.enum` из
`registry.json` → `yaxunit.mechanisms`. Значения механизмов (например,
`test_module`) отличаются от ID документов (`yaxunit:patterns:test-module`).

## Контракт SPEC-0014

Версия MCP policy protocol — `2.0.0`; registry version не меняется, поскольку
применимость и сила требований сохранены. `validate_compliance` принимает
`phase: proposal | result` и возвращает phase также в ошибках. Для совместимости
пропущенная phase означает `proposal`; managed skills всегда передают её явно.
Ledger запрещает неизвестные поля, требует непустые `rule_id`, `selection_digest`,
`target`, `evidence` и статус `passed` для mandatory. Recommended допускает
`passed` либо `deviated` с непустым `reason`. Схема отвергает `compliant` и
`satisfied` до проверки применимости. Контекстные ограничения (сила селектора,
дубли строк, digest, изменившиеся механизмы) проверяет runtime.

`detect_1c_mechanisms` поддерживает `format: compact`: ответ `compact-v1` содержит
sourceRef и все 13 именованных `[mechanism, status, evidence]` оценок. Selection
и compliance принимают обе формы; исходная verbose остаётся default для старых
callers. Unknown, неполное покрытие и противоречия по-прежнему блокируют работу.
Compact — перенос полных оценок без повторных derived-массивов, не proof token,
кэш или доказательство свежести. Digest selection связывает применимость;
source/evidence остаются в запросе и проверяются отдельно.

L/M/H определяются консервативно в skill, без нового MCP и persistent state.
Низкий риск сокращает повторный detection/selection/retrieval только при
доказанно неизменной применимости; проверки proposal/result, EDT diagnostics,
concurrency и выбранные нормы обязательны. Изменение реального результата
требует новой оценки, а не механической замены sourceRef.

Installer уже копирует managed skills с backup/rollback. Его regression теперь
проверяет фактически опубликованную stdio schema и согласованность скопированных
skills с policy. Doctor выявляет mixed profile до признания установки готовой.
Обновлять MCP и skills следует одним запуском штатного installer и перезапуском
Codex; редактирование только файла MCP при старых skills не является rollout.

```powershell
node .\tools\ai\tests\test-policy-contract.mjs
node .\tools\ai\tests\test-orchestration.mjs
node .\tools\ai\tests\benchmark-orchestration.mjs
```

Benchmark использует frozen pre-change traces `tests/fixtures/orchestration-baseline.json`
и реальные policy functions с синтетическими ответами остальных authorities.
Считаются JSON bytes tool name/arguments и результата без transport envelope и
startup `tools/list`; это не billed tokens и не доказательство поведения LLM.
Пять сценариев одинаковы до/после: adapter, conversion, unit, reports и UI.
До изменения policy baseline создаётся однократно через `--capture-baseline`;
существующий baseline не перезаписывается. Legacy traces намеренно моделируют
наблюдавшиеся лишние retrieval/selection и guessing `compliant → satisfied → passed`.
Trace oracle проверяет разрешённые/запрещённые последовательности, но не является
исполняемым контроллером агента. Live-приёмка остаётся отдельной проверкой.

Проверка:

```powershell
node .\tools\ai\tests\test-policy.mjs
$env:V8STD_REPO='<path-to-v8std-checkout>'
node .\tools\ai\tests\test-policy.mjs
```

Вторая команда дополнительно сверяет все точные ID и corporate-заголовки с
исходным checkout `v8std`; значение пути задаётся пользователем среды.
Миграционные таблицы хранятся только в `ai/tests/legacy-*.md`, вне исполняемых
skills. До production cutover требуется проверить detection на реальном EDT
evidence, нормативную классификацию остальных смешанных правил, а также реальные
Codex integration tests. Штатный installer доставляет `kafka-policy` MCP и thin skills; фактическая
нормативная и live acceptance ещё не выполнена.
