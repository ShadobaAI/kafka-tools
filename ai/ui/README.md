# Vanessa UI CLI

Общие команды используют Node.js из PATH и локальный JSON-профиль. Рабочий каталог,
дерево репозиториев и EDT не участвуют в разрешении путей. Runtime — собранная
Vanessa `.epf` либо встроенная обработка, явно указанная в профиле;
upstream checkout при работе не нужен.
CLI не скачивает runtime, не устанавливает расширения и не изменяет базы.
Для managed bundle задайте `runtime.manifest`: путь к JSON manifest относительно
профиля. Он содержит version=1, product, release, source.url/source.sha256 и files
с path/sha256. Файлы разрешаются от manifest; выход за каталог bundle запрещён.
EPF должен однозначно совпасть с entry и его SHA-256. Проверка не меняет runtime.

Скопируйте `profile.example.json` в локальный нетрекаемый файл, заполните фактические
пути, базу менеджера, базу и имя TestClient, свободный loopback endpoint.
`9876` — пример, занятость проверяется при запуске. Все относительные пути считаются
от JSON-профиля. Для серверной базы используйте
`{"type":"server","server":"host","database":"database"}` вместо file/path.
Schema: `profile.schema.json`; неизвестные поля и credentials отклоняются.
Пароли не входят в профиль, аргументы CLI или сохранённое состояние.
Используйте существующую аутентификацию платформы.
`manager.interface` и `client.interface` принимают `"taxi"` (это также default).
Менеджер всегда запускается с `/iTaxi`. Bootstrap создаёт TestClient-профиль с
`additional_parameters: "/iTaxi"`; перед connect проверяется наличие этого флага
и отсутствие несовместимого `/itdi`. Другой интерфейс и непроверенные параметры
существующего TestClient-профиля дают ошибку до подключения.
Для явного имени пользователя допустим `manager.userEnv: "VANESSA_UI_USER"`:
значение берётся только из переменной среды для `/N`, не сохраняется в profile,
state или вывод. Password-аргументы CLI не поддерживаются.
`client.userEnv` задаёт такой же указатель для TestClient: setup передаёт `/N` из
среды только в MCP-вызов создания профиля. Значения не входят в локальные JSON-файлы
комплекта и фильтруются в выводе `/N`/`/P`; сама таблица профилей Vanessa содержит
параметры запуска клиента. `client.computerName` по умолчанию `localhost`.
Встроенная обработка задаётся `runtime.navigationUrl: "e1cib/app/Обработка.VanessaAutomationsingle"`
вместо `runtime.epf`. Для неё `/URL` заменяет `/Execute`; внешний EPF и manifest
не требуются, версия проверяется по живому runtime.

Скопируйте `interactive.example.json` рядом с профилем как `interactive.local.json`.
Добавляйте только нужные настройки проекта. Обязательно сохраняйте `ВыполнитьСценарии`
и `ЗавершитьРаботуСистемы` равными false, VanessaExt и Vanessa Editor — true.
CI VAParams с автоматическим выполнением/выходом отклоняется.
Перед запуском CLI пишет effective `interactive.json` в stateDir: абсолютные
КаталогПроекта/КаталогФич и подкаталоги results для JUnit, Allure, скриншотов,
явные interactive-флаги. Исходный paramsFile сохраняется. Без paramsFile используются
те же безопасные настройки. Загрузка конкретного feature и выбор сценария выполняются
явными MCP-вызовами по фактическим схемам, не режимом all.

Команды выполняются из любого каталога; пример абсолютного пути к CLI:

```powershell
node C:/Toolkit/ai/ui/vanessa.mjs configure --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs start --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs setup --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs connect --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs doctor --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs run --profile C:/MyProject/.local/ui.json --feature features/smoke.feature --scenario "Exact scenario name"
node C:/Toolkit/ai/ui/vanessa.mjs list --profile C:/MyProject/.local/ui.json
node C:/Toolkit/ai/ui/vanessa.mjs call --profile C:/MyProject/.local/ui.json --tool get_environment_data
node C:/Toolkit/ai/ui/vanessa.mjs call --profile C:/MyProject/.local/ui.json --tool actual_tool_name --arguments-file C:/MyProject/.local/arguments.json
```

`vanessa.cmd` передаёт те же аргументы без паузы. `configure` печатает TOML-snippet
для секции `mcp_servers.<serverName>` в конфигурации проекта. Он не перезаписывает
существующую конфигурацию. При существующей одноимённой секции сверьте её с выводом;
не добавляйте дубликат. Имя по умолчанию `vanessa`. После изменения подключений
переподключите MCP или перезапустите клиент. `list`/`call` работают через отдельную
Streamable HTTP сессию уже сейчас, без обновления списка инструментов текущего чата.
`list` получает все страницы с фактическими `inputSchema`. `call` передаёт JSON
без преобразования имён и подбора параметров. Сервер проверяет полную schema.

