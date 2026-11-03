#!/usr/bin/env bash
set -Eeuo pipefail
early_finish() {
  local code=$?
  trap - EXIT
  printf '\nExit code: %s.\n' "$code" >&2
  if [[ -t 0 ]]; then printf 'Press Enter to close.\n'; read -r _ || true; fi
  exit "$code"
}
trap early_finish EXIT
printf 'Starting OpenViking documentation update...\n'
source "$(dirname "$0")/common.sh" || { printf 'ERROR: Could not load common.sh.\n' >&2; exit 1; }
trap 'error_code=$?; printf "ERROR: Command failed at line %s (exit code %s).\n" "$LINENO" "$error_code" >&2' ERR
for program in git curl jq mktemp cygpath; do require "$program"; done
[[ -f "$STATE_DIR/tenant.curl" ]] || fail 'Run start.sh first.'
printf 'Checking OpenViking and Ollama...\n'
check_ready
model_digests() {
  curl --silent --show-error --fail --max-time 15 "$OLLAMA_URL/api/tags" | jq -cSe '[.models[] | select(.name == "qwen3-embedding:0.6b" or .name == "qwen3.5:4b") | {(.name): .digest}] | add | select(type == "object" and length == 2 and all(.[]; type == "string" and length > 0))'
}
models=$(model_digests) || fail 'Cannot verify the installed model digests.'
printf 'Checking Git documents and synchronization state...\n'
lock="$STATE_DIR/sync.lock"
mkdir "$lock" 2>/dev/null || fail 'Synchronization lock exists. Check for another running update before recovery.'
work=''
progress_pid=''
cleanup() {
  local code=$?
  trap - EXIT
  if [[ -n "$progress_pid" ]]; then
    kill "$progress_pid" 2>/dev/null || true
    wait "$progress_pid" 2>/dev/null || true
  fi
  if [[ -n "$work" ]]; then
    rm -f -- "$work/previous.json" "$work/current.json" "$work/inventory" "$work/response" "$work/body" "$work/next" "$work/plan" "$work/content" "$work/state.json"
    rmdir -- "$work"
  fi
  rmdir -- "$lock"
  finish "$code"
}
trap cleanup EXIT
work=$(mktemp -d "$STATE_DIR/sync.XXXXXX")
state="$STATE_DIR/state.json"
previous="$work/previous.json"
current="$work/current.json"
inventory="$work/inventory"
response="$work/response"
body="$work/body"
if [[ -e "$STATE_DIR/dirty" ]]; then
  # An interrupted very first import can be retried only when it left no
  # resources at all and OpenViking has no queued or active processing.
  [[ ! -e "$state" ]] || fail 'Previous synchronization was incomplete. Do not retry until its outcome is reviewed.'
  queue_idle() {
    request "$STATE_DIR/tenant.curl" GET '/api/v1/observer/queue?format=json' "$response" &&
      jq -e '.status == "ok" and .result.is_healthy == true and .result.has_errors == false and .result.status.summary.pending == 0 and .result.status.summary.in_progress == 0' "$response" >/dev/null
  }
  queue_idle || fail 'Previous synchronization was incomplete and the processing queue is not confirmed idle.'
  curl --silent --show-error --fail --max-time 15 --config "$(cygpath -m "$STATE_DIR/tenant.curl")" --get --data-urlencode 'uri=viking://resources' "$OPENVIKING_URL/api/v1/fs/ls" > "$response" || fail 'Cannot inspect resources for initial synchronization recovery.'
  jq -e '.status == "ok" and (.result | type == "array" and length == 0)' "$response" >/dev/null || fail 'Resources are not empty; manual review of the incomplete synchronization is required.'
  queue_idle || fail 'Processing resumed during the recovery check; retry later.'
  reviewed="$STATE_DIR/dirty-reviewed.$(date +%Y%m%d%H%M%S).$$"
  [[ ! -e "$reviewed" ]] || fail 'Recovery marker already exists.'
  mv -- "$STATE_DIR/dirty" "$reviewed"
  printf 'Recovered an incomplete first import: resources are empty and the queue is idle. The previous marker was preserved.\n'
