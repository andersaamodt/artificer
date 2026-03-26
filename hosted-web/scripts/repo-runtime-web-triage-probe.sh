#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="repo-runtime-web-triage-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for repo/runtime/web triage probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for repo/runtime/web triage probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: repo-runtime-web-triage-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded multi-tool triage probe against a demo workspace and checks
whether Artificer can combine repo evidence, runtime evidence, and current web
docs into one concrete root-cause/next-change answer without mutating files.
EOF_USAGE
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

post_api_json() {
  body=$1
  len=$(printf '%s' "$body" | wc -c | tr -d ' ')
  REQUEST_METHOD=POST CONTENT_LENGTH="$len" sh "$API_SCRIPT" <<EOF_BODY | tr -d '\r' | awk 'seen{print} /^$/{seen=1}'
$body
EOF_BODY
}

post_api_json_with_timeout() {
  body=$1
  timeout_sec=$2
  python3 - "$API_SCRIPT" "$timeout_sec" "$body" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
timeout_sec = float(sys.argv[2])
body = sys.argv[3]
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))

try:
    proc = subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout_sec,
        check=False,
    )
    raw = proc.stdout.decode().replace("\r", "")
    parts = raw.split("\n\n", 1)
    payload = parts[1] if len(parts) > 1 else raw
    payload = payload.strip()
    if payload:
        print(payload)
    else:
        print('{"__timed_out":false}')
except subprocess.TimeoutExpired:
    print('{"__timed_out":true}')
PY
}

delete_workspace_best_effort() {
  workspace_id=$1
  [ -n "$workspace_id" ] || return 0
  workspace_id_uri=$(uri "$workspace_id")
  python3 - "$API_SCRIPT" "$workspace_id_uri" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
workspace_id_uri = sys.argv[2]
body = f"action=delete_workspace&workspace_id={workspace_id_uri}"
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))
try:
    subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=12,
        check=False,
    )
except Exception:
    pass
PY
}

create_triage_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/webapp/src" "$workspace_dir/runtime"
  cat > "$workspace_dir/webapp/src/widgets-client.js" <<'EOF_JS'
export async function loadWidgets(fetchJson) {
  const response = await fetchJson('/v1/widgets/list', {
    timeoutMs: 5000,
  });
  return response.widgets;
}
EOF_JS
  cat > "$workspace_dir/runtime/last-run.log" <<'EOF_LOG'
request GET /v1/widgets/list
response 404 not found
client parser expected widgets but server requires items
client timeout 5000ms expired before retry budget finished
EOF_LOG
  cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
client_file="$ROOT_DIR/webapp/src/widgets-client.js"
endpoint=$(grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' "$client_file" | head -n 1)
timeout_ms=$(grep -Eo 'timeoutMs:[[:space:]]*[0-9]+' "$client_file" | head -n 1 | tr -cd '0-9')
response_key=$(grep -Eo 'response\.[A-Za-z0-9_]+' "$client_file" | head -n 1 | cut -d. -f2)
printf '%s\n' "repo_file=webapp/src/widgets-client.js"
printf '%s\n' "repo_endpoint=$endpoint"
printf '%s\n' "repo_response_key=$response_key"
printf '%s\n' "repo_timeout_ms=$timeout_ms"
EOF_SH
  cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
log_file="$ROOT_DIR/runtime/last-run.log"
endpoint=$(grep -Eo '/v[0-9]+/widgets(/[A-Za-z0-9._-]+)?' "$log_file" | head -n 1)
http_status=$(grep -Eo 'response[[:space:]]+[0-9]+' "$log_file" | head -n 1 | tr -cd '0-9')
printf '%s\n' "runtime_http_status=$http_status"
printf '%s\n' "runtime_endpoint=$endpoint"
printf '%s\n' 'runtime_shape_issue=expected_items_found_widgets'
printf '%s\n' 'runtime_timeout_issue=timeout_too_low'
exit 1
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Repo Runtime Web Triage Demo

Use `./bin/repo-scan.sh` for repo evidence and `./bin/runtime-check.sh` for
runtime evidence. The current migration doc explains the new widgets contract.
This probe should triage the mismatch without editing files.
EOF_README
}

create_docs_site() {
  docs_dir=$1
  mkdir -p "$docs_dir/migrations"
  cat > "$docs_dir/migrations/widgets-v2.html" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Widgets API v2 Migration</title>
</head>
<body>
  <article>
    <h1>Widgets API v2 migration</h1>
    <p>Legacy GET /v1/widgets/list has been removed.</p>
    <p>Clients must call GET /v2/widgets.</p>
    <p>The response body now uses items and next_cursor.</p>
    <p>Client timeout should be at least 15000 ms before wider rollout.</p>
    <p>Update widgets-client.js to the v2 contract before broadening the change.</p>
  </article>
</body>
</html>
EOF_HTML
}

pick_unused_port() {
  python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

wait_for_doc_server() {
  doc_url=$1
  python3 - "$doc_url" <<'PY'
import sys
import time
import urllib.request

url = sys.argv[1]
for _ in range(40):
    try:
        with urllib.request.urlopen(url, timeout=0.5) as response:
            if response.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.25)
sys.exit(1)
PY
}

