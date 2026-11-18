# Инструменты 1С

[← Все инструменты](../README.md)

Команды выполняются из корня репозитория `tools`. Для автоматической сборки релизов используйте [руководство CI/CD](../.github/README.md).

## Технологический журнал

[logcfg.xml](logcfg.xml) содержит настройки технологического журнала платформы 1С. В этом примере записи в формате JSON сохраняются в `C:\kfk`. Загрузку записей описывает [руководство по импорту в Elasticsearch](../elk/README.md#импорт-технологического-журнала-1с).

## Публикация выгрузки базы

[push-dt.py](push-dt.py) публикует файл `.dt` как OCI-артефакт в GHCR с тегом `latest`. Нужны Python 3 и авторизованный GitHub CLI с правом публикации в GHCR. При первом запуске без локального ORAS скрипт загружает его в свой каталог.

```powershell
python .\ones\push-dt.py .\example.dt
```

## Экспорт YAxUnit в XML

[export-yaxunit-xml.py](export-yaxunit-xml.py) экспортирует проект EDT во временный каталог, адаптирует экспортированную конфигурацию и упаковывает XML в ZIP. Нужны Python 3, `1cedtcli` в `PATH` и каталог проекта EDT с файлом `.project`.

```powershell
python .\ones\export-yaxunit-xml.py 'C:\path\to\edt-project' .\yaxunit-xml.zip
```

Оба скрипта выводят параметры по ключу `--help`.
