#!/usr/bin/env bash
set -euo pipefail

license_source="/work"
license_dir="${ONEC_LICENSE_DIR:-/var/1C/licenses}"

mkdir -p "$license_dir" /home/usr1cv8/.1cv8

find "$license_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

if [ -d "$license_source" ]; then
  find "$license_source" -maxdepth 1 -type f -name "*.lic" -exec cp {} "$license_dir"/ \;
fi

chown -R usr1cv8:grp1cv8 "$license_dir" /home/usr1cv8 /work 2>/dev/null || true

if [ "$(id -u)" = "0" ]; then
  exec gosu usr1cv8 "$@"
fi

exec "$@"
