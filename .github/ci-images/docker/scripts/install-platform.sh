#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"
kind="${2:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"
components="${3:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"

work=/tmp/platform-install
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

latest_file() {
  find "$source_dir" -maxdepth 1 -type f -name "$1" | sort -V | tail -1
}

install_server() {
  local archive
  archive="$(latest_file 'deb64_*.zip')"

  if [ -z "$archive" ]; then
    echo "Linux deb64 archive was not found in $source_dir." >&2
    exit 1
  fi

  unzip -q "$archive" -d "$work"
  cd "$work"
  dpkg -i 1c-enterprise*-{common,server}_*.deb
}

install_client() {
  local archive
  local installer
  archive="$(latest_file 'server64_*.zip')"

  if [ -z "$archive" ]; then
    echo "Linux server64 archive was not found in $source_dir." >&2
    exit 1
  fi

  unzip -q "$archive" -d "$work"
  cd "$work"

  installer="$(find . -maxdepth 1 -type f -name 'setup-full-*-x86_64.run' | sort -V | tail -1)"
  if [ -z "$installer" ]; then
    echo "Linux setup-full was not found in $archive." >&2
    exit 1
  fi

  chmod +x "$installer"
  "$installer" --mode unattended --enable-components "$components"
}

case "$kind" in
  server)
    install_server
    ;;
  client)
    install_client
    ;;
  *)
    echo "Unsupported platform kind: $kind" >&2
    exit 2
    ;;
esac

# /opt/1cv8/current lets downstream scripts avoid version-specific paths.
current_dir="$(find /opt -type f \( -name ibcmd -o -name 1cv8 -o -name ragent \) -exec dirname {} \; | sort -V | tail -1)"
test -n "$current_dir"
mkdir -p /opt/1cv8
ln -s "$current_dir" /opt/1cv8/current
