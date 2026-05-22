#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="remote-boundary-rollout-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for remote boundary rollout probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: remote-boundary-rollout-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded remote boundary rollout probe against a demo workspace and checks
whether Artificer can open the bastion tunnel, deploy the private canary target first,
then deploy the private fleet target while keeping rollback intact.
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

create_remote_boundary_rollout_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/remote" "$workspace_dir/state"
  cat > "$workspace_dir/remote/boundary.env" <<'EOF_CFG'
BASTION_HOST=demo-bastion-1
CANARY_PRIVATE_HOST=demo-app-private-a
FLEET_PRIVATE_HOST=demo-app-private-b
TARGET_RELEASE=2026.03.22
APPROVED_RELEASE=2026.03.10
TUNNEL_READY=0
CANARY_READY=0
FLEET_READY=0
READ_ONLY=0
ROLLOUT_STATE=stale
EOF_CFG
  cp "$workspace_dir/remote/boundary.env" "$workspace_dir/remote/boundary.env.bak"
  cat > "$workspace_dir/bin/ssh-bastion.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/boundary.env"
state_file="$ROOT_DIR/state/boundary.tunnel"
case "$subcommand" in
  status)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$TUNNEL_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_bastion=ready host=$BASTION_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "boundary_bastion=stale host=$BASTION_HOST release=$TARGET_RELEASE"
      printf '%s\n' "expected_fix=APPROVED_RELEASE=$TARGET_RELEASE TUNNEL_READY=1 READ_ONLY=1"
    fi
    ;;
  tunnel)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$TUNNEL_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "$TARGET_RELEASE" > "$state_file"
      printf '%s\n' "boundary_tunnel=ok host=$BASTION_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "blocked" > "$state_file"
      printf '%s\n' "boundary_tunnel=failed host=$BASTION_HOST release=$TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    tunneled=$(cat "$state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$tunneled" = "$TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_bastion_health=ok host=$BASTION_HOST release=$TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "boundary_bastion_health=failed host=$BASTION_HOST release=$TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-bastion.sh status|tunnel|health" >&2
    exit 2
    ;;
esac
EOF_BIN
  cat > "$workspace_dir/bin/ssh-private-canary.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/boundary.env"
tunnel_state_file="$ROOT_DIR/state/boundary.tunnel"
canary_state_file="$ROOT_DIR/state/private.canary.release"
case "$subcommand" in
  status)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_canary=ready host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "boundary_canary=stale host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
      printf '%s\n' "expected_fix=APPROVED_RELEASE=$TARGET_RELEASE CANARY_READY=1 READ_ONLY=1"
    fi
    ;;
  deploy)
    tunneled=$(cat "$tunnel_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$CANARY_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$tunneled" = "$TARGET_RELEASE" ]; then
      printf '%s\n' "$TARGET_RELEASE" > "$canary_state_file"
      printf '%s\n' "boundary_canary_deploy=ok host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "blocked" > "$canary_state_file"
      printf '%s\n' "boundary_canary_deploy=failed host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    deployed=$(cat "$canary_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$deployed" = "$TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_canary_health=ok host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "boundary_canary_health=failed host=$CANARY_PRIVATE_HOST release=$TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-private-canary.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN
  cat > "$workspace_dir/bin/ssh-private-fleet.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/boundary.env"
canary_state_file="$ROOT_DIR/state/private.canary.release"
fleet_state_file="$ROOT_DIR/state/private.fleet.release"
case "$subcommand" in
  status)
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_fleet=ready host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "boundary_fleet=stale host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
      printf '%s\n' "expected_fix=APPROVED_RELEASE=$TARGET_RELEASE FLEET_READY=1 READ_ONLY=1"
    fi
    ;;
  deploy)
    canary_release=$(cat "$canary_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$APPROVED_RELEASE" = "$TARGET_RELEASE" ] && [ "$FLEET_READY" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$canary_release" = "$TARGET_RELEASE" ]; then
      printf '%s\n' "$TARGET_RELEASE" > "$fleet_state_file"
      printf '%s\n' "boundary_fleet_deploy=ok host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
    else
      printf '%s\n' "blocked" > "$fleet_state_file"
      printf '%s\n' "boundary_fleet_deploy=failed host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
      exit 1
    fi
    ;;
  health)
    deployed=$(cat "$fleet_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$deployed" = "$TARGET_RELEASE" ] && [ "$READ_ONLY" = "1" ]; then
      printf '%s\n' "boundary_fleet_health=ok host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
      exit 0
    fi
    printf '%s\n' "boundary_fleet_health=failed host=$FLEET_PRIVATE_HOST release=$TARGET_RELEASE"
    exit 1
    ;;
  *)
    echo "usage: ssh-private-fleet.sh status|deploy|health" >&2
    exit 2
    ;;
esac
EOF_BIN
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/remote/boundary.env.bak" "$ROOT_DIR/remote/boundary.env"
printf '%s\n' "rollback_status=ready"
EOF_BIN
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Remote Boundary Rollout Demo

