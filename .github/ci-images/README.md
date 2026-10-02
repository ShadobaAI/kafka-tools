# Docker-образы для CI

[← CI/CD](../README.md) · [Все инструменты](../../README.md)

Раздельные образы для конвертации, сборки и тестирования проектов 1С. Конфигурация registry и профилей — [images.yml](images.yml), сборка — [Dockerfile](docker/Dockerfile).

## Профили

| Профиль | Назначение | Версия в CI |
|---|---|---|
| `edtcli` | Конвертация EDT-проектов в XML | `EDT` |
| `ibcmd` | Сборка CF/CFE из XML | `PLATFORM` |
| `client` | Клиентское окружение для тестирования и покрытия | `PLATFORM` |

Версии EDT и платформы задаются переменными GitHub Actions `EDT` и `PLATFORM`. Для `edtcli` значение `PLATFORM` также задаёт минимальную версию поддержки платформы. Образы используют Debian `trixie-slim`. `edtcli` и `client` используют последнюю доступную версию Axiom JDK 25 Full x64; `ibcmd` и `client` — последние доступные OneScript x64 и Vanessa Runner; `client` — последний релиз Coverage41C и EDT для поддержки покрытия.

Команды CI рассчитаны на Vanessa Runner 3.x и OneScript 2.0.0 или новее. При переходе с образов с Runner 2.x пересоберите и опубликуйте оба профиля `ibcmd` и `client` до запуска обновлённых workflows.

## Подготовка

Нужны Python с PyYAML и Docker с Buildx. Команды ниже выполняются из корня репозитория `tools`.

```powershell
python -m pip install pyyaml
```

Локальные дистрибутивы размещаются в `.github/ci-images/distr/`. Сборщик проверяет наличие архивов, нужных выбранному профилю. Их загрузкой в CI занимается [download_distribution.py](scripts/download_distribution.py).

| Профиль | Дистрибутивы |
|---|---|
| `edtcli` | EDT offline для Linux x86_64 и Axiom JDK 25 Full amd64 `.deb` |
| `ibcmd` | Серверная платформа 1С для Linux x86_64 и OneScript |
| `client` | Платформа 1С, EDT offline, Coverage41C, OneScript и Axiom JDK 25 Full amd64 `.deb` |

Axiom JDK загружается с `releases.1c.ru` из проекта `Axiom25FullJDK` с учётными данными `RELEASES_ONEC_USERNAME` и `RELEASES_ONEC_PASSWORD`. Для локальной сборки можно заранее поместить `axiomjdk_jdk_pro25.*_linux_amd64_full.deb` в `distr/`.

## Локальная сборка

Примеры ниже используют конкретные версии; замените их версиями подготовленных дистрибутивов.

```powershell
python ./.github/ci-images/scripts/build_image.py edtcli:2025.2.6 --edt-platform-support 8.3.27
python ./.github/ci-images/scripts/build_image.py ibcmd:8.3.27
```

Справка по параметрам доступна через `--help`. Параметр `--print-image` выводит имя registry-образа без сборки.

## Публикация

Для публикации добавьте `--push` к команде сборки. Registry по умолчанию — `ghcr.io/<org>`, где владелец берётся из `GITHUB_REPOSITORY_OWNER` в CI или из Git origin локально.

Профили публикуются под тегами `edtcli:latest`, `ibcmd:latest` и `client:latest`. Registry и имя образа можно переопределить параметрами `--registry` и `--image`.

## Сборка через GitHub Actions

Запустите [Build 1C CI Images](../workflows/build-ci-images.yml) вручную и выберите профиль. Workflow подготавливает Buildx, загружает нужные дистрибутивы, собирает и публикует образ. После публикации выполняется очистка старых версий пакета GHCR без тега `latest`.

Доступ к источникам дистрибутивов и registry настраивается через секреты workflow; значения в документации не хранятся.