`start` запускает только менеджер командой
`ENTERPRISE /TESTMANAGER /iTaxi /IBConnectionString ... /Execute <epf> /C "runMcp;mcpPort=<port>;UseEditor;WorkspaceRoot=<project>;VAParams=<effective-params>"`.
Документированная загрузка VAParams без StartFeaturePlayer не выполняет сценарии.
Интерактивный менеджер запускается через `Start-Process -WindowStyle Normal`,
чтобы его окно было доступно пользователю; служебный PowerShell helper скрыт.
Менеджер повторно не
запускается, если сохранённые PID, время создания и executable совпадают. Чужой
занятый endpoint не присваивается. CLI не закрывает процессы и окна.
Кавычки внутри `/IBConnectionString` удваиваются по контракту платформы.
Каждый новый запуск получает собственный `<stateDir>/startup-<uuid>.log` через `/Out`.
Путь сохраняется в owner.startupLog и возвращается командой start, включая diagnostic
hint при неопределённом исходе. Старые логи не удаляются и не перезаписываются:
это исключает конфликт с дескриптором старого сеанса или crash dumper.

Состояние по умолчанию — `.vanessa/<id>-<hash-absolute-profile-path>` рядом с профилем;
явный `stateDir` должен принадлежать одному профилю. Временные блокировки endpoint и
TestClient сериализуют команды разных профилей. При неопределённом результате
запуска или мутации проверьте фактическое состояние до нового вызова. Автоповторов
мутаций нет. Нет команд stop/kill/restore/удаления данных.

`doctor` проверяет локальные файлы, initialize, полный tools/list и контрольные
get_environment_data/get_vanessa_automation_state/manage_test_client_profiles.
`connect` — отдельный bootstrap: проверяет базу менеджера и компоненты,
единственный совпадающий профиль клиента и отсутствие активного сценария/записи,
затем подключает только этот профиль через manage_test_client и повторяет doctor.
Он не отключает уже подключённый другой клиент. Готовность требует совпадающей базы
и имени подключённого клиента и активного VAExtension с установленной версией.
`setup` дополнительно создаёт отсутствующий профиль только с точными name/infobase
выбранной конфигурации, после проверки менеджера и idle-состояния; потом перечитывает
профили и выполняет connect. Несовпадающий существующий профиль не перезаписывается.
Схема actual tools/list проверяется перед каждой мутацией.
После той же проверки setup может исправить только computer_name у выбранного
совпадающего профиля. Он перечитывает состояние; уже подключённый клиент повторно
не запускается. Ошибка отдельного UI-инструмента остаётся ошибкой этого инструмента
и требует собственной проверки после исправления настройки.
Успех транспорта не означает
готовность базы, TestClient или расширений. Подтверждён wire contract Vanessa
Automation Single 1.2.043.45 / MCP 1.31: окружение, состояние, профили, editor,
расширения и процессы ОС. Неизвестная версия/структура даёт `unverified` с ненулевым кодом.
Отдельный get_editor_state(includeContent:false) доказывает доступность snapshot,
который может быть cached при выключенном редакторе. Поэтому doctor честно сообщает
editorEnabled:unverified. Функциональная готовность редактора подтверждается только
успешным open_feature_file внутри run.
Строка базы из настроек профиля не доказывает базу работающего клиента:
readiness требует точного подключённого имени из state и полной глобальной выборки
get_process_list_os по `/TESTCLIENT`, содержащей ровно один процесс. Его фактические
`/S`, `/F` либо `/IBConnectionString`, `/iTaxi`, `-TPort` и пользователь сверяются
с профилем. Несколько TestClient, неполный ответ или неизвестная командная строка
дают unverified. Это консервативная проверка локального интерактивного контура.
`ready` имеет scope environment_and_test_client; наличие нужной операции и её
actual schema проверяются перед вызовом. Оно не означает успешный прогон сценария.
Поддерживается только локальный TestClient: computerName должен быть localhost,
127.0.0.1, ::1 либо фактическим именем текущего компьютера. Удалённые профили
отклоняются до управления клиентом. Блокировка и persistent claim основаны на базе,
без имени профиля: разные имена одной базы не создают независимые UI-цепочки.

