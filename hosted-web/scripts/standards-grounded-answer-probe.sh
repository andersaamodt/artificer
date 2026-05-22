#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="standards-grounded-answer-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for standards-grounded-answer probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for standards-grounded-answer probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: standards-grounded-answer-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH] [--doc-url URL]

Runs a live bounded standards-grounded answer probe against a demo workspace and
checks whether Artificer can combine repo evidence, runtime evidence, and the
current official standard/docs into one concrete answer without editing files.
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

scenario_default_doc_url() {
  case "$1" in
    cors-credentials-wildcard)
      printf '%s' 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors/CORSNotSupportingCredentials'
      ;;
    cookie-samesite-none-without-secure)
      printf '%s' 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite'
      ;;
    cors-authorization-header-missing)
      printf '%s' 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Headers'
      ;;
    *)
      printf '%s' 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS'
      ;;
  esac
}

create_workspace_for_scenario() {
  scenario=$1
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/server"
  case "$scenario" in
    cors-credentials-wildcard)
      cat > "$workspace_dir/server/cors.py" <<'EOF_PY'
RESPONSE_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Credentials": "true",
}
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=server/cors.py'
printf '%s\n' 'standard_issue=cors_credentials_wildcard'
printf '%s\n' 'repo_allow_origin=*'
printf '%s\n' 'repo_allow_credentials=true'
printf '%s\n' 'repo_origin=https://app.example.com'
EOF_SH
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=cors_credentials_wildcard'
printf '%s\n' 'runtime_request_origin=https://app.example.com'
printf '%s\n' 'runtime_symptom=credentials_blocked_by_wildcard'
printf '%s\n' 'runtime_request_mode=include_credentials'
EOF_SH
      ;;
    cookie-samesite-none-without-secure)
      cat > "$workspace_dir/server/session.py" <<'EOF_PY'
SESSION_COOKIE = {
    "name": "app_session",
    "same_site": "None",
    "secure": False,
}
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=server/session.py'
printf '%s\n' 'standard_issue=samesite_none_without_secure'
printf '%s\n' 'repo_cookie_name=app_session'
printf '%s\n' 'repo_same_site=None'
printf '%s\n' 'repo_secure=false'
EOF_SH
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=samesite_none_without_secure'
printf '%s\n' 'runtime_cookie_name=app_session'
printf '%s\n' 'runtime_browser=chrome'
printf '%s\n' 'runtime_symptom=session_cookie_rejected'
EOF_SH
      ;;
    cors-authorization-header-missing)
      cat > "$workspace_dir/server/cors.py" <<'EOF_PY'
RESPONSE_HEADERS = {
    "Access-Control-Allow-Origin": "https://admin.example.com",
    "Access-Control-Allow-Headers": "Content-Type",
}
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=server/cors.py'
printf '%s\n' 'standard_issue=cors_authorization_header_missing'
printf '%s\n' 'repo_allow_headers=Content-Type'
printf '%s\n' 'repo_requested_header=Authorization'
printf '%s\n' 'repo_origin=https://admin.example.com'
EOF_SH
      cat > "$workspace_dir/bin/runtime-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'runtime_issue=cors_authorization_header_missing'
printf '%s\n' 'runtime_requested_header=Authorization'
printf '%s\n' 'runtime_origin=https://admin.example.com'
printf '%s\n' 'runtime_symptom=preflight_header_rejected'
EOF_SH
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  chmod +x "$workspace_dir/bin/repo-scan.sh" "$workspace_dir/bin/runtime-check.sh"
  cat > "$workspace_dir/README.md" <<EOF_README
# Standards Grounded Answer Demo

Scenario: $scenario
Use ./bin/repo-scan.sh for repo evidence, ./bin/runtime-check.sh for runtime evidence,
and the current official standard/docs URL for grounding. Do not edit files.
EOF_README
}

label=$DEFAULT_LABEL
scenario="cors-credentials-wildcard"
prompt_override=""
prompt_file=""
doc_url=""
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
    --doc-url)
      doc_url=$2
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

