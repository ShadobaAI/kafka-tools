# 1С: Адаптер Kafka — инструменты разработки

Стенды и инструменты для разработки, тестирования и выпуска [1С: Адаптера Kafka](https://github.com/ShadobaAI/kafka-adapter).

## Стенды

| Компонент | Назначение |
|---|---|
| [Kafka](kafka/README.md) | Два брокера KRaft, Kafka UI, Schema Registry и отправка тестовых сообщений |
| [MS SQL Server](mssql/README.md) | SQL Server 2022, MCP, диагностика и импорт Extended Events |
| [ELK](elk/README.md) | История обмена и импорт технологического журнала 1С в Elasticsearch |
| [OpenSearch](opensearch/README.md) | История обмена через Fluent Bit и OpenSearch Dashboards |
| [SonarQube](sonarqube/README.md) | Анализ BSL-кода, GitHub Actions runner и обслуживание стенда |
| [OpenViking и Ollama](openviking/README.md) | Индексация документации и запуск моделей на отдельной GPU-машине |

Каждое руководство указывает рабочий каталог. Общие команды запуска, проверки и остановки стендов собраны в [справочнике Docker](docs/docker.md).

## Инструменты разработки

| Компонент | Назначение |
|---|---|
| [CI/CD](.github/README.md) | Сборка CI-образов, выпуск CF/CFE и упаковка исходников EDT/XML через GitHub Actions |
| [Инструменты 1С](ones/README.md) | Настройки технологического журнала, публикация выгрузок `.dt` и экспорт YAxUnit |
| [AsyncAPI и XDTO](xdto/README.md) | Генерация XSD, примеры обмена и просмотр AsyncAPI в Confluence |

## Лицензия

Проект распространяется под лицензией [Apache License 2.0](LICENSE).
