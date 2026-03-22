#!/bin/bash
# EDT (проект расширения) → XML → .cf
# Перед сборкой вырезает extension-атрибуты из Configuration.mdo,
# чтобы EDT воспринял проект как конфигурацию, а не расширение.
#
# Переменные:
#   VERSION             — X.X.X.X (обязательно)
#   VERSION_PLACEHOLDER — заглушка в исходниках, по умолчанию 9.9.9.9
#   VERSION_FILES       — доп. файлы для замены (через пробел, относительно корня проекта)
#   SRC_DIR             — исходники EDT-проекта, по умолчанию /src
#   OUTPUT_DIR          — куда сохранить config.cf, по умолчанию /output
#   EDT_MEMORY          — память JVM, по умолчанию 2g

set -euo pipefail

VERSION="${VERSION:-0.0.0.0}"
VERSION_PLACEHOLDER="${VERSION_PLACEHOLDER:-9.9.9.9}"
VERSION_FILES="${VERSION_FILES:-}"
SRC_DIR="${SRC_DIR:-/src}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
EDT_WORKSPACE=/tmp/edt-ws
EDT_MEMORY="${EDT_MEMORY:-2g}"
PROJECT_DIR=/tmp/project
XML_DIR=/tmp/xml

echo "=== Build CF from CFE ==="
echo "  Version : $VERSION"
echo "  Sources : $SRC_DIR"
echo "  Output  : $OUTPUT_DIR"
echo ""

# ── 1. Валидация версии ──────────────────────────────────────────────────────
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: неверный формат версии '$VERSION'. Ожидается X.X.X.X"
    exit 1
fi

# ── 2. Проверка исходников ───────────────────────────────────────────────────
if [ ! -f "$SRC_DIR/src/Configuration/Configuration.mdo" ]; then
    echo "ERROR: Configuration.mdo не найден в $SRC_DIR/src/Configuration/"
    exit 1
fi

# ── 3. Копирование исходников ────────────────────────────────────────────────
echo "→ Копирование исходников..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cp -r "$SRC_DIR/.project" "$SRC_DIR/.settings" "$SRC_DIR/DT-INF" "$SRC_DIR/src" "$PROJECT_DIR/"

# ── 4. Замена версии ─────────────────────────────────────────────────────────
echo "→ Версия $VERSION (замена '$VERSION_PLACEHOLDER')..."
PLACEHOLDER_ESC="${VERSION_PLACEHOLDER//./\\.}"
sed -i "s/${PLACEHOLDER_ESC}/${VERSION}/g" "$PROJECT_DIR/src/Configuration/Configuration.mdo"
if [ -n "$VERSION_FILES" ]; then
    for f in $VERSION_FILES; do
        target="$PROJECT_DIR/$f"
        if [ -f "$target" ]; then
            sed -i "s/${PLACEHOLDER_ESC}/${VERSION}/g" "$target"
            echo "  патч: $f"
        else
            echo "  WARN: файл не найден — $f"
        fi
    done
fi

# ── 5. Preprocessing: CFE → CF (убираем extension-атрибуты) ─────────────────
echo "→ Preprocessing: вырезаем extension-атрибуты из Configuration.mdo..."
MDO="$PROJECT_DIR/src/Configuration/Configuration.mdo"
python3 - "$MDO" <<'PYEOF'
import sys, re

content = open(sys.argv[1], encoding='utf-8').read()

# Убираем namespace-атрибуты из корневого элемента
content = re.sub(r'\s+xmlns:xsi="[^"]*"', '', content)
content = re.sub(r'\s+xmlns:mdclassExtension="[^"]*"', '', content)

# Убираем дочерние элементы расширения
for tag in [
    'objectBelonging',
    'extension',
    'keepMappingToExtendedConfigurationObjectsByIDs',
    'namePrefix',
    'configurationExtensionPurpose',
    'configurationExtensionCompatibilityMode',
]:
    content = re.sub(rf'\s*<{tag}>[^<]*</{tag}>', '', content)
    content = re.sub(rf'\s*<{tag}/>', '', content)

open(sys.argv[1], 'w', encoding='utf-8').write(content)
print(f"  patched: {sys.argv[1]}")
PYEOF

# Меняем природу проекта: расширение → конфигурация
echo "→ Патч .project: V8ExtensionNature → V8ConfigurationNature..."
sed -i 's/V8ExtensionNature/V8ConfigurationNature/g' "$PROJECT_DIR/.project"

# Убираем строки Base-Project из PROJECT.PMF
if [ -f "$PROJECT_DIR/DT-INF/PROJECT.PMF" ]; then
    echo "→ Патч DT-INF/PROJECT.PMF: убираем Base-Project..."
    sed -i '/^Base-Project/d' "$PROJECT_DIR/DT-INF/PROJECT.PMF"
fi

# ── 6. EDT → XML ─────────────────────────────────────────────────────────────
echo "→ EDT → XML..."
rm -rf "$XML_DIR" "$EDT_WORKSPACE"
mkdir -p "$XML_DIR" "$EDT_WORKSPACE"

EDTCLI=$(command -v 1cedtcli 2>/dev/null || find /opt/1C/EDT -name "1cedtcli" -type f 2>/dev/null | head -1)
[ -z "$EDTCLI" ] && echo "ERROR: 1cedtcli не найден" && exit 1

"$EDTCLI" -data "$EDT_WORKSPACE" -vmargs "-Xmx${EDT_MEMORY}" \
    -command export --project "$PROJECT_DIR" --configuration-files "$XML_DIR"

# ── 7. XML → CF ──────────────────────────────────────────────────────────────
echo "→ XML → CF..."
mkdir -p "$OUTPUT_DIR"
vrunner compile -s "$XML_DIR" -o "$OUTPUT_DIR/config.cf" --ibcmd

echo ""
echo "=== Готово: $OUTPUT_DIR/config.cf ==="
ls -lh "$OUTPUT_DIR/config.cf"
