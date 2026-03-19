# 1С: Адаптер Kafka — Инструменты разработки

Вспомогательные скрипты и Docker-окружения для локальной разработки и тестирования [1С: Адаптер Kafka](https://github.com/ShadobaAI/kafka-adapter).

## Состав репозитория

| Каталог | Назначение |
|---------|------------|
| `kafka/` | Apache Kafka — двухузловой кластер KRaft + Kafka UI |
| `kafka/scripts/` | Вспомогательные скрипты для тестирования Kafka |
| `elk/` | ELK-стек — Elasticsearch + Logstash + Kibana |
| `opensearch/` | Альтернатива ELK — OpenSearch + Dashboards + Fluent Bit |
| `mssql/` | MS SQL Server 2022 — скрипт запуска и утилитарные SQL-скрипты |
| `xdto/` | `asyncapi2xsd.py` — генератор XSD из AsyncAPI-спецификации |

---

## kafka

Двухузловой кластер Apache Kafka в режиме KRaft (без ZooKeeper) + веб-интерфейс Kafka UI.

```
cd kafka
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| Kafka node1 (внешний) | `localhost:29091` |
| Kafka node2 (внешний) | `localhost:29092` |
| Kafka UI | http://localhost:8081 |

Bootstrap-серверы для адаптера: `localhost:29091,localhost:29092`

### kafka/scripts/kafka_sender.py

Генератор нагрузки для тестирования адаптера — отправляет случайные JSON-сообщения в топики Kafka.

**Зависимости:** `pip install kafka-python`

Скрипт отправляет сообщения двух типов:

| Топик | Описание |
|-------|----------|
| `1c.test-register` | Сообщение регистра (событие, UUID, число, строка, дата, булево) |
| `1c.test-catalog` | Сообщение справочника (ref, наименование, перечисление, табличная часть) |

Параметры задаются в секции `data` внутри скрипта:

| Параметр | Описание |
|----------|----------|
| `total` | Количество сообщений |
| `speed` | Скорость (msg/sec); `0` — максимальная |
| `topic` | `"register"`, `"catalog"` или `None` (оба топика) |

```bash
python kafka/scripts/kafka_sender.py
```

---

## elk

ELK-стек для централизованного логирования истории обмена адаптера.

```
cd elk
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| Elasticsearch | http://localhost:9200 |
| Kibana | http://localhost:5601 |
| Logstash (HTTP input) | http://localhost:8082 |

Конфигурация Logstash — `elk/config/logstash.conf`.
Резервное копирование данных — `elk/backup.ps1`.

---

## opensearch

Альтернативный стек логирования на базе OpenSearch с агрегатором Fluent Bit.

```
cd opensearch
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| OpenSearch | http://localhost:9201 |
| OpenSearch Dashboards | http://localhost:5602 |
| Fluent Bit (HTTP input) | http://localhost:9880 |

Конфигурация — `opensearch/config/`.

---

## mssql

MS SQL Server 2022 с кириллической сортировкой (`Cyrillic_General_CI_AS`) и русской локалью.

```powershell
.\mssql\docker_run_mssql.ps1
```

| Параметр | Значение |
|----------|----------|
| Порт | `1433` |
| Логин | `sa` |
| Пароль | `Qwerty123!` |
| Сортировка | `Cyrillic_General_CI_AS` |
| Резервные копии (том) | `C:\docker-backups\mssql` |

Дополнительно в каталоге `mssql/`:
- `Очистка кэша.sql` — сброс кешей плана запросов и буферного пула;
- `Статистика индексов.sql` — анализ фрагментации индексов.

---

## xdto/asyncapi2xsd.py

Конвертирует схемы из [AsyncAPI YAML](https://studio.asyncapi.com/) в XSD для импорта в XDTO-пакет 1С.

**Зависимости:** `pip install pyyaml lxml`

### Использование

```
python asyncapi2xsd.py <input.yaml> <output.xsd> -n <namespace> [--prefix <prefix>] [--suffix <suffix>]
```

| Аргумент | Обязательный | Описание |
|----------|:---:|----------|
| `input` | да | Путь к AsyncAPI YAML |
| `output` | да | Путь к выходному XSD |
| `-n`, `--namespace` | да | `targetNamespace` генерируемой схемы |
| `--prefix` | нет | Префикс адреса канала, отрезаемый при формировании имени типа |
| `--suffix` | нет | Суффикс адреса канала, отрезаемый при формировании имени типа |

```bash
# Без strip-правил — имя типа берётся напрямую из адреса канала
python asyncapi2xsd.py spec.yaml out.xsd -n http://example.com/ns

# С prefix/suffix — crm.someObject.changed → SomeObject
python asyncapi2xsd.py spec.yaml out.xsd \
  -n http://example.com/ns \
  --prefix crm. \
  --suffix .changed
```

---

## Справочник команд Docker

### Запуск и остановка

| Команда | Описание |
|---------|----------|
| `docker compose up -d` | Поднять сервисы в фоне |
| `docker compose up -d --build` | Пересобрать образы и запустить |
| `docker compose down` | Остановить и удалить контейнеры и сети |
| `docker compose down -v` | То же + удалить тома |

### Логи и отладка

| Команда | Описание |
|---------|----------|
| `docker compose logs -f` | Поток логов всех сервисов |
| `docker compose logs -f <service>` | Логи конкретного сервиса |
| `docker compose exec <service> sh` | Shell внутри контейнера |

### Состояние окружения

| Команда | Описание |
|---------|----------|
| `docker ps` | Активные контейнеры |
| `docker ps -a` | Все контейнеры, включая остановленные |
| `docker images` | Локальные образы |

### Очистка

| Команда | Описание |
|---------|----------|
| `docker system prune -a --volumes` | Удалить неиспользуемые контейнеры, образы, кеш и тома |
| `docker volume prune` | Удалить неиспользуемые тома |

---

## Лицензия

Проект распространяется под лицензией MIT + Commons Clause.

**Разрешается:** свободное использование, модификация и внедрение в собственных и коммерческих решениях.

**Запрещается:** продажа подсистемы или её производных в качестве самостоятельного продукта.
