# AsyncAPI: генерация XSD и просмотр спецификации

[← Все инструменты](../readme.md)

Выберите задачу: [получить XSD для 1С](#генерация-xsd) или [подключить просмотр в Confluence](#просмотр-в-confluence).

> Команды выполняются из корня репозитория `tools`. Пути в командах указаны относительно этого каталога.

## Генерация XSD

Конвертирует схемы из [AsyncAPI YAML](https://studio.asyncapi.com/) в XSD для импорта в XDTO-пакет 1С.

Требуется Python 3.10 или новее. Установка зависимостей:

```powershell
python -m pip install pyyaml lxml
```

### Использование

```powershell
python .\xdto\asyncapi2xsd.py <input.yaml> <output.xsd> -n <namespace> [--prefix <prefix>] [--suffix <suffix>]
```

| Аргумент | Обязательный | Описание |
|----------|:---:|----------|
| `input` | да | Путь к AsyncAPI YAML |
| `output` | да | Путь к выходному XSD |
| `-n`, `--namespace` | да | `targetNamespace` генерируемой схемы |
| `--prefix` | нет | Префикс адреса канала, отрезаемый при формировании имени типа |
| `--suffix` | нет | Суффикс адреса канала, отрезаемый при формировании имени типа |

Готовый пример спецификации: [`xdto/asyncapi_example.yaml`](asyncapi_example.yaml). Соответствующий результат: [`xdto/asyncapi_example.xsd`](asyncapi_example.xsd).

```powershell
python .\xdto\asyncapi2xsd.py `
  .\xdto\asyncapi_example.yaml `
  .\xdto\asyncapi_example.generated.xsd `
  --namespace http://example.com/xdto `
  --prefix 1c. `
  --suffix .changed
```

Параметры `--prefix` и `--suffix` применяются к адресам каналов. Например, из адреса `1c.test-document.changed` будет сформировано имя типа `TestDocument`. Если канал для схемы не найден, используется имя схемы из `components.schemas`.

### Поддерживаемые схемы

| AsyncAPI / JSON Schema | XSD |
|------------------------|-----|
| `string` | `xs:string` |
| `string` + `uuid` | `tns:UUID` с проверкой формата |
| `string` + `date`, `date-time`, `time` | `xs:date`, `xs:dateTime`, `xs:time` |
| `integer` | `xs:integer` |
| `integer` + `int32`, `int64` | `xs:int`, `xs:long` |
| `number` | `xs:decimal` |
| `number` + `float`, `double` | `xs:float`, `xs:double` |
| `boolean` | `xs:boolean` |
| `object` | именованный `xs:complexType` |
| `array` | повторяющийся элемент с границами из `minItems` и `maxItems` |
| `enum` | `xs:simpleType` с ограничениями `xs:enumeration` |

Генератор поддерживает:

- вложенные объекты и массивы примитивов, объектов, перечислений и ссылочных типов;
- массивы верхнего уровня;
- локальные ссылки вида `#/components/schemas/<имя>`, включая циклические зависимости;
- строковые ограничения `minLength`, `maxLength`, `pattern`;
- числовые ограничения `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`;
- `multipleOf`, если значение точно представимо через `fractionDigits`: `0.1`, `0.01` и аналогичные десятичные шаги; для целых чисел поддерживается `1`;
- обязательность свойств через `required`; необязательные скалярные свойства формируются с `nillable="true"`.

Внешние `$ref`, логические схемы (`oneOf`, `anyOf`, `allOf`) и `boolean enum` не поддерживаются. При неизвестной ссылке или несовместимом ограничении генератор завершает работу с ошибкой, содержащей путь к проблемному свойству.

## Просмотр в Confluence

Самодостаточный HTML-визуализатор AsyncAPI-спецификации для HTML macro Confluence. Загружает attachment `asyncapi.yaml` с текущей страницы без фиксации версии attachment и не зависит от внешнего CDN или backend-приложения.

Возможности:

- обязательный выбор Kafka-топика с сохранением адреса в URL hash;
- компактная информация о топике, формате и количестве полей;
- табличное представление properties с поддержкой вложенных объектов и массивов;
- разрешение локальных `$ref`, включая enum, `allOf` и защиту от циклов;
- отображение `x-topics`, ограничений, `pattern`, `default`, examples и пользовательских `x-*`;
- поиск внутри выбранного топика и фильтры `Required` / `Deprecated`;
- раскрытие и сворачивание вложенных полей;
- экспорт текущего отфильтрованного представления в CSV с UTF-8 BOM.

### Подключение к Confluence

1. Прикрепить к странице файл с точным именем `asyncapi.yaml`.
2. Поместить содержимое [`xdto/viewer.html`](viewer.html) в HTML macro на этой же странице.
3. Если `pageId` не определяется из контекста Confluence автоматически, указать его в константе `PAGE_ID` внутри `viewer.html`.

При обновлении спецификации достаточно заменить attachment; изменять HTML macro не требуется.
