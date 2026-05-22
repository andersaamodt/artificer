#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="system-boundary-pack-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for system boundary pack probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: system-boundary-pack-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded system-boundary pack probe against a demo workspace and checks
whether Artificer can inspect two local boundaries, approve one shared cutover
state, cut the core boundary over first, cut the edge boundary over second,
verify the pack, and keep rollback intact.
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

create_system_boundary_pack_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/core/live" "$workspace_dir/core/staging" "$workspace_dir/edge/live" "$workspace_dir/edge/staging" "$workspace_dir/state" "$workspace_dir/audit"
  cat > "$workspace_dir/core/live/release.txt" <<'EOF_TXT'
2026.03.15-core
EOF_TXT
  cat > "$workspace_dir/core/staging/release.txt.next" <<'EOF_TXT'
2026.03.22-core
EOF_TXT
  cat > "$workspace_dir/edge/live/channel.txt" <<'EOF_TXT'
legacy-edge
EOF_TXT
  cat > "$workspace_dir/edge/staging/channel.txt.next" <<'EOF_TXT'
2026.03.22-edge
EOF_TXT
  cp "$workspace_dir/core/live/release.txt" "$workspace_dir/core/live/release.txt.bak"
  cp "$workspace_dir/core/staging/release.txt.next" "$workspace_dir/core/staging/release.txt.next.bak"
  cp "$workspace_dir/edge/live/channel.txt" "$workspace_dir/edge/live/channel.txt.bak"
  cp "$workspace_dir/edge/staging/channel.txt.next" "$workspace_dir/edge/staging/channel.txt.next.bak"
  cat > "$workspace_dir/state/boundary-pack.env" <<'EOF_ENV'
CORE_CURRENT=2026.03.15-core
CORE_TARGET=2026.03.22-core
EDGE_CURRENT=legacy-edge
EDGE_TARGET=2026.03.22-edge
CUTOVER_APPROVED=0
READ_ONLY=0
CORE_READY=0
EDGE_READY=0
PACK_STATE=pending
EOF_ENV
  cp "$workspace_dir/state/boundary-pack.env" "$workspace_dir/state/boundary-pack.env.bak"
  printf '%s\n' 'pending' > "$workspace_dir/state/core.cutover.status"
  printf '%s\n' 'pending' > "$workspace_dir/state/edge.cutover.status"
  cat > "$workspace_dir/bin/status-core.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/boundary-pack.env"
live_release=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$CORE_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$live_release" = "$CORE_CURRENT" ]; then
  printf '%s\n' "core_boundary=ready current=$live_release target=$CORE_TARGET"
else
  printf '%s\n' "core_boundary=stale current=$live_release target=$CORE_TARGET"
  printf '%s\n' "expected_fix=approve shared cutover, set core ready, keep the pack read-only, and then cut core over first"
fi
EOF_SH
  cat > "$workspace_dir/bin/status-edge.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/boundary-pack.env"
live_channel=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$EDGE_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$live_channel" = "$EDGE_CURRENT" ]; then
  printf '%s\n' "edge_boundary=ready current=$live_channel target=$EDGE_TARGET"
else
  printf '%s\n' "edge_boundary=stale current=$live_channel target=$EDGE_TARGET"
  printf '%s\n' "expected_fix=approve shared cutover, set edge ready, keep the pack read-only, and then cut edge over second"
fi
EOF_SH
  cat > "$workspace_dir/bin/cutover-core.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/boundary-pack.env"
live_release=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$CORE_READY" != "1" ] || [ "$PACK_STATE" != "ready" ] || [ "$live_release" != "$CORE_CURRENT" ]; then
  printf '%s\n' "core_cutover=blocked"
  exit 1
