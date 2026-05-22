#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="remote-bastion-cutover-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for remote bastion cutover probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: remote-bastion-cutover-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded bastion cutover probe against a demo workspace and checks
whether Artificer can repair the bastion/private-host config, establish the
bastion tunnel, cut traffic over to the target private host, and verify health
while keeping rollback intact.
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

create_remote_bastion_cutover_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/remote" "$workspace_dir/state"
  cat > "$workspace_dir/remote/bastion.env" <<'EOF_CFG'
BASTION_HOST=demo-bastion-1
CURRENT_PRIVATE_HOST=demo-app-private-a
TARGET_PRIVATE_HOST=demo-app-private-b
APPROVED_PRIVATE_HOST=demo-app-private-a
BASTION_READY=0
PRIVATE_READY=0
READ_ONLY=0
CUTOVER_STATE=stale
EOF_CFG
  cp "$workspace_dir/remote/bastion.env" "$workspace_dir/remote/bastion.env.bak"
  cat > "$workspace_dir/bin/ssh-bastion.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/bastion.env"
state_file="$ROOT_DIR/state/bastion.tunnel"
case "$subcommand" in
  status)
    if [ "$APPROVED_PRIVATE_HOST" = "$TARGET_PRIVATE_HOST" ] && [ "$BASTION_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "bastion_state=ready host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
    else
      printf '%s\n' "bastion_state=stale host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
      printf '%s\n' "expected_fix=APPROVED_PRIVATE_HOST=$TARGET_PRIVATE_HOST BASTION_READY=1 READ_ONLY=1"
    fi
    ;;
  tunnel)
    if [ "$APPROVED_PRIVATE_HOST" = "$TARGET_PRIVATE_HOST" ] && [ "$BASTION_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "$TARGET_PRIVATE_HOST" > "$state_file"
      printf '%s\n' "bastion_tunnel=ok host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
    else
      printf '%s\n' "blocked" > "$state_file"
      printf '%s\n' "bastion_tunnel=failed host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
      exit 1
    fi
    ;;
  health)
    tunneled=$(cat "$state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$tunneled" = "$TARGET_PRIVATE_HOST" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "bastion_health=ok host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
      exit 0
    fi
    printf '%s\n' "bastion_health=failed host=$BASTION_HOST target=$TARGET_PRIVATE_HOST"
    exit 1
    ;;
  *)
    echo "usage: ssh-bastion.sh status|tunnel|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/ssh-private.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/bastion.env"
tunnel_state_file="$ROOT_DIR/state/bastion.tunnel"
private_state_file="$ROOT_DIR/state/private.cutover"
case "$subcommand" in
  status)
    if [ "$CURRENT_PRIVATE_HOST" = "$TARGET_PRIVATE_HOST" ] && [ "$PRIVATE_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "private_cutover=ready host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
    else
      printf '%s\n' "private_cutover=stale host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
      printf '%s\n' "expected_fix=CURRENT_PRIVATE_HOST=$TARGET_PRIVATE_HOST PRIVATE_READY=1 READ_ONLY=1"
    fi
    ;;
  cutover)
    tunneled=$(cat "$tunnel_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$CURRENT_PRIVATE_HOST" = "$TARGET_PRIVATE_HOST" ] && [ "$PRIVATE_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$tunneled" = "$TARGET_PRIVATE_HOST" ]; then
      printf '%s\n' "$TARGET_PRIVATE_HOST" > "$private_state_file"
      printf '%s\n' "private_cutover=ok host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
    else
      printf '%s\n' "blocked" > "$private_state_file"
      printf '%s\n' "private_cutover=failed host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
      exit 1
    fi
    ;;
  health)
    cutover_target=$(cat "$private_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$cutover_target" = "$TARGET_PRIVATE_HOST" ] && [ "$CURRENT_PRIVATE_HOST" = "$TARGET_PRIVATE_HOST" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "private_health=ok host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
      exit 0
    fi
    printf '%s\n' "private_health=failed host=$CURRENT_PRIVATE_HOST target=$TARGET_PRIVATE_HOST"
    exit 1
    ;;
  *)
    echo "usage: ssh-private.sh status|cutover|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/remote/bastion.env.bak" "$ROOT_DIR/remote/bastion.env"
