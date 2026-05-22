#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="remote-multi-host-replica-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for remote multi-host probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: remote-multi-host-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded multi-host remote failover probe against a demo workspace and
checks whether Artificer can promote the replica, restart the app host, verify
both hosts, and keep rollback intact.
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

create_remote_multi_host_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/remote" "$workspace_dir/state"
  cat > "$workspace_dir/remote/topology.env" <<'EOF_CFG'
APP_HOST=demo-app-1
PRIMARY_DB_HOST=demo-db-1
REPLICA_DB_HOST=demo-db-2
APP_DB_HOST=demo-db-1
REPLICA_ROLE=replica
FAILOVER_READY=0
APP_READ_ONLY=0
EOF_CFG
  cp "$workspace_dir/remote/topology.env" "$workspace_dir/remote/topology.env.bak"
  cat > "$workspace_dir/bin/ssh-db.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/topology.env"
state_file="$ROOT_DIR/state/db.primary"
case "$subcommand" in
  status)
    if [ "$REPLICA_ROLE" = "primary" ] && [ "$FAILOVER_READY" = "1" ] && [ "$PRIMARY_DB_HOST" != "$REPLICA_DB_HOST" ]; then
      printf '%s\n' "db_failover=ready primary=$PRIMARY_DB_HOST replica=$REPLICA_DB_HOST"
    else
      printf '%s\n' "db_failover=stale primary=$PRIMARY_DB_HOST replica=$REPLICA_DB_HOST"
      printf '%s\n' "expected_fix=promote replica and mark failover ready"
    fi
    ;;
  promote)
    if [ "$REPLICA_ROLE" = "primary" ] && [ "$FAILOVER_READY" = "1" ] && [ "$PRIMARY_DB_HOST" != "$REPLICA_DB_HOST" ]; then
      printf '%s\n' "$PRIMARY_DB_HOST" > "$state_file"
      printf '%s\n' "db_promote=ok primary=$PRIMARY_DB_HOST"
    else
      printf '%s\n' "blocked" > "$state_file"
      printf '%s\n' "db_promote=failed primary=$PRIMARY_DB_HOST replica=$REPLICA_DB_HOST"
      exit 1
    fi
    ;;
  health)
    promoted=$(cat "$state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$promoted" = "$PRIMARY_DB_HOST" ] && [ "$REPLICA_ROLE" = "primary" ] && [ "$FAILOVER_READY" = "1" ]; then
      printf '%s\n' "db_health=ok primary=$PRIMARY_DB_HOST"
      exit 0
    fi
    printf '%s\n' "db_health=failed primary=$PRIMARY_DB_HOST"
    exit 1
    ;;
  *)
    echo "usage: ssh-db.sh status|promote|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/ssh-app.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
subcommand=${1:-}
. "$ROOT_DIR/remote/topology.env"
app_state_file="$ROOT_DIR/state/app.status"
db_state_file="$ROOT_DIR/state/db.primary"
case "$subcommand" in
  status)
    if [ "$APP_DB_HOST" = "$PRIMARY_DB_HOST" ] && [ "$APP_READ_ONLY" = "1" ]; then
      printf '%s\n' "app_route=ready app=$APP_HOST db=$APP_DB_HOST"
    else
      printf '%s\n' "app_route=stale app=$APP_HOST db=$APP_DB_HOST"
      printf '%s\n' "expected_fix=APP_DB_HOST should match promoted primary and APP_READ_ONLY=1"
    fi
    ;;
  restart)
    promoted=$(cat "$db_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$APP_DB_HOST" = "$PRIMARY_DB_HOST" ] && [ "$APP_READ_ONLY" = "1" ] && [ "$promoted" = "$PRIMARY_DB_HOST" ]; then
      printf '%s\n' "healthy" > "$app_state_file"
      printf '%s\n' "app_restart=ok app=$APP_HOST db=$APP_DB_HOST"
    else
      printf '%s\n' "degraded" > "$app_state_file"
      printf '%s\n' "app_restart=failed app=$APP_HOST db=$APP_DB_HOST"
      exit 1
    fi
    ;;
  health)
    app_state=$(cat "$app_state_file" 2>/dev/null || printf '%s' 'unknown')
    if [ "$app_state" = "healthy" ] && [ "$APP_DB_HOST" = "$PRIMARY_DB_HOST" ] && [ "$APP_READ_ONLY" = "1" ]; then
      printf '%s\n' "app_health=ok app=$APP_HOST db=$APP_DB_HOST"
      exit 0
    fi
    printf '%s\n' "app_health=failed app=$APP_HOST db=$APP_DB_HOST"
    exit 1
    ;;
  *)
    echo "usage: ssh-app.sh status|restart|health" >&2
    exit 2
    ;;
