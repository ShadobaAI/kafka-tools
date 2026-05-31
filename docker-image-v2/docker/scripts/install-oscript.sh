#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: install-oscript.sh <source-dir>}"
archive="$(find "$source_dir" -maxdepth 1 -type f -name 'OneScript-*-linux-x64.zip' | sort -V | tail -1)"

if [ -z "$archive" ]; then
  echo "OneScript linux x64 distribution was not found in $source_dir." >&2
  exit 1
fi

mkdir -p /opt/oscript
unzip -q "$archive" -d /opt/oscript
chmod +x /opt/oscript/bin/oscript /opt/oscript/bin/opm
if grep -q '^[[:space:]]*#*[[:space:]]*systemLanguage[[:space:]]*=' /opt/oscript/bin/oscript.cfg; then
  sed -i 's/^[[:space:]]*#*[[:space:]]*systemLanguage[[:space:]]*=.*/systemLanguage = ru/' /opt/oscript/bin/oscript.cfg
else
  printf '\nsystemLanguage = ru\n' >> /opt/oscript/bin/oscript.cfg
fi
