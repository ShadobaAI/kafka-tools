# OpenSearch — логирование истории обмена

[← Все инструменты](../README.md)

> Команды выполняются из каталога `tools/opensearch`. Пути к файлам в описаниях указаны относительно корня репозитория `tools`, если не оговорено иное.

Альтернативный стек логирования на базе OpenSearch с агрегатором Fluent Bit.

```
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| OpenSearch | http://localhost:9201 |
| OpenSearch Dashboards | http://localhost:5602 |
| Fluent Bit (HTTP input) | http://localhost:9880 |

Конфигурация — `opensearch/config/`.
