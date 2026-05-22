#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="tool-failure-handoff-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tool-failure-handoff probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for tool-failure-handoff probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: tool-failure-handoff-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded multi-tool probe where the primary helper fails and Artificer
must hand off to a fallback helper plus current docs, then return one concrete
triage without editing files.
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

create_workspace_for_scenario() {
  scenario=$1
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/webapp/src" "$workspace_dir/config"
  case "$scenario" in
    repo-helper-missing)
      cat > "$workspace_dir/webapp/src/widgets-client.js" <<'EOF_JS'
export async function loadWidgets(fetchJson) {
  return fetchJson('/v1/widgets/list', {
    timeoutMs: 5000,
  });
}
EOF_JS
      cat > "$workspace_dir/bin/primary-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'primary_helper=./bin/primary-check.sh'
printf '%s\n' 'primary_reason=repo_scan_unavailable'
exit 1
EOF_SH
      cat > "$workspace_dir/bin/fallback-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=legacy_widget_contract'
printf '%s\n' 'runtime_file=webapp/src/widgets-client.js'
printf '%s\n' 'runtime_endpoint=/v1/widgets/list'
printf '%s\n' 'runtime_timeout_ms=5000'
exit 1
EOF_SH
      ;;
    upload-browser-blocked)
      cat > "$workspace_dir/config/runtime.env" <<'EOF_CFG'
uploads_rollout=off
UPLOAD_BUCKET=tenant-artifacts
EOF_CFG
      cat > "$workspace_dir/bin/primary-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'primary_helper=./bin/primary-check.sh'
printf '%s\n' 'primary_reason=browser_snapshot_capture_failed'
exit 1
EOF_SH
      cat > "$workspace_dir/bin/fallback-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=uploads_rollout_disabled'
printf '%s\n' 'runtime_file=config/runtime.env'
printf '%s\n' 'runtime_flag=uploads_rollout=off'
printf '%s\n' 'runtime_route=/v2/uploads/complete'
exit 1
EOF_SH
      ;;
    session-cache-handoff)
      cat > "$workspace_dir/config/runtime.env" <<'EOF_CFG'
SESSION_CACHE_URL=
LOGIN_BOUNDARY=active
EOF_CFG
      cat > "$workspace_dir/bin/primary-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'primary_helper=./bin/primary-check.sh'
printf '%s\n' 'primary_reason=dom_snapshot_unavailable'
exit 1
EOF_SH
      cat > "$workspace_dir/bin/fallback-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=session_cache_missing'
printf '%s\n' 'runtime_file=config/runtime.env'
printf '%s\n' 'runtime_session_cache_url=missing'
printf '%s\n' 'runtime_miss_rate=68%'
exit 1
EOF_SH
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<EOF_README
# Tool Failure Handoff Demo

Scenario: $scenario
Use ./bin/primary-check.sh first. If it fails, hand off to ./bin/fallback-check.sh and the current docs URL. Do not edit files in this probe.
EOF_README
}

create_docs_site() {
  docs_dir=$1
  mkdir -p "$docs_dir/current"
  cat > "$docs_dir/current/widgets-v2.html" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Widgets v2</title></head>
<body>
  <article>
    <h1>Widgets API v2 migration</h1>
    <p>Legacy GET /v1/widgets/list has been removed.</p>
    <p>Clients must call GET /v2/widgets.</p>
    <p>Client timeout should be at least 15000 ms before wider rollout.</p>
  </article>
</body>
</html>
EOF_HTML
  cat > "$docs_dir/current/uploads-rollout.html" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Uploads rollout</title></head>
<body>
  <article>
    <h1>Uploads publishing rollout</h1>
    <p>Publishing uploads to /v2/uploads/complete requires uploads_rollout=on.</p>
    <p>Do not widen upload traffic until the rollout flag is enabled.</p>
  </article>
</body>
</html>
EOF_HTML
  cat > "$docs_dir/current/session-cache.html" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Session cache guidance</title></head>
<body>
  <article>
    <h1>Session-backed login guidance</h1>
    <p>Interactive login requires SESSION_CACHE_URL to be configured.</p>
    <p>Warm the session cache before broadening traffic again.</p>
  </article>
</body>
</html>
EOF_HTML
}

doc_path_for_scenario() {
  case "$1" in
    repo-helper-missing)
      printf '%s' '/current/widgets-v2.html'
      ;;
    upload-browser-blocked)
      printf '%s' '/current/uploads-rollout.html'
      ;;
    session-cache-handoff)
      printf '%s' '/current/session-cache.html'
      ;;
    *)
      return 1
      ;;
  esac
}

label=$DEFAULT_LABEL
scenario="repo-helper-missing"
prompt_override=""
prompt_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --scenario)
      scenario=$2
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
[ -n "$model" ] || { echo "No installed models available; tool-failure-handoff probe cannot run." >&2; exit 1; }

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

create_workspace_for_scenario "$scenario" "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"
create_docs_site "$docs_dir"

