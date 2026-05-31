#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"
kind="${2:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"
components="${3:?usage: install-platform.sh <source-dir> <server|client> <run-components>}"

work=/tmp/platform-install
rm -rf "$work"
mkdir -p "$work"

archive="$(find "$source_dir" -maxdepth 1 -type f \( -name 'deb64_*.zip' -o -name 'deb64_*.tar.gz' -o -name '*.deb64.zip' -o -name '*.deb64.tar.gz' \) | sort -V | tail -1)"
installer="$(find "$source_dir" -maxdepth 1 -type f -name 'setup-full-*-x86_64.run' | sort -V | tail -1)"

install_deb_packages() {
  case "$kind" in
    server)
      dpkg -i 1c-enterprise*-common_*.deb 1c-enterprise*-server_*.deb
      ;;
    client)
      dpkg -i 1c-enterprise*-common_*.deb 1c-enterprise*-client_*.deb
      ;;
    *)
      echo "Unsupported platform kind: $kind" >&2
      exit 2
      ;;
  esac
}

if [ -n "$archive" ]; then
  case "$archive" in
    *.zip)
      unzip -q "$archive" -d "$work"
      ;;
    *.tar.gz)
      tar -xzf "$archive" -C "$work"
      ;;
  esac
  cd "$work"
  install_deb_packages
elif [ -n "$installer" ]; then
  chmod +x "$installer"
  "$installer" --mode unattended --enable-components "$components"
else
  echo "Linux setup-full or deb64 archive was not found in $source_dir." >&2
  exit 1
fi

current_dir="$(find /opt -type f \( -name ibcmd -o -name 1cv8 -o -name ragent \) -exec dirname {} \; | sort -V | tail -1)"
test -n "$current_dir"
mkdir -p /opt/1cv8
ln -s "$current_dir" /opt/1cv8/current
rm -rf "$work"