esac
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/remote/topology.env.bak" "$ROOT_DIR/remote/topology.env"
printf '%s\n' "rollback_status=ready"
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Remote Multi-Host Replica Demo

Use `bin/ssh-app.sh` and `bin/ssh-db.sh` to recover the bounded app-plus-replica pair.
The workspace is healthy only when the replica is promoted, the app points at the
new primary, and the app is restarted in read-only mode during the failover.
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
[ -n "$model" ] || { echo "No installed models available; remote multi-host probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_remote_multi_host_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded multi-host failover in this workspace. Use `./bin/ssh-app.sh status`, `./bin/ssh-db.sh status`, `./bin/ssh-db.sh promote`, `./bin/ssh-db.sh health`, `./bin/ssh-app.sh restart`, `./bin/ssh-app.sh health`, and `./bin/rollback.sh`. Make the smallest safe topology fix so the replica becomes the new primary, rerun both remote health checks, keep rollback intact, and do not widen beyond this one app host plus one replica host. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
if grep -q '^PRIMARY_DB_HOST=demo-db-2$' "$tmp_ws/remote/topology.env" \
  && grep -q '^REPLICA_DB_HOST=demo-db-1$' "$tmp_ws/remote/topology.env" \
  && grep -q '^APP_DB_HOST=demo-db-2$' "$tmp_ws/remote/topology.env" \
  && grep -q '^REPLICA_ROLE=primary$' "$tmp_ws/remote/topology.env" \
  && grep -q '^FAILOVER_READY=1$' "$tmp_ws/remote/topology.env" \
  && grep -q '^APP_READ_ONLY=1$' "$tmp_ws/remote/topology.env"; then
  config_fixed=1
fi

app_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-app.sh status")) | if . then 1 else 0 end')
db_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-db.sh status")) | if . then 1 else 0 end')
db_promote_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-db.sh promote")) | if . then 1 else 0 end')
db_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-db.sh health")) | if . then 1 else 0 end')
app_restart_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-app.sh restart")) | if . then 1 else 0 end')
app_health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/ssh-app.sh health")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
db_health_ok=$(sh "$tmp_ws/bin/ssh-db.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
app_health_ok=$(sh "$tmp_ws/bin/ssh-app.sh" health >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] && cmp -s "$baseline_dir/remote/topology.env.bak" "$tmp_ws/remote/topology.env.bak" && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$app_status_ran" -eq 1 ] && [ "$db_status_ran" -eq 1 ] && [ "$db_promote_ran" -eq 1 ] && [ "$db_health_ran" -eq 1 ] && [ "$app_restart_ran" -eq 1 ] && [ "$app_health_ran" -eq 1 ] && [ "$db_health_ok" -eq 1 ] && [ "$app_health_ok" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"app_status_ran":%s,"db_status_ran":%s,"db_promote_ran":%s,"db_health_ran":%s,"app_restart_ran":%s,"app_health_ran":%s,"db_health_ok":%s,"app_health_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$app_status_ran" "$db_status_ran" "$db_promote_ran" "$db_health_ran" "$app_restart_ran" "$app_health_ran" "$db_health_ok" "$app_health_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Remote Multi-Host Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `ssh-app.sh status` ran: %s\n' "$app_status_ran"
  printf -- '- `ssh-db.sh status` ran: %s\n' "$db_status_ran"
  printf -- '- `ssh-db.sh promote` ran: %s\n' "$db_promote_ran"
  printf -- '- `ssh-db.sh health` ran: %s\n' "$db_health_ran"
  printf -- '- `ssh-app.sh restart` ran: %s\n' "$app_restart_ran"
  printf -- '- `ssh-app.sh health` ran: %s\n' "$app_health_ran"
  printf -- '- DB health now passes: %s\n' "$db_health_ok"
  printf -- '- App health now passes: %s\n' "$app_health_ok"
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
