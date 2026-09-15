# Примеры обмена

[← Инструменты AsyncAPI](../README.md)

Здесь находятся пары YAML/XSD: `asyncapi_example`, `kfk-test` и `kfk-unit`.

## Параметры генерации

Команды выполняются из корня репозитория `tools`.

```powershell
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\kfk-test.yaml .\xdto\examples\kfk-test.xsd -n http://v8.fsk.ru/kfk/test/1.0 --prefix 1c.
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\asyncapi_example.yaml .\xdto\examples\asyncapi_example.xsd -n http://v8.fsk.ru/example/kfk/1.0 --prefix 1c. --suffix .changed
.\xdto\.venv\Scripts\python.exe .\xdto\generator\asyncapi2xsd.py .\xdto\examples\kfk-unit.yaml .\xdto\examples\kfk-unit.xsd -n http://v8.fsk.ru/kfk/unit/1.0
```

У `kfk-test` адреса начинаются с `1c.`, постфикс отсутствует; например, `1c.test-catalog` даёт `TestCatalog`. У `asyncapi_example` удаляются `1c.` и `.changed`; `1c.test-document.changed` даёт `TestDocument`. В `kfk-unit` каналы отсутствуют: префикс и постфикс не применяются, имена берутся из schemas.

Все три XSD сформированы текущим генератором с приведёнными параметрами и проверены через XMLSchema. Исходные YAML сохранены без изменения.

Проверка воспроизводимости этих XSD включена в test_generator.py. Для небольшого отдельного примера см. [supported-example.yaml](../generator/supported-example.yaml).