fi
cp "$ROOT_DIR/core/staging/release.txt.next" "$ROOT_DIR/core/live/release.txt"
printf '%s\n' 'applied' > "$ROOT_DIR/state/core.cutover.status"
printf '%s\n' "core_cutover=ok release=$(cat "$ROOT_DIR/core/live/release.txt")" > "$ROOT_DIR/audit/core-cutover.log"
printf '%s\n' "core_cutover=ok"
EOF_SH
  cat > "$workspace_dir/bin/cutover-edge.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/boundary-pack.env"
core_state=$(cat "$ROOT_DIR/state/core.cutover.status" 2>/dev/null || printf '%s' 'missing')
live_channel=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$EDGE_READY" != "1" ] || [ "$PACK_STATE" != "ready" ] || [ "$core_state" != "applied" ] || [ "$live_channel" != "$EDGE_CURRENT" ]; then
  printf '%s\n' "edge_cutover=blocked"
  exit 1
fi
cp "$ROOT_DIR/edge/staging/channel.txt.next" "$ROOT_DIR/edge/live/channel.txt"
printf '%s\n' 'applied' > "$ROOT_DIR/state/edge.cutover.status"
printf '%s\n' "edge_cutover=ok channel=$(cat "$ROOT_DIR/edge/live/channel.txt")" > "$ROOT_DIR/audit/edge-cutover.log"
printf '%s\n' "edge_cutover=ok"
EOF_SH
  cat > "$workspace_dir/bin/verify-pack.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/boundary-pack.env"
core_live=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
edge_live=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
core_state=$(cat "$ROOT_DIR/state/core.cutover.status" 2>/dev/null || printf '%s' 'missing')
edge_state=$(cat "$ROOT_DIR/state/edge.cutover.status" 2>/dev/null || printf '%s' 'missing')
core_log=$(cat "$ROOT_DIR/audit/core-cutover.log" 2>/dev/null || printf '%s' 'missing')
edge_log=$(cat "$ROOT_DIR/audit/edge-cutover.log" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$CORE_READY" = "1" ] && [ "$EDGE_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] \
  && [ "$core_live" = "$CORE_TARGET" ] && [ "$edge_live" = "$EDGE_TARGET" ] \
  && [ "$core_state" = "applied" ] && [ "$edge_state" = "applied" ] \
  && printf '%s' "$core_log" | grep -q 'core_cutover=ok' \
  && printf '%s' "$edge_log" | grep -q 'edge_cutover=ok'; then
  printf '%s\n' "verify_pack=ok core=$core_live edge=$edge_live"
  exit 0
fi
printf '%s\n' "verify_pack=failed core=$core_live edge=$edge_live"
exit 1
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/state/boundary-pack.env.bak" "$ROOT_DIR/state/boundary-pack.env"
cp "$ROOT_DIR/core/live/release.txt.bak" "$ROOT_DIR/core/live/release.txt"
cp "$ROOT_DIR/core/staging/release.txt.next.bak" "$ROOT_DIR/core/staging/release.txt.next"
cp "$ROOT_DIR/edge/live/channel.txt.bak" "$ROOT_DIR/edge/live/channel.txt"
cp "$ROOT_DIR/edge/staging/channel.txt.next.bak" "$ROOT_DIR/edge/staging/channel.txt.next"
rm -f "$ROOT_DIR/audit/core-cutover.log" "$ROOT_DIR/audit/edge-cutover.log"
printf '%s\n' 'pending' > "$ROOT_DIR/state/core.cutover.status"
printf '%s\n' 'pending' > "$ROOT_DIR/state/edge.cutover.status"
printf '%s\n' "rollback_status=ready"
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# System Boundary Pack Demo