label=$DEFAULT_LABEL
prompt_override=""
prompt_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --prompt)
      prompt_override=$2
      shift 2
      ;;
    --prompt-file)
      prompt_file=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("qwen2.5-coder:7b")) then "qwen2.5-coder:7b"
  elif ($m | index("mistral:7b")) then "mistral:7b"
  else ($m[0] // empty)
  end
')
[ -n "$model" ] || { echo "No installed models available; repo/runtime/web triage probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
docs_dir=$(mktemp -d)
doc_server_log=$(mktemp)
doc_server_pid=""
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  if [ -n "$doc_server_pid" ]; then
    kill "$doc_server_pid" >/dev/null 2>&1 || true
    wait "$doc_server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_ws" "$baseline_dir" "$docs_dir" "$doc_server_log"
}
trap cleanup EXIT INT TERM

create_triage_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"
create_docs_site "$docs_dir"

doc_port=$(pick_unused_port)
doc_url="http://127.0.0.1:$doc_port/migrations/widgets-v2.html"
python3 -m http.server "$doc_port" --bind 127.0.0.1 --directory "$docs_dir" >"$doc_server_log" 2>&1 &
doc_server_pid=$!
wait_for_doc_server "$doc_url"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Triaging the bounded client migration mismatch in this workspace. Use `./bin/repo-scan.sh` for repo evidence, `./bin/runtime-check.sh` for runtime evidence, and the current migration doc at __DOC_URL__ for web evidence. Do not edit files. Determine the concrete root cause and the next file-level change only. End with sections: Repo Evidence, Runtime Evidence, Web Evidence, Root Cause, Next Change.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
prompt_text=$(printf '%s' "$prompt_text" | sed "s|__DOC_URL__|$doc_url|g")

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=assistant&compute_budget=long&advanced_loop=1&max_iterations=6&stream_session=$(uri "$stream_session")"
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=170 post_api_json_with_timeout "$run_body" 95)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

repo_scan_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/repo-scan.sh")) | if . then 1 else 0 end')
runtime_check_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/runtime-check.sh")) | if . then 1 else 0 end')
web_fetch_emitted=$(printf '%s\n' "$stream_text" | grep -q 'Quick-mode web fetch:' && printf '%s' "1" || printf '%s' "0")
has_repo_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Repo Evidence:' && printf '%s' "1" || printf '%s' "0")
has_runtime_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Runtime Evidence:' && printf '%s' "1" || printf '%s' "0")
has_web_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Web Evidence:' && printf '%s' "1" || printf '%s' "0")
has_root_cause=$(printf '%s\n' "$assistant_text" | grep -q '^Root Cause:' && printf '%s' "1" || printf '%s' "0")
has_next_change=$(printf '%s\n' "$assistant_text" | grep -q '^Next Change:' && printf '%s' "1" || printf '%s' "0")
mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'webapp/src/widgets-client.js' && printf '%s' "1" || printf '%s' "0")
mentions_v1=$(printf '%s\n' "$assistant_text" | grep -q '/v1/widgets/list' && printf '%s' "1" || printf '%s' "0")
mentions_v2=$(printf '%s\n' "$assistant_text" | grep -q '/v2/widgets' && printf '%s' "1" || printf '%s' "0")
mentions_items=$(printf '%s\n' "$assistant_text" | grep -q 'items' && printf '%s' "1" || printf '%s' "0")
mentions_timeout=$(printf '%s\n' "$assistant_text" | grep -q '15000' && printf '%s' "1" || printf '%s' "0")
workspace_unchanged=$(diff -qr "$baseline_dir" "$tmp_ws" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$repo_scan_ran" -eq 1 ] && [ "$runtime_check_ran" -eq 1 ] && [ "$web_fetch_emitted" -eq 1 ] && [ "$workspace_unchanged" -eq 1 ] && [ "$has_repo_evidence" -eq 1 ] && [ "$has_runtime_evidence" -eq 1 ] && [ "$has_web_evidence" -eq 1 ] && [ "$has_root_cause" -eq 1 ] && [ "$has_next_change" -eq 1 ] && [ "$mentions_repo_file" -eq 1 ] && [ "$mentions_v1" -eq 1 ] && [ "$mentions_v2" -eq 1 ] && [ "$mentions_items" -eq 1 ] && [ "$mentions_timeout" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"repo_scan_ran":%s,"runtime_check_ran":%s,"web_fetch_emitted":%s,"workspace_unchanged":%s,"has_repo_evidence":%s,"has_runtime_evidence":%s,"has_web_evidence":%s,"has_root_cause":%s,"has_next_change":%s,"mentions_repo_file":%s,"mentions_v1":%s,"mentions_v2":%s,"mentions_items":%s,"mentions_timeout":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$repo_scan_ran" "$runtime_check_ran" "$web_fetch_emitted" "$workspace_unchanged" "$has_repo_evidence" "$has_runtime_evidence" "$has_web_evidence" "$has_root_cause" "$has_next_change" "$mentions_repo_file" "$mentions_v1" "$mentions_v2" "$mentions_items" "$mentions_timeout" "$stream_line_count" > "$json_file"

{
  printf '# Repo Runtime Web Triage Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- `repo-scan.sh` ran: %s\n' "$repo_scan_ran"
  printf -- '- `runtime-check.sh` ran: %s\n' "$runtime_check_ran"
  printf -- '- Web fetch emitted: %s\n' "$web_fetch_emitted"
  printf -- '- Workspace unchanged: %s\n' "$workspace_unchanged"
  printf -- '- Repo Evidence section: %s\n' "$has_repo_evidence"
  printf -- '- Runtime Evidence section: %s\n' "$has_runtime_evidence"
  printf -- '- Web Evidence section: %s\n' "$has_web_evidence"
  printf -- '- Root Cause section: %s\n' "$has_root_cause"
  printf -- '- Next Change section: %s\n' "$has_next_change"
  printf -- '- Mentions repo file: %s\n' "$mentions_repo_file"
  printf -- '- Mentions legacy endpoint: %s\n' "$mentions_v1"
  printf -- '- Mentions current endpoint: %s\n' "$mentions_v2"
  printf -- '- Mentions new response key: %s\n' "$mentions_items"
  printf -- '- Mentions current timeout: %s\n' "$mentions_timeout"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
