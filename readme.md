# 1С: Адаптер Kafka — Набор скриптов для разработки

Репозиторий со скриптами для запуска, обслуживания и локальной разработки адаптера «1С ↔ Kafka».  
Цель — быстрый старт, единообразие команд и минимум рутины.

## asyncapi2xsd.py

Конвертирует схемы из [AsyncAPI YAML](https://studio.asyncapi.com/) в XSD-файл для импорта в XDTO-пакет 1С.

**Зависимости:** `pip install pyyaml lxml`

### Использование

python asyncapi2xsd.py <input.yaml> <output.xsd> -n <namespace> [--prefix <prefix>] [--suffix <suffix>]



| Аргумент | Обязательный | Описание |
|----------|:---:|----------|
| `input` | да | Путь к AsyncAPI YAML |
| `output` | да | Путь к выходному XSD |
| `-n`, `--namespace` | да | `targetNamespace` генерируемой схемы |
| `--prefix` | нет | Префикс адреса канала, отрезаемый при формировании имени типа |
| `--suffix` | нет | Суффикс адреса канала, отрезаемый при формировании имени типа |

### Примеры

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

## Основные команды Docker

### Запуск и остановка
- `docker compose up -d` — поднимает сервисы в фоне.  
- `docker compose up -d --build` — пересобирает образы и стартует заново.  
- `docker compose down -v` — останавливает сервисы и удаляет контейнеры, сети и тома.

### Логи и отладка
- `docker compose logs -f` — поток логов всех сервисов  
  (`logs -f <service>` для конкретного).  
- `docker compose exec <service> sh` — интерактивный shell внутри контейнера.

### Состояние окружения
- `docker ps` — активные контейнеры.  
- `docker ps -a` — все контейнеры, включая остановленные.  
- `docker images` — локальные образы.

### Очистка
- `docker system prune -a --volumes` — удаление мусора: неиспользуемые контейнеры, образы, кеш и тома.  
- `docker volume prune` — чистка неиспользуемых томов.
