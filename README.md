# 1С: Адаптер Kafka — Инструменты разработки

Вспомогательные скрипты и Docker-окружения для локальной разработки и тестирования [1С: Адаптер Kafka](https://github.com/ShadobaAI/kafka-adapter).

## Выберите задачу

Подробные инструкции находятся в README соответствующих каталогов.

| Задача | Что входит | Руководство |
|---|---|---|
| Настроить AI-инструменты | Установка, маршрутизация MCP, проверки | [ai](ai/README.md) |
| Собрать Docker-образы для CI | Профили `edtcli`, `ibcmd`, `client`, дистрибутивы и публикация | [.github/ci-images](.github/ci-images/README.md) |
| Настроить сборку релизов | GitHub Actions, сборка CF/CFE, упаковка EDT/XML | [.github](.github/README_CI.md) |
| Запустить Kafka и отправить тестовые сообщения | Два узла KRaft, ACL, Kafka UI, Schema Registry, генератор нагрузки | [kafka](kafka/README.md) |
| Настроить логирование через ELK | Elasticsearch, Logstash, Kibana | [elk](elk/README.md) |
| Настроить логирование через OpenSearch | OpenSearch, Dashboards, Fluent Bit | [opensearch](opensearch/README.md) |
| Запустить MS SQL Server | Локальный сервер и утилитарные SQL-скрипты | [mssql](mssql/README.md) |
| Настроить анализ BSL-кода | SonarQube, BSL-плагин, runner, обслуживание и восстановление | [sonarqube](sonarqube/README.md) |
| Преобразовать или просмотреть AsyncAPI | Генерация XSD для XDTO и просмотр спецификации в Confluence | [xdto](xdto/README.md) |

## Как пользоваться инструкциями

- Выберите нужный компонент в таблице и откройте его README.
- Рабочий каталог для команд указан в каждом руководстве. Корень репозитория `tools` и корень workspace Kafka — разные каталоги.
- Требования, адреса сервисов, параметры и устранение ошибок описаны рядом с компонентом.
- Общие команды запуска, просмотра логов и управления Docker собраны в [справочнике Docker](docs/docker.md).

## Лицензия

Проект распространяется под лицензией [Apache License 2.0](LICENSE).

**Разрешается:** использование, модификация и распространение — в том числе в коммерческих проектах — без ограничений.
