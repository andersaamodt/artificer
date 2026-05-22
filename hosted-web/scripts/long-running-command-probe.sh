#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="long-running-command-polling-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for long-running command probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: long-running-command-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded long-running command probe against a demo job workspace and checks
whether Artificer can poll, checkpoint, finalize, verify, and keep rollback intact.
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

create_long_running_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/job" "$workspace_dir/state"
  cat > "$workspace_dir/job/run.env" <<'EOF_CFG'
CURRENT_STEP=0
TARGET_STEP=3
CHECKPOINT_READY=0
ALLOW_FINALIZE=0
READ_ONLY=0
EOF_CFG
  cp "$workspace_dir/job/run.env" "$workspace_dir/job/run.env.bak"
  cat > "$workspace_dir/bin/poll.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/job/run.env"
state_file="$ROOT_DIR/state/poll.count"
count=$(cat "$state_file" 2>/dev/null || printf '%s' '0')
count=$((count + 1))
printf '%s\n' "$count" > "$state_file"
if [ "$count" -ge "$TARGET_STEP" ] && [ "$CHECKPOINT_READY" = "1" ] && [ "$ALLOW_FINALIZE" = "1" ] && [ "$READ_ONLY" = "1" ]; then
  printf '%s\n' "poll_state=ready step=$count target=$TARGET_STEP"
else
  printf '%s\n' "poll_state=waiting step=$count target=$TARGET_STEP"
  printf '%s\n' "expected_fix=CHECKPOINT_READY=1 ALLOW_FINALIZE=1 READ_ONLY=1"
fi
EOF_SH
  cat > "$workspace_dir/bin/checkpoint.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/job/run.env"
if [ "$CHECKPOINT_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
  printf '%s\n' "ready" > "$ROOT_DIR/state/checkpoint.status"
  printf '%s\n' "checkpoint=ok"
else
  printf '%s\n' "blocked" > "$ROOT_DIR/state/checkpoint.status"
  printf '%s\n' "checkpoint=failed"
  exit 1
fi
EOF_SH
  cat > "$workspace_dir/bin/finalize.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/job/run.env"
count=$(cat "$ROOT_DIR/state/poll.count" 2>/dev/null || printf '%s' '0')
checkpoint=$(cat "$ROOT_DIR/state/checkpoint.status" 2>/dev/null || printf '%s' 'missing')
if [ "$ALLOW_FINALIZE" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$checkpoint" = "ready" ] && [ "$count" -ge "$TARGET_STEP" ]; then
  printf '%s\n' "done" > "$ROOT_DIR/state/final.status"
  printf '%s\n' "finalize=ok step=$count target=$TARGET_STEP"
else
  printf '%s\n' "blocked" > "$ROOT_DIR/state/final.status"
  printf '%s\n' "finalize=failed step=$count target=$TARGET_STEP"
  exit 1
fi
EOF_SH
  cat > "$workspace_dir/bin/verify.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/job/run.env"
final_status=$(cat "$ROOT_DIR/state/final.status" 2>/dev/null || printf '%s' 'missing')
if [ "$READ_ONLY" = "1" ] && [ "$final_status" = "done" ]; then
  printf '%s\n' "verify=ok"
  exit 0
fi
printf '%s\n' "verify=failed"
exit 1
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/job/run.env.bak" "$ROOT_DIR/job/run.env"
printf '%s\n' "rollback_status=ready"
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Long-Running Command Demo

Use the scripts in `bin/` to poll, checkpoint, finalize, verify, and roll back the bounded job.
The job is ready only after the final poll reaches the target step, checkpointing is enabled, and finalize/verify pass in read-only mode.
EOF_README
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
[ -n "$model" ] || { echo "No installed models available; long-running command probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_long_running_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded long-running command in this workspace. Use `./bin/poll.sh`, `./bin/checkpoint.sh`, `./bin/finalize.sh`, `./bin/verify.sh`, and `./bin/rollback.sh`. Make the smallest safe job-config fix so checkpointing is enabled, poll until the job is ready, finalize only when the bounded job is actually ready, rerun verification, keep rollback intact, and do not widen beyond this one job. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi

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

config_fixed=0
if grep -q '^CHECKPOINT_READY=1$' "$tmp_ws/job/run.env" \
  && grep -q '^ALLOW_FINALIZE=1$' "$tmp_ws/job/run.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/job/run.env"; then
  config_fixed=1
fi

poll_run_count=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | map(select(contains("bin/poll.sh"))) | length')
checkpoint_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/checkpoint.sh")) | if . then 1 else 0 end')
finalize_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/finalize.sh")) | if . then 1 else 0 end')
verify_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/verify.sh")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
verify_ok=$(sh "$tmp_ws/bin/verify.sh" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] && cmp -s "$baseline_dir/job/run.env.bak" "$tmp_ws/job/run.env.bak" && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$poll_run_count" -ge 3 ] && [ "$checkpoint_ran" -eq 1 ] && [ "$finalize_ran" -eq 1 ] && [ "$verify_ran" -eq 1 ] && [ "$verify_ok" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"poll_run_count":%s,"checkpoint_ran":%s,"finalize_ran":%s,"verify_ran":%s,"verify_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$poll_run_count" "$checkpoint_ran" "$finalize_ran" "$verify_ran" "$verify_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Long-Running Command Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `poll.sh` run count: %s\n' "$poll_run_count"
  printf -- '- `checkpoint.sh` ran: %s\n' "$checkpoint_ran"
  printf -- '- `finalize.sh` ran: %s\n' "$finalize_ran"
  printf -- '- `verify.sh` ran: %s\n' "$verify_ran"
  printf -- '- Verify now passes: %s\n' "$verify_ok"
  printf -- '- Rollback referenced: %s\n' "$rollback_ref"
  printf -- '- Rollback intact: %s\n' "$rollback_intact"
  printf -- '- Outcome section: %s\n' "$has_outcome"
  printf -- '- Verification section: %s\n' "$has_verify"
  printf -- '- Risks section: %s\n' "$has_risks"
  printf -- '- Next Improvement section: %s\n' "$has_next"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
