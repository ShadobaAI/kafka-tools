# Установка OpenViking в Hyper-V ВМ с Ollama на GPU хоста

Физический Windows-хост запускает Ollama в Docker с NVIDIA GPU (например,
RTX 3060). Windows-ВМ запускает OpenViking в Docker и обращается к Ollama по сети.
Проброс GPU в Hyper-V ВМ для этой схемы не нужен.

Установщик уже поддерживает внешнюю Ollama через `-OllamaUrl`. Модели скачиваются
на физический хост; второй контейнер Ollama внутри ВМ не создаётся.

## 1. Подготовьте физический Windows-хост

Установите актуальный драйвер NVIDIA и Docker Desktop. Обновите WSL:

```powershell
wsl --update
```

В Docker Desktop включите **Settings → General → Use the WSL 2 based engine**
и используйте Linux containers. Для GPU в Docker Desktop на Windows требуется
WSL2 backend: [официальная документация Docker](https://docs.docker.com/desktop/features/gpu/).

## 2. Запустите Ollama на физическом хосте

Для i7-11700K, 32 ГБ RAM и RTX 3060 12 ГБ используйте
[compose.ollama-gpu.yaml](compose.ollama-gpu.yaml). Скопируйте файл на физический
хост и выполняйте команды из его каталога. Это стартовый профиль для текущих
`qwen3-embedding:0.6b` и `qwen3.5:4b`; фактическую скорость и размещение обеих
моделей необходимо проверить под нагрузкой.

Профиль использует GPU 0, допускает две загруженные модели, удерживает их 30 минут
и обрабатывает один запрос на модель одновременно. Контекст — 16384, KV cache —
`f16`, Flash Attention включён для эффективного использования памяти. Модели,
их квантование и содержимое документов не меняются. Повышать параллелизм заранее
не требуется: Git-синхронизатор отправляет документы последовательно.
Параметры описаны в [Ollama FAQ](https://docs.ollama.com/faq), подключение GPU —
в [Docker Compose GPU support](https://docs.docker.com/compose/how-tos/gpu-support/).

При **первом запуске без существующего контейнера**:

```powershell
docker volume create ollama-models
docker compose -f compose.ollama-gpu.yaml config --quiet
docker compose -f compose.ollama-gpu.yaml up -d
```

Модели сохраняются во внешнем volume `ollama-models`, имя которого не зависит
от каталога Compose. Внешний том не управляется жизненным циклом Compose.
Образ `latest` скачивается только при отсутствии локального образа; обычный запуск
не обновляет имеющуюся версию. Для воспроизводимого развёртывания можно закрепить
проверенный тег или digest вместо `latest`.

Если контейнер `ollama` уже существует, сначала проверьте **только подключения томов**:

```powershell
docker inspect ollama --format '{{json .Mounts}}'
```

Найдите подключение к `/root/.ollama`. Если это named volume с другим именем,
замените `volumes.ollama-models.name` в Compose на фактическое имя. Для bind mount
сохраните существующий путь хоста в подключении сервиса вместо named volume.
Если модели находятся только внутри контейнера, сначала перенесите их в постоянное
хранилище; этот профиль автоматически их не переносит.

Для перехода с прежнего `docker run`, после завершения индексации, сохраните
старый контейнер для отката (имя `ollama-before-compose` должно быть свободно):

```powershell
docker compose -f compose.ollama-gpu.yaml config --quiet
docker stop ollama
docker rename ollama ollama-before-compose
docker compose -f compose.ollama-gpu.yaml up -d
```

Старый контейнер и модели не удаляются. Не запускайте оба контейнера одновременно
с одним томом. Если Ollama уже управляется другим Compose-проектом, перенесите
настройки в его файл и пересоздайте сервис в том проекте вместо этой процедуры.
Последующие изменения этого профиля применяются командой
`docker compose -f compose.ollama-gpu.yaml up -d`.
Публикация порта нужна для доступа из ВМ; ограничьте доступ firewall, как описано ниже.

Скачайте обе модели:

```powershell
docker exec ollama ollama pull qwen3-embedding:0.6b
docker exec ollama ollama pull qwen3.5:4b
docker exec ollama ollama list
```

- `qwen3-embedding:0.6b` — векторные представления документов и поисковых запросов.
- `qwen3.5:4b` — семантические описания и краткие представления документов.

Проверьте генерацию и размещение модели на GPU:

```powershell
docker exec ollama ollama run qwen3.5:4b --think=false "Напиши только слово: работает"
docker exec ollama ollama ps
docker exec ollama nvidia-smi
```

В `ollama ps` для загруженной модели ожидается `100% GPU` в столбце `PROCESSOR`.
Это размещение модели, а не постоянная загрузка GPU на 100%.
`--think=false` отключает рассуждения в коротком тесте. Проверяйте `ollama ps`
сразу после генерации, пока модель ещё загружена.

## 3. Разрешите доступ только из ВМ

В PowerShell **внутри ВМ** определите IPv4 сетевого адаптера, через который
доступен физический хост:

```powershell
Get-NetIPConfiguration
```

На **физическом хосте**, в PowerShell **от имени администратора**, выполните
следующий блок и введите фактический IPv4 ВМ. Не вводите строку `<IP-ВМ>`:

```powershell
$ollamaVmAddress = [System.Net.IPAddress]::Parse((Read-Host "IPv4 виртуальной машины"))
New-NetFirewallRule `
  -DisplayName "Ollama API from Hyper-V VM" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 11434 `
  -RemoteAddress $ollamaVmAddress.IPAddressToString `
  -Profile Any
```

Правило создаётся один раз. При изменении IP ВМ обновите его адрес.
Локальный API Ollama не требует API-ключа; не открывайте порт всему Интернету.
Если ранее создано широкое разрешающее правило для этого порта, узкое правило
не отменяет его — проверьте существующие правила firewall.

## 4. Проверьте подключение из ВМ

Следующие команды используют имя физического хоста `iA11`. Если у вас другое
имя, замените его на доступное из ВМ имя или IP хоста:

```powershell
Test-NetConnection iA11 -Port 11434
(Invoke-RestMethod http://iA11:11434/api/tags).models | Select-Object name, size
```

Ожидаются `TcpTestSucceeded : True` и обе установленные модели.
При ошибке проверьте разрешение имени, IP ВМ в firewall, состояние контейнера
Ollama и публикацию порта `11434`. Адрес должен быть доступен также из Docker
внутри ВМ; установщик отдельно проверяет этот маршрут.

## 5. Запустите установщик в ВМ

В ВМ должен работать Docker Desktop с Linux containers и Docker Compose.
Откройте PowerShell в корне Kafka workspace и выполните:

```powershell
.\tools\ai\install.cmd -OllamaUrl http://iA11:11434
```

Префикс `.\` нужен для запуска файла из текущей папки в PowerShell.
Не добавляйте `-OpenVikingGpu`: GPU используется контейнером Ollama на хосте.

При сообщении `mode: external Ollama` подтвердите `y` на запрос
`Download/update the OpenViking image and connect to external Ollama?`.
Это загрузка/обновление образа OpenViking в ВМ; модели на хосте повторно
скачиваться не будут.

Установщик проверяет модели из Docker, запускает OpenViking, настраивает
учётную запись Kafka и синхронизирует документы из Git. Адрес Ollama сохраняется
для последующих запусков. Состояние и ключи находятся вне Git, по умолчанию
в `%USERPROFILE%\.codex\openviking-docker`; не публикуйте эти файлы.

## Сообщения и диагностика

| Сообщение | Значение / действие |
|---|---|
| GHCR `denied`, затем `Pulling the verified official ... image through Docker Hub` | Установщик использует Docker Hub с проверенным digest официального образа. Если этот pull завершился успешно, установка продолжается. |
| `Checking embedding and VLM inside Docker...` | Два настоящих запроса к Ollama. Таймаут каждого — до 10 минут. Надпись `on CPU` описывает допустимое ожидание и не определяет, где фактически выполняется модель; GPU проверяйте на хосте через `ollama ps`. |
| `Embedding and VLM requests passed.` | Обе модели успешно проверены из Docker в ВМ. |
| `Indexing N/M: ...` | Первый проход строит семантические описания и векторы. Он может быть длительным даже на GPU. Не запускайте вторую установку параллельно. |
| Повторная синхронизация с `writes: 0` | При неизменных Git-ревизиях, настройках и runtime используется существующий индекс. |
| HTTP 403 при Git reconciliation | Убедитесь, что запускаете актуальную версию toolkit: data API должен использовать отдельный tenant key, а не ROOT-ключ. Не отключайте авторизацию сервера. |

На физическом хосте:

```powershell
docker ps --filter name=ollama
docker exec ollama ollama ps
docker logs --tail 50 ollama
```

В ВМ (для стандартной папки состояния):

```powershell
docker compose -f "$env:USERPROFILE\.codex\openviking-docker\compose.json" ps
docker compose -f "$env:USERPROFILE\.codex\openviking-docker\compose.json" logs --tail 50 openviking
```

При собственном `-OpenVikingStateDir` используйте его путь к `compose.json`.
Подробности синхронизации и диагностики: [OpenViking README](README.md).
