# ELK — логирование истории обмена

[← Все инструменты](../README.md)

> Команды выполняются из каталога `tools/elk`. Пути к файлам в описаниях указаны относительно корня репозитория `tools`, если не оговорено иное.

ELK-стек для централизованного логирования истории обмена адаптера.

```
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| Elasticsearch | http://localhost:9200 |
| Kibana | http://localhost:5601 |
| Logstash (HTTP input) | http://localhost:8082 |
| Elasticsearch MCP (Streamable HTTP) | http://localhost:8080/mcp |

Конфигурация Logstash — `elk/config/logstash.conf`.
Резервное копирование данных — `elk/backup.ps1`.

MCP-сервер подключается к Elasticsearch через сеть Compose. Укажите адрес из таблицы в MCP-клиенте; проверка доступности — `http://localhost:8080/ping` (ответ `pong`). На хосте порт MCP доступен только через `127.0.0.1`. В этой конфигурации Elasticsearch и MCP работают без аутентификации.

[Elasticsearch MCP Server](https://github.com/elastic/mcp-server-elasticsearch) объявлен устаревшим и получает только критические обновления безопасности.
