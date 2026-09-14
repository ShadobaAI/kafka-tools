# CI/CD — сборка образов и релизных артефактов

[← Все инструменты](../README.md)

Здесь находятся GitHub Actions workflows, переиспользуемые actions и Python-скрипты сборки проектов 1С.

## Сборка CI-образов

Workflow [Build 1C CI Images](workflows/build-ci-images.yml) запускается вручную через `workflow_dispatch`. Выберите профиль `edtcli`, `ibcmd` или `client`.

[Подготовка дистрибутивов, локальная сборка и публикация](ci-images/README.md) описаны в руководстве CI-образов. Их конфигурация хранится в [images.yml](ci-images/images.yml).

## Сборка релиза

Вызываемый workflow [Release 1C artifacts](workflows/release-1c-artifacts.yml) использует `workflow_call` и собирает артефакты по тегу версии в формате `X.X.X.X`.

Тип результата (`cf` или `cfe`) определяется по EDT-проекту. Образы сборки берутся из GHCR: `ghcr.io/<owner>/edtcli:latest` и `ghcr.io/<owner>/ibcmd:latest`.

### Входные параметры

| Параметр | Обязательный | Назначение |
|---|:---:|---|
| `name_suffix` | нет | Суффикс имени ZIP-архивов |
| `version_files` | нет | Дополнительные файлы для замены версии, через пробел, относительно корня проекта |
| `pre_script` | нет | Скрипт `.py` или `.sh`, выполняемый до сборки, относительно корня проекта |

### Результат

Workflow публикует в GitHub Release:

- `<repository>.cf` или `<repository>.cfe` — конфигурацию или расширение;
- `<repository>[-<suffix>]-edt.zip` — исходники EDT;
- `<repository>[-<suffix>]-xml.zip` — исходники XML.

Здесь `<repository>` — имя репозитория, вызывающего workflow. Job использует разрешения `contents: write` и `packages: read`.

## Переиспользуемые actions

| Action | Назначение |
|---|---|
| [edt2xml](actions/edt2xml/action.yml) | Конвертация EDT-проекта в XML |
| [xml2cf](actions/xml2cf/action.yml) | Сборка CF/CFE из XML |
| [package-zip](actions/package-zip/action.yml) | Упаковка исходников в ZIP |

## Скрипты

| Скрипт | Назначение |
|---|---|
| [set_version.py](scripts/set_version.py) | Проверка версии релиза, определение типа проекта и замена `9.9.9.9` |
| [edt2xml.py](scripts/edt2xml.py) | Конвертация EDT-проекта в XML в контейнере `edtcli` |
| [xml2cf.py](scripts/xml2cf.py) | Сборка `.cf` или `.cfe` в контейнере `ibcmd` |
| [package_zip.py](scripts/package_zip.py) | Упаковка исходников EDT или XML |
| [ci_utils.py](scripts/ci_utils.py) | Общие пути, определение типа проекта и запись GitHub outputs |