Use the bastion and private-target helpers in `bin/` to recover the bounded boundary rollout.
The rollout is healthy only when the bastion tunnel opens first, the private canary target deploys second,
and the private fleet target deploys last while all hosts remain in read-only mode and rollback stays intact.
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
[ -n "$model" ] || { echo "No installed models available; remote boundary rollout probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_remote_boundary_rollout_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded remote boundary rollout in this workspace. Use `./bin/ssh-bastion.sh`, `./bin/ssh-private-canary.sh`, `./bin/ssh-private-fleet.sh`, and `./bin/rollback.sh`. Make the smallest safe release-config fix so the bastion tunnel opens first, the private canary target deploys second, the private fleet target deploys last, rerun the health checks, keep rollback intact, and do not widen beyond this one boundary rollout. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=160 post_api_json_with_timeout "$run_body" 95)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

config_fixed=0
if grep -q '^APPROVED_RELEASE=2026.03.22$' "$tmp_ws/remote/boundary.env" \
  && grep -q '^TUNNEL_READY=1$' "$tmp_ws/remote/boundary.env" \
  && grep -q '^CANARY_READY=1$' "$tmp_ws/remote/boundary.env" \
  && grep -q '^FLEET_READY=1$' "$tmp_ws/remote/boundary.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/remote/boundary.env"; then
  config_fixed=1
fi

bastion_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh status")) | if . then 1 else 0 end')
bastion_tunnel_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh tunnel")) | if . then 1 else 0 end')
bastion_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-bastion.sh health")) | if . then 1 else 0 end')
canary_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-canary.sh status")) | if . then 1 else 0 end')
canary_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-canary.sh deploy")) | if . then 1 else 0 end')
canary_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-canary.sh health")) | if . then 1 else 0 end')
fleet_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-fleet.sh status")) | if . then 1 else 0 end')
fleet_deploy_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-fleet.sh deploy")) | if . then 1 else 0 end')
fleet_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-private-fleet.sh health")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
bastion_health_ok=$(sh "$tmp_ws/bin/ssh-bastion.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
canary_health_ok=$(sh "$tmp_ws/bin/ssh-private-canary.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
fleet_health_ok=$(sh "$tmp_ws/bin/ssh-private-fleet.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] && cmp -s "$baseline_dir/remote/boundary.env.bak" "$tmp_ws/remote/boundary.env.bak" && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] \
  && [ "$bastion_status_ran" -eq 1 ] && [ "$bastion_tunnel_ran" -eq 1 ] && [ "$bastion_health_ran" -eq 1 ] \
  && [ "$canary_status_ran" -eq 1 ] && [ "$canary_deploy_ran" -eq 1 ] && [ "$canary_health_ran" -eq 1 ] \
  && [ "$fleet_status_ran" -eq 1 ] && [ "$fleet_deploy_ran" -eq 1 ] && [ "$fleet_health_ran" -eq 1 ] \
  && [ "$bastion_health_ok" -eq 1 ] && [ "$canary_health_ok" -eq 1 ] && [ "$fleet_health_ok" -eq 1 ] \
  && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] \
  && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"bastion_status_ran":%s,"bastion_tunnel_ran":%s,"bastion_health_ran":%s,"canary_status_ran":%s,"canary_deploy_ran":%s,"canary_health_ran":%s,"fleet_status_ran":%s,"fleet_deploy_ran":%s,"fleet_health_ran":%s,"bastion_health_ok":%s,"canary_health_ok":%s,"fleet_health_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$bastion_status_ran" "$bastion_tunnel_ran" "$bastion_health_ran" "$canary_status_ran" "$canary_deploy_ran" "$canary_health_ran" "$fleet_status_ran" "$fleet_deploy_ran" "$fleet_health_ran" "$bastion_health_ok" "$canary_health_ok" "$fleet_health_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Remote Boundary Rollout Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `ssh-bastion.sh status` ran: %s\n' "$bastion_status_ran"
  printf -- '- `ssh-bastion.sh tunnel` ran: %s\n' "$bastion_tunnel_ran"
  printf -- '- `ssh-bastion.sh health` ran: %s\n' "$bastion_health_ran"
  printf -- '- `ssh-private-canary.sh status` ran: %s\n' "$canary_status_ran"
  printf -- '- `ssh-private-canary.sh deploy` ran: %s\n' "$canary_deploy_ran"
  printf -- '- `ssh-private-canary.sh health` ran: %s\n' "$canary_health_ran"
  printf -- '- `ssh-private-fleet.sh status` ran: %s\n' "$fleet_status_ran"
  printf -- '- `ssh-private-fleet.sh deploy` ran: %s\n' "$fleet_deploy_ran"
  printf -- '- `ssh-private-fleet.sh health` ran: %s\n' "$fleet_health_ran"
  printf -- '- Bastion health now passes: %s\n' "$bastion_health_ok"
  printf -- '- Private canary health now passes: %s\n' "$canary_health_ok"
  printf -- '- Private fleet health now passes: %s\n' "$fleet_health_ok"
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
