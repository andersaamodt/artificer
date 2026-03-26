#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="current-api-migration-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"
DEFAULT_DOC_URL="https://docs.pydantic.dev/latest/migration/"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for current-api-migration probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for current-api-migration probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: current-api-migration-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH] [--doc-url URL]

Runs a live bounded freshness-sensitive migration probe against a demo workspace
and checks whether Artificer can combine repo evidence with the current official
migration guide into one concrete migration answer without editing files.
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

create_workspace_for_scenario() {
  scenario=$1
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/app"
  case "$scenario" in
    parse-obj-migration)
      cat > "$workspace_dir/app/user_loader.py" <<'EOF_PY'
from pydantic import BaseModel


class User(BaseModel):
    id: int
    email: str


def load_user(payload):
    return User.parse_obj(payload)
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=app/user_loader.py'
printf '%s\n' 'repo_old_method=parse_obj'
printf '%s\n' 'repo_call=User.parse_obj(payload)'
EOF_SH
      ;;
    dict-migration)
      cat > "$workspace_dir/app/user_dump.py" <<'EOF_PY'
from pydantic import BaseModel


class User(BaseModel):
    id: int
    email: str


def dump_user(user):
    return user.dict()
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=app/user_dump.py'
printf '%s\n' 'repo_old_method=dict'
printf '%s\n' 'repo_call=user.dict()'
EOF_SH
      ;;
    from-orm-migration)
      cat > "$workspace_dir/app/user_record.py" <<'EOF_PY'
from pydantic import BaseModel


class User(BaseModel):
    id: int
    email: str


def load_record(record):
    return User.from_orm(record)
EOF_PY
      cat > "$workspace_dir/bin/repo-scan.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'repo_file=app/user_record.py'
printf '%s\n' 'repo_old_method=from_orm'
printf '%s\n' 'repo_call=User.from_orm(record)'
EOF_SH
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  chmod +x "$workspace_dir/bin/repo-scan.sh"
  cat > "$workspace_dir/README.md" <<EOF_README
# Current API Migration Demo

Scenario: $scenario
Use ./bin/repo-scan.sh for repo evidence and the current official migration guide for source grounding. Do not edit files.
EOF_README
}

label=$DEFAULT_LABEL
scenario="parse-obj-migration"
prompt_override=""
prompt_file=""
doc_url=$DEFAULT_DOC_URL
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
[ -n "$model" ] || { echo "No installed models available; current-api-migration probe cannot run." >&2; exit 1; }

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
Investigate this bounded current API migration question in the workspace. Use `./bin/repo-scan.sh` for repo evidence and the current official migration guide at __DOC_URL__ for source grounding. Do not edit files. Return exactly five lines starting with: Repo Evidence, Current Source, Migration Change, Root Cause, Next Change.
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
web_fetch_emitted=$(printf '%s\n' "$stream_text" | grep -q 'Quick-mode web fetch:' && printf '%s' "1" || printf '%s' "0")
workspace_unchanged=$(diff -qr "$baseline_dir" "$tmp_ws" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
has_repo_evidence=$(printf '%s\n' "$assistant_text" | grep -q '^Repo Evidence:' && printf '%s' "1" || printf '%s' "0")
has_current_source=$(printf '%s\n' "$assistant_text" | grep -q '^Current Source:' && printf '%s' "1" || printf '%s' "0")
has_migration_change=$(printf '%s\n' "$assistant_text" | grep -q '^Migration Change:' && printf '%s' "1" || printf '%s' "0")
has_root_cause=$(printf '%s\n' "$assistant_text" | grep -q '^Root Cause:' && printf '%s' "1" || printf '%s' "0")
has_next_change=$(printf '%s\n' "$assistant_text" | grep -q '^Next Change:' && printf '%s' "1" || printf '%s' "0")
mentions_repo_file=0
mentions_expected_one=0
mentions_expected_two=0

case "$scenario" in
  parse-obj-migration)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'app/user_loader.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'parse_obj' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q 'model_validate' && printf '%s' "1" || printf '%s' "0")
    ;;
  dict-migration)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'app/user_dump.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'dict' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q 'model_dump' && printf '%s' "1" || printf '%s' "0")
    ;;
  from-orm-migration)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'app/user_record.py' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'from_orm' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -q 'from_attributes=True' && printf '%s' "1" || printf '%s' "0")
    ;;
esac

stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$repo_scan_ran" -eq 1 ] && [ "$web_fetch_emitted" -eq 1 ] && [ "$workspace_unchanged" -eq 1 ] && [ "$has_repo_evidence" -eq 1 ] && [ "$has_current_source" -eq 1 ] && [ "$has_migration_change" -eq 1 ] && [ "$has_root_cause" -eq 1 ] && [ "$has_next_change" -eq 1 ] && [ "$mentions_repo_file" -eq 1 ] && [ "$mentions_expected_one" -eq 1 ] && [ "$mentions_expected_two" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"repo_scan_ran":%s,"web_fetch_emitted":%s,"workspace_unchanged":%s,"has_repo_evidence":%s,"has_current_source":%s,"has_migration_change":%s,"has_root_cause":%s,"has_next_change":%s,"mentions_repo_file":%s,"mentions_expected_one":%s,"mentions_expected_two":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$repo_scan_ran" "$web_fetch_emitted" "$workspace_unchanged" "$has_repo_evidence" "$has_current_source" "$has_migration_change" "$has_root_cause" "$has_next_change" "$mentions_repo_file" "$mentions_expected_one" "$mentions_expected_two" "$stream_line_count" > "$json_file"

{
  printf '# Current API Migration Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- `repo-scan.sh` ran: %s\n' "$repo_scan_ran"
  printf -- '- Web fetch emitted: %s\n' "$web_fetch_emitted"
  printf -- '- Workspace unchanged: %s\n' "$workspace_unchanged"
  printf -- '- Repo Evidence section: %s\n' "$has_repo_evidence"
  printf -- '- Current Source section: %s\n' "$has_current_source"
  printf -- '- Migration Change section: %s\n' "$has_migration_change"
  printf -- '- Root Cause section: %s\n' "$has_root_cause"
  printf -- '- Next Change section: %s\n' "$has_next_change"
  printf -- '- Mentions repo file: %s\n' "$mentions_repo_file"
  printf -- '- Mentions expected old API: %s\n' "$mentions_expected_one"
  printf -- '- Mentions expected new API: %s\n' "$mentions_expected_two"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
