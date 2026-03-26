#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="remote-multi-host-rollout-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for remote multi-host rollout probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: remote-multi-host-rollout-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded staged rollout probe against a demo workspace and checks
whether Artificer can deploy canary first, verify it, then deploy the fleet host
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

create_remote_multi_host_rollout_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/remote" "$workspace_dir/state"
  cat > "$workspace_dir/remote/rollout.env" <<'EOF_CFG'
CANARY_HOST=demo-app-1
FLEET_HOST=demo-app-2
TARGET_RELEASE=2026.03.22
APPROVED_RELEASE=2026.03.10
CANARY_READY=0
FLEET_READY=0
READ_ONLY=0
ROLLOUT_STAGE=stale
EOF_CFG
  cp "$workspace_dir/remote/rollout.env" "$workspace_dir/remote/rollout.env.bak"
  cat > "$workspace_dir/bin/ssh-canary.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/rollout.env"
state_file="$ROOT_DIR/state/canary.release"
case "$subcommand" in
  status)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "canary_rollout=ready host=$CANARY_HOST target=$TARGET_RELEASE"
    else
      printf '%s\n' "canary_rollout=stale host=$CANARY_HOST target=$TARGET_RELEASE"
      printf '%s\n' "expected_fix=APPROVED_RELEASE=$TARGET_RELEASE CANARY_READY=1 READ_ONLY=1"
    fi
    ;;
  deploy)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "$TARGET_RELEASE" > "$state_file"
      printf '%s\n' "canary_deploy=ok host=$CANARY_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "blocked" > "$state_file"
      printf '%s\n' "canary_deploy=failed host=$CANARY_HOST release=$TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    deployed=$(cat "$state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$deployed" = "$TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "canary_health=ok host=$CANARY_HOST release=$TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "canary_health=failed host=$CANARY_HOST release=$TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-canary.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/ssh-fleet.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/rollout.env"
canary_state_file="$ROOT_DIR/state/canary.release"
fleet_state_file="$ROOT_DIR/state/fleet.release"
case "$subcommand" in
  status)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "fleet_rollout=ready host=$FLEET_HOST target=$TARGET_RELEASE"
    else
      printf '%s\n' "fleet_rollout=stale host=$FLEET_HOST target=$TARGET_RELEASE"
      printf '%s\n' "expected_fix=APPROVED_RELEASE=$TARGET_RELEASE FLEET_READY=1 READ_ONLY=1"
    fi
    ;;
  deploy)
    canary_release=$(cat "$canary_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$canary_release" = "$TARGET_RELEASE" ]; then
      printf '%s\n' "$TARGET_RELEASE" > "$fleet_state_file"
      printf '%s\n' "fleet_deploy=ok host=$FLEET_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "blocked" > "$fleet_state_file"
      printf '%s\n' "fleet_deploy=failed host=$FLEET_HOST release=$TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    deployed=$(cat "$fleet_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$deployed" = "$TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "fleet_health=ok host=$FLEET_HOST release=$TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "fleet_health=failed host=$FLEET_HOST release=$TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-fleet.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/remote/rollout.env.bak" "$ROOT_DIR/remote/rollout.env"
printf '%s\n' "rollback_status=ready"
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Remote Multi-Host Rollout Demo

Use `bin/ssh-canary.sh` and `bin/ssh-fleet.sh` to recover the bounded staged rollout.
The rollout is healthy only when the canary deploy succeeds first, the fleet host deploys after that,
and both hosts pass health in read-only mode during the bounded rollout.
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
[ -n "$model" ] || { echo "No installed models available; remote multi-host rollout probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_remote_multi_host_rollout_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded staged multi-host rollout in this workspace. Use `./bin/ssh-canary.sh status`, `./bin/ssh-fleet.sh status`, `./bin/ssh-canary.sh deploy`, `./bin/ssh-canary.sh health`, `./bin/ssh-fleet.sh deploy`, `./bin/ssh-fleet.sh health`, and `./bin/rollback.sh`. Make the smallest safe rollout-config fix so the canary deploys first, verify canary health, then deploy the fleet host, rerun fleet health, keep rollback intact, and do not widen beyond this one canary host plus one fleet host. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
if grep -q '^APPROVED_RELEASE=2026.03.22$' "$tmp_ws/remote/rollout.env" \
  && grep -q '^CANARY_READY=1$' "$tmp_ws/remote/rollout.env" \
  && grep -q '^FLEET_READY=1$' "$tmp_ws/remote/rollout.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/remote/rollout.env" \
  && grep -q '^ROLLOUT_STAGE=staged$' "$tmp_ws/remote/rollout.env"; then
  config_fixed=1
fi

canary_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-canary.sh status")) | if . then 1 else 0 end')
fleet_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-fleet.sh status")) | if . then 1 else 0 end')
canary_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-canary.sh deploy")) | if . then 1 else 0 end')
canary_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-canary.sh health")) | if . then 1 else 0 end')
fleet_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-fleet.sh deploy")) | if . then 1 else 0 end')
fleet_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-fleet.sh health")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
canary_health_ok=$(sh "$tmp_ws/bin/ssh-canary.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
fleet_health_ok=$(sh "$tmp_ws/bin/ssh-fleet.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] && cmp -s "$baseline_dir/remote/rollout.env.bak" "$tmp_ws/remote/rollout.env.bak" && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$canary_status_ran" -eq 1 ] && [ "$fleet_status_ran" -eq 1 ] && [ "$canary_deploy_ran" -eq 1 ] && [ "$canary_health_ran" -eq 1 ] && [ "$fleet_deploy_ran" -eq 1 ] && [ "$fleet_health_ran" -eq 1 ] && [ "$canary_health_ok" -eq 1 ] && [ "$fleet_health_ok" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"canary_status_ran":%s,"fleet_status_ran":%s,"canary_deploy_ran":%s,"canary_health_ran":%s,"fleet_deploy_ran":%s,"fleet_health_ran":%s,"canary_health_ok":%s,"fleet_health_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$canary_status_ran" "$fleet_status_ran" "$canary_deploy_ran" "$canary_health_ran" "$fleet_deploy_ran" "$fleet_health_ran" "$canary_health_ok" "$fleet_health_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Remote Multi-Host Rollout Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `ssh-canary.sh status` ran: %s\n' "$canary_status_ran"
  printf -- '- `ssh-fleet.sh status` ran: %s\n' "$fleet_status_ran"
  printf -- '- `ssh-canary.sh deploy` ran: %s\n' "$canary_deploy_ran"
  printf -- '- `ssh-canary.sh health` ran: %s\n' "$canary_health_ran"
  printf -- '- `ssh-fleet.sh deploy` ran: %s\n' "$fleet_deploy_ran"
  printf -- '- `ssh-fleet.sh health` ran: %s\n' "$fleet_health_ran"
  printf -- '- Canary health now passes: %s\n' "$canary_health_ok"
  printf -- '- Fleet health now passes: %s\n' "$fleet_health_ok"
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
