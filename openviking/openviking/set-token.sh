#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [[ ${OS:-} != Windows_NT ]] || ! command -v powershell.exe >/dev/null 2>&1; then
  printf '%s\n' 'Run this script in Git Bash on Windows; PowerShell is required.' >&2
  exit 1
fi

# Never reuse the publication/admin key (tenant.curl) as a search credential.
key_file="$STATE_DIR/search.curl"
key_pattern='^[[:space:]]*header[[:space:]]*=[[:space:]]*"X-Api-Key:[[:space:]]*([^"[:space:]]+)"[[:space:]]*$'
if [[ -e "$key_file" ]]; then
  [[ -f "$key_file" && -r "$key_file" ]] || { printf '%s\n' 'Cannot read search.curl; no variable was saved.' >&2; exit 1; }
  mapfile -t key_lines < "$key_file"
  if [[ ${#key_lines[@]} -ne 1 ]] || [[ ! ${key_lines[0]%$'\r'} =~ $key_pattern ]]; then
    printf '%s\n' 'Invalid search.curl format; no variable was saved.' >&2
    exit 1
  fi
  token=${BASH_REMATCH[1]}
  unset key_lines BASH_REMATCH
else
  if [[ ! -t 0 ]]; then
    printf '%s\n' 'No search.curl found; run interactively to enter a read-only token.' >&2
    exit 1
  fi
  read -r -s -p 'OpenViking search token: ' token
  printf '\n'
  if [[ -z "$token" || "$token" =~ [[:space:]] ]]; then
    printf '%s\n' 'Invalid search token; no variable was saved.' >&2
    exit 1
  fi
fi
for admin_file in "$STATE_DIR/tenant.curl" "$STATE_DIR/root.curl"; do
  if [[ -e "$admin_file" ]]; then
    [[ -f "$admin_file" && -r "$admin_file" ]] || { printf '%s\n' 'Cannot check an existing publication credential; no variable was saved.' >&2; exit 1; }
    mapfile -t admin_lines < "$admin_file"
    if [[ ${#admin_lines[@]} -ne 1 ]] || [[ ! ${admin_lines[0]%$'\r'} =~ $key_pattern ]]; then
      printf '%s\n' 'Cannot check an existing publication credential; no variable was saved.' >&2
      exit 1
    fi
    if [[ "$token" == "${BASH_REMATCH[1]}" ]]; then
      printf '%s\n' 'Search and publication credentials must differ; no variable was saved.' >&2
      exit 1
    fi
    unset admin_lines BASH_REMATCH
  fi
done

# No credentials in command arguments or output.
export OPENVIKING_SEARCH_TOKEN="$token"
unset token
if ! powershell.exe -NoLogo -NoProfile -NonInteractive -Command '[Environment]::SetEnvironmentVariable("OPENVIKING_SEARCH_TOKEN", $env:OPENVIKING_SEARCH_TOKEN, "User")'; then
  unset OPENVIKING_SEARCH_TOKEN
  printf '%s\n' 'Could not save the user environment variable.' >&2
  exit 1
fi
unset OPENVIKING_SEARCH_TOKEN
printf '%s\n' 'Saved the search token for the Windows user. Restart Codex and check that its process receives the variable.'
printf '%s\n' 'Token separation alone does not verify server permissions or publication.'
