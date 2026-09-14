# ELK — логирование истории обмена

[← Все инструменты](../readme.md)

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

Конфигурация Logstash — `elk/config/logstash.conf`.
Резервное копирование данных — `elk/backup.ps1`.