fi
if [[ -f "$state" ]]; then
  jq -e --arg version "$OPENVIKING_VERSION" --argjson models "$models" '.schema == 1 and .version == $version and .models == $models and (.files | type == "object")' "$state" >/dev/null || fail 'Saved state is incompatible or model digests changed; review the index before updating.'
  cp "$state" "$previous"
else
  status=$(curl --silent --show-error --max-time 15 --config "$(cygpath -m "$STATE_DIR/tenant.curl")" --get --data-urlencode "uri=$NAMESPACE" -o "$response" -w '%{http_code}' "$OPENVIKING_URL/api/v1/fs/stat") || fail 'Cannot inspect existing namespace.'
  [[ "$status" == 404 ]] && jq -e '.error.code == "NOT_FOUND"' "$response" >/dev/null || fail 'Namespace already exists or its state cannot be established; restore synchronization state.'
  printf '{"schema":1,"files":{}}\n' > "$previous"
fi
revision=$(git -C "$REPO_DIR" rev-parse HEAD)
git -C "$REPO_DIR" ls-tree -r -z "$revision" -- docs > "$inventory"
printf '{}\n' > "$current"
while IFS= read -r -d '' entry; do
  meta=${entry%%$'\t'*}
  file=${entry#*$'\t'}
  [[ "$file" == *.md ]] || continue
  [[ "$meta" =~ ^100(644|755)\ blob\ ([0-9a-f]{40,64})$ ]] || fail "Unsupported Git entry: $file"
  oid=${BASH_REMATCH[2]}
  [[ "$file" == docs/* && "$file" != *$'\n'* && "$file" != *$'\r'* && "$file" != *'..'* ]] || fail "Unsupported document path: $file"
  jq --arg f "$file" --arg oid "$oid" '. + {($f): $oid}' "$current" > "$work/next"
  mv -f "$work/next" "$current"
done < "$inventory"
jq -e 'length > 0' "$current" >/dev/null || fail 'No committed Markdown documents found in docs/.'
jq -n --slurpfile old "$previous" --slurpfile new "$current" '{writes: [$new[0] | to_entries[] | select(.value != $old[0].files[.key]) | .key], deletes: [$old[0].files | keys[] | select(. as $k | $new[0] | has($k) | not)]}' > "$work/plan"
writes=$(jq '.writes | length' "$work/plan")
deletes=$(jq '.deletes | length' "$work/plan")
printf 'Commit %s: %s document(s) to index; %s to delete.\n' "$revision" "$writes" "$deletes"
sync_started=$SECONDS
if (( deletes > 0 )); then
  jq -r '.deletes[]' "$work/plan"
  [[ -t 0 ]] || fail 'Deletion needs confirmation in an interactive terminal.'
  read -r -p 'Delete these documents from OpenViking? Type yes: ' answer
  [[ "$answer" == yes ]] || fail 'Cancelled; index unchanged.'
fi
if (( writes > 0 || deletes > 0 )); then printf 'incomplete\n' > "$STATE_DIR/dirty"; fi
deleted=0
while IFS= read -r file; do
  # Native Windows jq may end each output line with CRLF under Git Bash.
  file=${file%$'\r'}
  [[ -n "$file" ]] || continue
  uri="$NAMESPACE/$file"
  ((deleted += 1))
  printf '[delete %s/%s] %s\n' "$deleted" "$deletes" "$file"
  curl --silent --show-error --fail-with-body --max-time 120 --config "$(cygpath -m "$STATE_DIR/tenant.curl")" -X DELETE --get --data-urlencode "uri=$uri" --data-urlencode 'recursive=false' "$OPENVIKING_URL/api/v1/fs" > "$response" || fail "Delete failed: $file"
  jq -e '.status == "ok"' "$response" >/dev/null || fail "Delete incomplete: $file"
done < <(jq -r '.deletes[]' "$work/plan")
completed=0
while IFS= read -r file; do
  file=${file%$'\r'}
  [[ -n "$file" ]] || continue
  oid=$(jq -er --arg f "$file" '.[$f] | select(type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))' "$current") || fail "Missing or invalid Git object ID for $file"
  git -C "$REPO_DIR" cat-file blob "$oid" > "$work/content"
  jq -n --arg uri "$NAMESPACE/$file" --rawfile content "$work/content" '{uri:$uri,content:$content,mode:"replace",wait:true}' > "$body"
  current_number=$((completed + 1))
  item_started=$SECONDS
  printf '[%s/%s, %s%% complete] Indexing %s\n' "$current_number" "$writes" "$((completed * 100 / writes))" "$file"
  request "$STATE_DIR/tenant.curl" POST '/api/v1/content/write' "$response" -H 'Content-Type: application/json' --data-binary "@$(cygpath -m "$body")" &
  request_pid=$!
  (
    while kill -0 "$request_pid" 2>/dev/null; do
      sleep 15 </dev/null >/dev/null 2>&1
      if kill -0 "$request_pid" 2>/dev/null; then
        printf '[%s/%s] Still processing: %ss for this document, %ss total.\n' "$current_number" "$writes" "$((SECONDS - item_started))" "$((SECONDS - sync_started))"
      fi
    done
  ) &
  progress_pid=$!
  request_status=0
  wait "$request_pid" || request_status=$?
  kill "$progress_pid" 2>/dev/null || true
  wait "$progress_pid" 2>/dev/null || true
  progress_pid=''
  (( request_status == 0 )) || fail "Write failed or timed out: $file. Its outcome is unknown; do not retry automatically."
  jq -e '.status == "ok" and .result.semantic_status == "complete" and .result.vector_status == "complete"' "$response" >/dev/null || fail "Indexing incomplete: $file"
  ((completed += 1))
  printf '[%s/%s, %s%% complete] Done in %ss; total %ss.\n' "$completed" "$writes" "$((completed * 100 / writes))" "$((SECONDS - item_started))" "$((SECONDS - sync_started))"
done < <(jq -r '.writes[]' "$work/plan")
total_documents=$(jq 'length' "$current")
verified=0
printf 'Verifying %s indexed documents...\n' "$total_documents"
while IFS= read -r file; do
  file=${file%$'\r'}
  curl --silent --show-error --fail --max-time 15 --config "$(cygpath -m "$STATE_DIR/tenant.curl")" --get --data-urlencode "uri=$NAMESPACE/$file" "$OPENVIKING_URL/api/v1/fs/stat" > "$response" || fail "Missing indexed document: $file"
  jq -e '.status == "ok" and .result.isDir == false' "$response" >/dev/null || fail "Invalid indexed document: $file"
  ((verified += 1))
  if (( verified % 10 == 0 || verified == total_documents )); then
    printf 'Verified %s/%s documents; total %ss.\n' "$verified" "$total_documents" "$((SECONDS - sync_started))"
  fi
done < <(jq -r 'keys[]' "$current")
[[ $(git -C "$REPO_DIR" rev-parse HEAD) == "$revision" ]] || fail 'Git HEAD changed during synchronization.'
models_after=$(model_digests) || fail 'Cannot recheck model digests after synchronization.'
[[ "$models_after" == "$models" ]] || fail 'Model digests changed during synchronization.'
jq -n --arg revision "$revision" --arg version "$OPENVIKING_VERSION" --argjson models "$models" --slurpfile files "$current" '{schema:1,version:$version,models:$models,revision:$revision,files:$files[0]}' > "$work/state.json"
mv -f "$work/state.json" "$state"
rm -f "$STATE_DIR/dirty"
printf 'Documentation synchronized successfully in %ss.\n' "$((SECONDS - sync_started))"