printf '%s\n' "rollback_status=ready"
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Remote Bastion Cutover Demo

Use `bin/ssh-bastion.sh` and `bin/ssh-private.sh` to recover the bounded bastion cutover.
The cutover is healthy only when the bastion tunnel is ready first, the target private host is approved and cut over,
and both hosts pass health in read-only mode while rollback stays intact.
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
[ -n "$model" ] || { echo "No installed models available; remote bastion cutover probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_remote_bastion_cutover_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded bastion cutover in this workspace. Use `./bin/ssh-bastion.sh status`, `./bin/ssh-private.sh status`, `./bin/ssh-bastion.sh tunnel`, `./bin/ssh-bastion.sh health`, `./bin/ssh-private.sh cutover`, `./bin/ssh-private.sh health`, and `./bin/rollback.sh`. Make the smallest safe bastion-config fix so the bastion tunnel is ready first, cut traffic over to the target private host, rerun both health checks, keep rollback intact, and do not widen beyond this one bastion host plus one target private host. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
if grep -q '^CURRENT_PRIVATE_HOST=demo-app-private-b$' "$tmp_ws/remote/bastion.env" \
  && grep -q '^APPROVED_PRIVATE_HOST=demo-app-private-b$' "$tmp_ws/remote/bastion.env" \
  && grep -q '^BASTION_READY=1$' "$tmp_ws/remote/bastion.env" \
  && grep -q '^PRIVATE_READY=1$' "$tmp_ws/remote/bastion.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/remote/bastion.env" \
  && grep -q '^CUTOVER_STATE=ready$' "$tmp_ws/remote/bastion.env"; then
  config_fixed=1
fi

bastion_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh status")) | if . then 1 else 0 end')
private_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private.sh status")) | if . then 1 else 0 end')
bastion_tunnel_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh tunnel")) | if . then 1 else 0 end')
bastion_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh health")) | if . then 1 else 0 end')
private_cutover_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private.sh cutover")) | if . then 1 else 0 end')
private_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private.sh health")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
bastion_health_ok=$(sh "$tmp_ws/bin/ssh-bastion.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
private_health_ok=$(sh "$tmp_ws/bin/ssh-private.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] && cmp -s "$baseline_dir/remote/bastion.env.bak" "$tmp_ws/remote/bastion.env.bak" && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$bastion_status_ran" -eq 1 ] && [ "$private_status_ran" -eq 1 ] && [ "$bastion_tunnel_ran" -eq 1 ] && [ "$bastion_health_ran" -eq 1 ] && [ "$private_cutover_ran" -eq 1 ] && [ "$private_health_ran" -eq 1 ] && [ "$bastion_health_ok" -eq 1 ] && [ "$private_health_ok" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"bastion_status_ran":%s,"private_status_ran":%s,"bastion_tunnel_ran":%s,"bastion_health_ran":%s,"private_cutover_ran":%s,"private_health_ran":%s,"bastion_health_ok":%s,"private_health_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$bastion_status_ran" "$private_status_ran" "$bastion_tunnel_ran" "$bastion_health_ran" "$private_cutover_ran" "$private_health_ran" "$bastion_health_ok" "$private_health_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Remote Bastion Cutover Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `ssh-bastion.sh status` ran: %s\n' "$bastion_status_ran"
  printf -- '- `ssh-private.sh status` ran: %s\n' "$private_status_ran"
  printf -- '- `ssh-bastion.sh tunnel` ran: %s\n' "$bastion_tunnel_ran"
  printf -- '- `ssh-bastion.sh health` ran: %s\n' "$bastion_health_ran"
  printf -- '- `ssh-private.sh cutover` ran: %s\n' "$private_cutover_ran"
  printf -- '- `ssh-private.sh health` ran: %s\n' "$private_health_ran"
  printf -- '- Bastion health now passes: %s\n' "$bastion_health_ok"
  printf -- '- Private host health now passes: %s\n' "$private_health_ok"
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
