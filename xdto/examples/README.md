# Примеры обмена

[← Инструменты AsyncAPI](../README.md)

| Пример | Исходная спецификация | Схема XDTO |
|---|---|---|
| `asyncapi_example` | [YAML](asyncapi_example.yaml) | [XSD](asyncapi_example.xsd) |
| `kfk-test` | [YAML](kfk-test.yaml) | [XSD](kfk-test.xsd) |
| `kfk-unit` | [YAML](kfk-unit.yaml) | [XSD](kfk-unit.xsd) |

## Параметры генерации

Подготовьте [окружение генератора](../generator/README.md#окружение). Команды выполняются из корня репозитория `tools`.

```powershell
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\kfk-test.yaml .\xdto\examples\kfk-test.xsd -n http://v8.fsk.ru/kfk/test/1.0 --prefix 1c.
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\asyncapi_example.yaml .\xdto\examples\asyncapi_example.xsd -n http://v8.fsk.ru/example/kfk/1.0 --prefix 1c. --suffix .changed
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\kfk-unit.yaml .\xdto\examples\kfk-unit.xsd -n http://v8.fsk.ru/kfk/unit/1.0
```

У `kfk-test` удаляется префикс `1c.`. Адрес `1c.test-catalogs` даёт `TestCatalogs`. У `asyncapi_example` удаляются `1c.` и `.changed`, поэтому `1c.test-document.changed` даёт `TestDocument`. В `kfk-unit` имена берутся из `components.schemas`, поскольку в примере отсутствуют каналы.

Все три XSD сформированы текущим генератором с приведёнными параметрами и проверены через XMLSchema. Исходные YAML сохранены без изменения.

Проверка воспроизводимости этих XSD включена в test_generator.py. Для небольшого отдельного примера см. [supported-example.yaml](../generator/supported-example.yaml).