`run` выполняет ровно один явно указанный сценарий в одной блокировке и MCP-сессии:
полный initial doctor → open_feature_file → load_features(path) → check_syntax → select_scenario →
проверка выбора через get_editor_state → run_scenario(mode:selected) → get_test_results.
Относительный feature считается от projectRoot. Явный файл должен находиться внутри
projectRoot либо configured features; это позволяет запускать временную копию в
локальном ignored-каталоге проекта. Выход за оба корня запрещён.
Ошибочный/неизвестный синтаксис, другой файл/сценарий, неоднозначный выбор или timeout
останавливают цепочку до следующего действия. Ответ содержит исходные отчёты,
SHA-256 feature, имя сценария, время и runtime version. `completed` означает
завершение вызовов; результат теста оценивается по get_test_results.
Повторная загрузка обязательна даже для уже открытой вкладки. Перед run содержимое
get_editor_state(includeContent:true) сравнивается с feature на диске, нормализуя
только UTF-8 BOM и CRLF→LF. Пробелы и пустые строки не обрезаются. Неоднозначные
Markdown fences или старый буфер блокируют выполнение; receipt включает оба hash.

В MCP 1.31 активный редактор может возвращать из get_vanessa_automation_state только
«В редактор был загружен фича файл…». Эта фраза не доказывает idle, connection или
recording=false, в том числе после выполнения сценария. Новый doctor/run в таком
состоянии fail-closed. Кнопка «Перейти в дерево шагов» фактически выключает редактор:
после неё полный state доступен, но следующий open_feature_file может вернуть
Editor отключен. Для автономного повторного цикла используйте явный протокол:

```powershell
node C:/Toolkit/ai/ui/vanessa.mjs run --profile C:/MyProject/.local/ui.json --feature .local/repair.feature --scenario "Exact scenario name" --editor-transition
```

Команда проверяет полный baseline, удерживает блокировку/HTTP-сессию и печатает одну
строку JSON status=awaiting_editor_enable. Затем агент отдельным computer-use
инструментом выполняет наблюдаемое действие «Перейти в Vanessa Editor» у нужного
менеджера и подаёт в stdin ровно одну строку `{"action":"continue"}`. Никакие
произвольные команды stdin не принимаются. Ожидание ограничено 60 секундами и остатком
общей MCP-сессии; для UI-перехода задайте limits.timeoutMs=120000. Неверный ввод, EOF
или timeout завершают цепочку до open_feature_file. stdin должен оставаться открытым
(например, управляемая PTY). Затем реальный успешный open подтверждает enabled.
Progress JSON и итоговый JSON являются двумя отдельными сообщениями stdout.
CLI не угадывает координаты/внутренний callback и не хранит выведенный из ранней
фразы idle-receipt. Без флага исходный run подходит для свежего состояния, где
полный state доступен при уже включённом редакторе.
Внутри одного run исходная полная readiness сохраняется через документированные
действия только с редактором; повторной ложной проверки state после открытия нет.
Чтение данных окружения, состояния, результатов, списка окон и
`manage_test_client_profiles` с `action: "get_list"` доступно для исследования.
Другие действия этого инструмента требуют полной готовности.
Запись действий, начатая CLI в принадлежащем профилю процессе менеджера,
получает локальный token: profile/endpoint/process-session/runtime version.
Он разрешает действия в собственной активной записи и её stop между вызовами CLI.
Чужая запись, смена процесса или неопределённый результат блокируют зависимые действия.
Фактически наблюдённое idle-состояние завершает прежний active token. Для marker
starting/indeterminate сначала прочитайте состояние через discovery и проверьте
процесс менеджера; после подтверждённого завершения записи статус локального
recording.json можно вручную установить в idle. Автоматического продолжения после
неопределённой мутации нет.
Для внешнего менеджера без проверенного process-session запись не присваивается;
проверенные действия с UI доступны по обычному readiness.
После аварийного завершения CLI stale lock удаляют вручную только после проверки,
что операция завершена; автоматическое присваивание чужой блокировки запрещено.
Профиль ограничивает всю сессию 30 секундами и 1 MiB по умолчанию;
`limits.timeoutMs` допускает 100–120000, `limits.maxBytes` — 1024–8388608.
Вывод JSON фильтрует именованные credentials и распространённые password/token
поля. Не передавайте credentials в произвольных текстовых аргументах инструментов.

Узкая проверка из корня репозитория tools (без 1С и сети вне loopback):

```powershell
node ai/tests/test-vanessa-ui.mjs
node --check ai/ui/profile.mjs
node --check ai/ui/mcp.mjs
node --check ai/ui/runtime.mjs
node --check ai/ui/readiness.mjs
node --check ai/ui/recording.mjs
node --check ai/ui/runtime-contract.mjs
node --check ai/ui/run.mjs
node --check ai/ui/transition.mjs
node --check ai/ui/vanessa.mjs
```

Контракт запуска проверен по upstream `docs/AI/index.md` и
`docs/CommandSetting/CommandSetting.md` на этапе реализации. Фактическая версия EPF
и совместимость расширений требуют live doctor/приёмки выбранного профиля.