[ -n "$doc_url" ] || doc_url=$(scenario_default_doc_url "$scenario")

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
[ -n "$model" ] || { echo "No installed models available; standards-grounded-answer probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_workspace_for_scenario "$scenario" "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Investigate this bounded standards-grounded answer in the workspace. Use `./bin/repo-scan.sh` for repo evidence, `./bin/runtime-check.sh` for runtime evidence, and the current official standard/docs at __DOC_URL__. Do not edit files. Return exactly five lines starting with: Repo Evidence, Runtime Evidence, Current Standard, Standards Answer, Next Change.
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
workspace_unchanged=$(diff -qr "$baseline_dir" "$tmp_ws" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
has_repo_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Repo Evidence:' && printf '%s' "1" || printf '%s' "0")
has_runtime_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Runtime Evidence:' && printf '%s' "1" || printf '%s' "0")
has_current_standard=$(printf '%s\n' "$assistant_text" | grep -q '^Current Standard:' && printf '%s' "1" || printf '%s' "0")
has_standards_answer=$(printf '%s\n' "$assistant_text" | grep -q '^Standards Answer:' && printf '%s' "1" || printf '%s' "0")
has_next_change=$(printf '%s\n' "$assistant_text" | grep -q '^Next Change:' && printf '%s' "1" || printf '%s' "0")
mentions_repo_file=0
mentions_expected_one=0
mentions_expected_two=0

case "$scenario" in
  cors-credentials-wildcard)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'server/cors.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'Access-Control-Allow-Origin' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -qi 'credentials' && printf '%s' "1" || printf '%s' "0")
    ;;
  cookie-samesite-none-without-secure)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'server/session.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'SameSite=None' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q 'Secure' && printf '%s' "1" || printf '%s' "0")
    ;;
  cors-authorization-header-missing)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'server/cors.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'Authorization' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q 'Access-Control-Allow-Headers' && printf '%s' "1" || printf '%s' "0")
    ;;
esac

stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$repo_scan_ran" -eq 1 ] && [ "$runtime_check_ran" -eq 1 ] && [ "$web_fetch_emitted" -eq 1 ] && [ "$workspace_unchanged" -eq 1 ] && [ "$has_repo_evidence" -eq 1 ] && [ "$has_runtime_evidence" -eq 1 ] && [ "$has_current_standard" -eq 1 ] && [ "$has_standards_answer" -eq 1 ] && [ "$has_next_change" -eq 1 ] && [ "$mentions_repo_file" -eq 1 ] && [ "$mentions_expected_one" -eq 1 ] && [ "$mentions_expected_two" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"repo_scan_ran":%s,"runtime_check_ran":%s,"web_fetch_emitted":%s,"workspace_unchanged":%s,"has_repo_evidence":%s,"has_runtime_evidence":%s,"has_current_standard":%s,"has_standards_answer":%s,"has_next_change":%s,"mentions_repo_file":%s,"mentions_expected_one":%s,"mentions_expected_two":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$repo_scan_ran" "$runtime_check_ran" "$web_fetch_emitted" "$workspace_unchanged" "$has_repo_evidence" "$has_runtime_evidence" "$has_current_standard" "$has_standards_answer" "$has_next_change" "$mentions_repo_file" "$mentions_expected_one" "$mentions_expected_two" "$stream_line_count" > "$json_file"

{
  printf '# Standards Grounded Answer Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- `repo-scan.sh` ran: %s\n' "$repo_scan_ran"
  printf -- '- `runtime-check.sh` ran: %s\n' "$runtime_check_ran"
  printf -- '- Web fetch emitted: %s\n' "$web_fetch_emitted"
  printf -- '- Workspace unchanged: %s\n' "$workspace_unchanged"
  printf -- '- Repo Evidence section: %s\n' "$has_repo_evidence"
  printf -- '- Runtime Evidence section: %s\n' "$has_runtime_evidence"
  printf -- '- Current Standard section: %s\n' "$has_current_standard"
  printf -- '- Standards Answer section: %s\n' "$has_standards_answer"
  printf -- '- Next Change section: %s\n' "$has_next_change"
  printf -- '- Mentions repo file: %s\n' "$mentions_repo_file"
  printf -- '- Mentions expected standard term one: %s\n' "$mentions_expected_one"
  printf -- '- Mentions expected standard term two: %s\n' "$mentions_expected_two"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