doc_port=$(pick_unused_port)
doc_url="http://127.0.0.1:$doc_port$(doc_path_for_scenario "$scenario")"
python3 -m http.server "$doc_port" --bind 127.0.0.1 --directory "$docs_dir" >"$doc_server_log" 2>&1 &
doc_server_pid=$!
wait_for_doc_server "$doc_url"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Investigate this bounded multi-tool failure-handoff case in the workspace. Run `./bin/primary-check.sh` first. If the primary helper fails, explicitly hand off to `./bin/fallback-check.sh`, then use the current doc at __DOC_URL__. Do not edit files. Return exactly five lines starting with: Primary Tool Failure, Fallback Evidence, Web Evidence, Root Cause, Next Action.
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

primary_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/primary-check.sh")) | if . then 1 else 0 end')
fallback_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/fallback-check.sh")) | if . then 1 else 0 end')
web_fetch_emitted=$(printf '%s\n' "$stream_text" | grep -q 'Quick-mode web fetch:' && printf '%s' "1" || printf '%s' "0")
handoff_emitted=$(printf '%s\n' "$stream_text" | grep -q 'Quick-mode handoff:' && printf '%s' "1" || printf '%s' "0")
has_primary_failure=$(printf '%s\n' "$assistant_text" | grep -q '^Primary Tool Failure:' && printf '%s' "1" || printf '%s' "0")
has_fallback_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Fallback Evidence:' && printf '%s' "1" || printf '%s' "0")
has_web_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Web Evidence:' && printf '%s' "1" || printf '%s' "0")
has_root_cause=$(printf '%s\n' "$assistant_text" | grep -q '^Root Cause:' && printf '%s' "1" || printf '%s' "0")
has_next_action=$(printf '%s\n' "$assistant_text" | grep -q '^Next Action:' && printf '%s' "1" || printf '%s' "0")
mentions_primary=$(printf '%s\n' "$assistant_text" | grep -q './bin/primary-check.sh' && printf '%s' "1" || printf '%s' "0")
mentions_fallback=$(printf '%s\n' "$assistant_text" | grep -q './bin/fallback-check.sh' && printf '%s' "1" || printf '%s' "0")
workspace_unchanged=$(diff -qr "$baseline_dir" "$tmp_ws" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

mentions_expected_one=0
mentions_expected_two=0
case "$scenario" in
  repo-helper-missing)
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q '/v2/widgets' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q '15000' && printf '%s' "1" || printf '%s' "0")
    ;;
  upload-browser-blocked)
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'uploads_rollout=on' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q '/v2/uploads/complete' && printf '%s' "1" || printf '%s' "0")
    ;;
  session-cache-handoff)
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'SESSION_CACHE_URL' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -qi 'session cache' && printf '%s' "1" || printf '%s' "0")
    ;;
esac

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$primary_ran" -eq 1 ] && [ "$fallback_ran" -eq 1 ] && [ "$web_fetch_emitted" -eq 1 ] && [ "$handoff_emitted" -eq 1 ] && [ "$workspace_unchanged" -eq 1 ] && [ "$has_primary_failure" -eq 1 ] && [ "$has_fallback_evidence" -eq 1 ] && [ "$has_web_evidence" -eq 1 ] && [ "$has_root_cause" -eq 1 ] && [ "$has_next_action" -eq 1 ] && [ "$mentions_primary" -eq 1 ] && [ "$mentions_fallback" -eq 1 ] && [ "$mentions_expected_one" -eq 1 ] && [ "$mentions_expected_two" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"primary_ran":%s,"fallback_ran":%s,"web_fetch_emitted":%s,"handoff_emitted":%s,"workspace_unchanged":%s,"has_primary_failure":%s,"has_fallback_evidence":%s,"has_web_evidence":%s,"has_root_cause":%s,"has_next_action":%s,"mentions_primary":%s,"mentions_fallback":%s,"mentions_expected_one":%s,"mentions_expected_two":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$primary_ran" "$fallback_ran" "$web_fetch_emitted" "$handoff_emitted" "$workspace_unchanged" "$has_primary_failure" "$has_fallback_evidence" "$has_web_evidence" "$has_root_cause" "$has_next_action" "$mentions_primary" "$mentions_fallback" "$mentions_expected_one" "$mentions_expected_two" "$stream_line_count" > "$json_file"

{
  printf '# Tool Failure Handoff Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- `primary-check.sh` ran: %s\n' "$primary_ran"
  printf -- '- `fallback-check.sh` ran: %s\n' "$fallback_ran"
  printf -- '- Web fetch emitted: %s\n' "$web_fetch_emitted"
  printf -- '- Handoff emitted: %s\n' "$handoff_emitted"
  printf -- '- Workspace unchanged: %s\n' "$workspace_unchanged"
  printf -- '- Primary Tool Failure section: %s\n' "$has_primary_failure"
  printf -- '- Fallback Evidence section: %s\n' "$has_fallback_evidence"
  printf -- '- Web Evidence section: %s\n' "$has_web_evidence"
  printf -- '- Root Cause section: %s\n' "$has_root_cause"
  printf -- '- Next Action section: %s\n' "$has_next_action"
  printf -- '- Mentions primary helper: %s\n' "$mentions_primary"
  printf -- '- Mentions fallback helper: %s\n' "$mentions_fallback"
  printf -- '- Mentions scenario expectation one: %s\n' "$mentions_expected_one"
  printf -- '- Mentions scenario expectation two: %s\n' "$mentions_expected_two"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
