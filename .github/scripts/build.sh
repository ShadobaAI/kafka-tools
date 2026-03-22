#!/bin/bash
# EDT → XML → .cf или .cfe
# Переменные:
#   BUILD_TYPE    — 'cf' или 'cfe'. Если не задан — определяется автоматически
#                   по .project: V8ExtensionNature → cfe, V8ConfigurationNature → cf
#   VERSION       — X.X.X.X (обязательно)
#   VERSION_FILES — доп. файлы для замены версии (через пробел, относительно корня проекта)
#   SRC_DIR       — исходники EDT-проекта, по умолчанию /src
#   OUTPUT_DIR    — куда сохранить результат, по умолчанию /output

set -euo pipefail

# Автоопределение BUILD_TYPE из .project
if [ -z "${BUILD_TYPE:-}" ]; then
    if grep -q 'V8ExtensionNature' "${SRC_DIR:-/src}/.project" 2>/dev/null; then
        BUILD_TYPE="cfe"
    else
        BUILD_TYPE="cf"
    fi
    echo "→ BUILD_TYPE определён автоматически: $BUILD_TYPE"
fi
VERSION="${VERSION:-0.0.0.0}"
VERSION_FILES="${VERSION_FILES:-}"
SRC_DIR="${SRC_DIR:-/src}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
EDT_WORKSPACE=/tmp/edt-ws
PROJECT_DIR=/tmp/project
XML_DIR=/tmp/xml

echo "=== Build ${BUILD_TYPE^^} ==="
echo "  Version : $VERSION"
echo "  Sources : $SRC_DIR"
echo "  Output  : $OUTPUT_DIR"
echo ""

# ── 1. Валидация ─────────────────────────────────────────────────────────────
if [[ ! "$BUILD_TYPE" =~ ^(cf|cfe)$ ]]; then
    echo "ERROR: BUILD_TYPE должен быть 'cf' или 'cfe'"
    exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: неверный формат версии '$VERSION'. Ожидается X.X.X.X"
    exit 1
fi
if [ ! -f "$SRC_DIR/src/Configuration/Configuration.mdo" ]; then
    echo "ERROR: Configuration.mdo не найден в $SRC_DIR/src/Configuration/"
    exit 1
fi

# ── 2. Копирование исходников ────────────────────────────────────────────────
echo "→ Копирование исходников..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cp -r "$SRC_DIR/.project" "$SRC_DIR/.settings" "$SRC_DIR/DT-INF" "$SRC_DIR/src" "$PROJECT_DIR/"

# ── 3. Замена версии ─────────────────────────────────────────────────────────
echo "→ Версия $VERSION (замена '9.9.9.9')..."
sed -i "s/9\\.9\\.9\\.9/${VERSION}/g" "$PROJECT_DIR/src/Configuration/Configuration.mdo"
if [ -n "$VERSION_FILES" ]; then
    for f in $VERSION_FILES; do
        target="$PROJECT_DIR/$f"
        if [ -f "$target" ]; then
            sed -i "s/9\\.9\\.9\\.9/${VERSION}/g" "$target"
            echo "  патч: $f"
        else
            echo "  WARN: файл не найден — $f"
        fi
    done
fi

# ── 4. EDT → XML ─────────────────────────────────────────────────────────────
echo "→ EDT → XML..."
rm -rf "$XML_DIR" "$EDT_WORKSPACE"
mkdir -p "$XML_DIR" "$EDT_WORKSPACE"

EDTCLI=$(command -v 1cedtcli 2>/dev/null || find /opt/1C/EDT -name "1cedtcli" -type f 2>/dev/null | head -1)
[ -z "$EDTCLI" ] && echo "ERROR: 1cedtcli не найден" && exit 1

"$EDTCLI" -data "$EDT_WORKSPACE" -vmargs "-Xmx2g" \
    -command export --project "$PROJECT_DIR" --configuration-files "$XML_DIR"

# ── 5. XML → CF / CFE ────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
if [ "$BUILD_TYPE" = "cf" ]; then
    echo "→ XML → CF..."
    vrunner compile -s "$XML_DIR" -o "$OUTPUT_DIR/config.cf" --ibcmd
    echo ""
    echo "=== Готово: $OUTPUT_DIR/config.cf ==="
    ls -lh "$OUTPUT_DIR/config.cf"
else
    echo "→ XML → CFE..."
    vrunner compileexttocfe -s "$XML_DIR" -o "$OUTPUT_DIR/config.cfe" --ibcmd
    echo ""
    echo "=== Готово: $OUTPUT_DIR/config.cfe ==="
    ls -lh "$OUTPUT_DIR/config.cfe"
fi
