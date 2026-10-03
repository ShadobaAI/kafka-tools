#!/usr/bin/env bash
set -euo pipefail

# 1cv8c требует WebKitGTK 4.0/libsoup 2.4; trixie содержит только WebKitGTK 4.1.
printf 'deb https://deb.debian.org/debian bookworm main\ndeb https://security.debian.org/debian-security bookworm-security main\n' \
    >/etc/apt/sources.list.d/onec-webkit40.list
printf 'Package: *\nPin: release n=bookworm\nPin-Priority: 100\n\nPackage: *\nPin: release n=bookworm-security\nPin-Priority: 100\n' \
    >/etc/apt/preferences.d/onec-webkit40
apt-get update
apt-get install -y --no-remove --no-install-recommends libwebkit2gtk-4.0-37

# Bundled libstdc++ платформы не предоставляет GLIBCXX, нужные библиотекам ОС.
test -f /usr/lib/x86_64-linux-gnu/libstdc++.so.6
ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /opt/1cv8/current/libstdc++.so.6

if ! dependencies="$(ldd /opt/1cv8/current/1cv8c 2>&1)"; then
    printf '%s\n' "$dependencies" >&2
    exit 1
fi
if grep -q 'not found' <<<"$dependencies"; then
    printf '%s\n' "$dependencies" >&2
    exit 1
fi

rm -rf /var/lib/apt/lists/*