Use the helpers in `bin/` to inspect, cut over, verify, and roll back one bounded
shared local boundary pack. The pack is healthy only when the core boundary cuts
over first, the edge boundary cuts over second, verification passes, and rollback
stays intact.
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
[ -n "$model" ] || { echo "No installed models available; system boundary pack probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_system_boundary_pack_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded local system boundary pack in this workspace. Use `./bin/status-core.sh`, `./bin/status-edge.sh`, `./bin/cutover-core.sh`, `./bin/cutover-edge.sh`, `./bin/verify-pack.sh`, and `./bin/rollback.sh`. Make the smallest safe shared cutover-state fix so the core boundary cuts over first, the edge boundary cuts over second, rerun bounded verification, keep rollback intact, and stop there. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
if grep -q '^CUTOVER_APPROVED=1$' "$tmp_ws/state/boundary-pack.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/state/boundary-pack.env" \
  && grep -q '^CORE_READY=1$' "$tmp_ws/state/boundary-pack.env" \
  && grep -q '^EDGE_READY=1$' "$tmp_ws/state/boundary-pack.env" \
  && grep -q '^PACK_STATE=ready$' "$tmp_ws/state/boundary-pack.env"; then
  config_fixed=1
fi

core_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/status-core.sh") | if . then 1 else 0 end')
edge_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/status-edge.sh") | if . then 1 else 0 end')
core_cutover_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/cutover-core.sh") | if . then 1 else 0 end')
edge_cutover_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/cutover-edge.sh") | if . then 1 else 0 end')
verify_pack_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/verify-pack.sh") | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' '1' || printf '%s' '0')
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' '1' || printf '%s' '0')
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' '1' || printf '%s' '0')
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' '1' || printf '%s' '0')
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' '1' || printf '%s' '0')
core_live_ok=$(grep -q '^2026.03.22-core$' "$tmp_ws/core/live/release.txt" && printf '%s' '1' || printf '%s' '0')
edge_live_ok=$(grep -q '^2026.03.22-edge$' "$tmp_ws/edge/live/channel.txt" && printf '%s' '1' || printf '%s' '0')
verify_pack_ok=$(sh "$tmp_ws/bin/verify-pack.sh" >/dev/null 2>&1 && printf '%s' '1' || printf '%s' '0')
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] \
  && cmp -s "$baseline_dir/state/boundary-pack.env.bak" "$tmp_ws/state/boundary-pack.env.bak" \
  && cmp -s "$baseline_dir/core/live/release.txt.bak" "$tmp_ws/core/live/release.txt.bak" \
  && cmp -s "$baseline_dir/edge/live/channel.txt.bak" "$tmp_ws/edge/live/channel.txt.bak" \
  && printf '%s' '1' || printf '%s' '0')
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status='fail'
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] \
  && [ "$core_status_ran" -eq 1 ] && [ "$edge_status_ran" -eq 1 ] \
  && [ "$core_cutover_ran" -eq 1 ] && [ "$edge_cutover_ran" -eq 1 ] && [ "$verify_pack_ran" -eq 1 ] \
  && [ "$core_live_ok" -eq 1 ] && [ "$edge_live_ok" -eq 1 ] && [ "$verify_pack_ok" -eq 1 ] \
  && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] \
  && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"core_status_ran":%s,"edge_status_ran":%s,"core_cutover_ran":%s,"edge_cutover_ran":%s,"verify_pack_ran":%s,"core_live_ok":%s,"edge_live_ok":%s,"verify_pack_ok":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$core_status_ran" "$edge_status_ran" "$core_cutover_ran" "$edge_cutover_ran" "$verify_pack_ran" "$core_live_ok" "$edge_live_ok" "$verify_pack_ok" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# System Boundary Pack Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `status-core.sh` ran: %s\n' "$core_status_ran"
  printf -- '- `status-edge.sh` ran: %s\n' "$edge_status_ran"
  printf -- '- `cutover-core.sh` ran: %s\n' "$core_cutover_ran"
  printf -- '- `cutover-edge.sh` ran: %s\n' "$edge_cutover_ran"
  printf -- '- `verify-pack.sh` ran: %s\n' "$verify_pack_ran"
  printf -- '- Core boundary now on target: %s\n' "$core_live_ok"
  printf -- '- Edge boundary now on target: %s\n' "$edge_live_ok"
  printf -- '- Verify pack now passes: %s\n' "$verify_pack_ok"
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
[ "$status" = 'pass' ]
