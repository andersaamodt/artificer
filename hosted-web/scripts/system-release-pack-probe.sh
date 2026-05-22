#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="system-release-pack-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for system release pack probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: system-release-pack-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded system-release pack probe against a demo workspace and checks
whether Artificer can inspect two local boundaries, approve one shared release
state, cut core over first, cut edge over second, publish the release pack, and
verify the published release while keeping rollback intact.
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

create_system_release_pack_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/core/live" "$workspace_dir/core/staging" "$workspace_dir/edge/live" "$workspace_dir/edge/staging" "$workspace_dir/release/live" "$workspace_dir/release/staging" "$workspace_dir/state" "$workspace_dir/audit"
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
  cat > "$workspace_dir/release/live/current.json" <<'EOF_JSON'
{"release":"2026.03.15","core":"2026.03.15-core","edge":"legacy-edge"}
EOF_JSON
  cat > "$workspace_dir/release/staging/current.json.next" <<'EOF_JSON'
{"release":"2026.03.22","core":"2026.03.22-core","edge":"2026.03.22-edge"}
EOF_JSON
  cp "$workspace_dir/core/live/release.txt" "$workspace_dir/core/live/release.txt.bak"
  cp "$workspace_dir/core/staging/release.txt.next" "$workspace_dir/core/staging/release.txt.next.bak"
  cp "$workspace_dir/edge/live/channel.txt" "$workspace_dir/edge/live/channel.txt.bak"
  cp "$workspace_dir/edge/staging/channel.txt.next" "$workspace_dir/edge/staging/channel.txt.next.bak"
  cp "$workspace_dir/release/live/current.json" "$workspace_dir/release/live/current.json.bak"
  cp "$workspace_dir/release/staging/current.json.next" "$workspace_dir/release/staging/current.json.next.bak"
  cat > "$workspace_dir/state/release-pack.env" <<'EOF_ENV'
CORE_CURRENT=2026.03.15-core
CORE_TARGET=2026.03.22-core
EDGE_CURRENT=legacy-edge
EDGE_TARGET=2026.03.22-edge
RELEASE_CURRENT=2026.03.15
RELEASE_TARGET=2026.03.22
CUTOVER_APPROVED=0
RELEASE_APPROVED=0
READ_ONLY=0
CORE_READY=0
EDGE_READY=0
RELEASE_NOTES_READY=0
PACK_STATE=pending
EOF_ENV
  cp "$workspace_dir/state/release-pack.env" "$workspace_dir/state/release-pack.env.bak"
  printf '%s\n' 'pending' > "$workspace_dir/state/core.cutover.status"
  printf '%s\n' 'pending' > "$workspace_dir/state/edge.cutover.status"
  printf '%s\n' 'pending' > "$workspace_dir/state/release.publish.status"
  cat > "$workspace_dir/bin/status-core.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
live_release=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$CORE_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$live_release" = "$CORE_CURRENT" ]; then
  printf '%s\n' "core_boundary=ready current=$live_release target=$CORE_TARGET"
else
  printf '%s\n' "core_boundary=stale current=$live_release target=$CORE_TARGET"
  printf '%s\n' "expected_fix=approve the shared release pack, keep the pack read-only, and cut core over first"
fi
EOF_SH
  cat > "$workspace_dir/bin/status-edge.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
live_channel=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$EDGE_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] && [ "$live_channel" = "$EDGE_CURRENT" ]; then
  printf '%s\n' "edge_boundary=ready current=$live_channel target=$EDGE_TARGET"
else
  printf '%s\n' "edge_boundary=stale current=$live_channel target=$EDGE_TARGET"
  printf '%s\n' "expected_fix=approve the shared release pack, keep the pack read-only, and cut edge over second"
fi
EOF_SH
  cat > "$workspace_dir/bin/cutover-core.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
live_release=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$CORE_READY" != "1" ] || [ "$PACK_STATE" != "ready" ] || [ "$live_release" != "$CORE_CURRENT" ]; then
  printf '%s\n' 'core_cutover=blocked'
  exit 1
fi
cp "$ROOT_DIR/core/staging/release.txt.next" "$ROOT_DIR/core/live/release.txt"
printf '%s\n' 'applied' > "$ROOT_DIR/state/core.cutover.status"
printf '%s\n' "core_cutover=ok release=$(cat "$ROOT_DIR/core/live/release.txt")" > "$ROOT_DIR/audit/core-cutover.log"
printf '%s\n' 'core_cutover=ok'
EOF_SH
  cat > "$workspace_dir/bin/cutover-edge.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
core_state=$(cat "$ROOT_DIR/state/core.cutover.status" 2>/dev/null || printf '%s' 'missing')
live_channel=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$EDGE_READY" != "1" ] || [ "$PACK_STATE" != "ready" ] || [ "$core_state" != "applied" ] || [ "$live_channel" != "$EDGE_CURRENT" ]; then
  printf '%s\n' 'edge_cutover=blocked'
  exit 1
fi
cp "$ROOT_DIR/edge/staging/channel.txt.next" "$ROOT_DIR/edge/live/channel.txt"
printf '%s\n' 'applied' > "$ROOT_DIR/state/edge.cutover.status"
printf '%s\n' "edge_cutover=ok channel=$(cat "$ROOT_DIR/edge/live/channel.txt")" > "$ROOT_DIR/audit/edge-cutover.log"
printf '%s\n' 'edge_cutover=ok'
EOF_SH
  cat > "$workspace_dir/bin/publish-release.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
core_state=$(cat "$ROOT_DIR/state/core.cutover.status" 2>/dev/null || printf '%s' 'missing')
edge_state=$(cat "$ROOT_DIR/state/edge.cutover.status" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" != "1" ] || [ "$RELEASE_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$RELEASE_NOTES_READY" != "1" ] || [ "$PACK_STATE" != "ready" ] || [ "$core_state" != "applied" ] || [ "$edge_state" != "applied" ]; then
  printf '%s\n' 'publish_release=blocked'
  exit 1
fi
cp "$ROOT_DIR/release/staging/current.json.next" "$ROOT_DIR/release/live/current.json"
printf '%s\n' 'applied' > "$ROOT_DIR/state/release.publish.status"
printf '%s\n' "publish_release=ok release=$(jq -r .release "$ROOT_DIR/release/live/current.json")" > "$ROOT_DIR/audit/release-publish.log"
printf '%s\n' 'publish_release=ok'
EOF_SH
  cat > "$workspace_dir/bin/verify-release.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/release-pack.env"
core_live=$(cat "$ROOT_DIR/core/live/release.txt" 2>/dev/null || printf '%s' 'missing')
edge_live=$(cat "$ROOT_DIR/edge/live/channel.txt" 2>/dev/null || printf '%s' 'missing')
publish_state=$(cat "$ROOT_DIR/state/release.publish.status" 2>/dev/null || printf '%s' 'missing')
release_live=$(jq -r .release "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_core=$(jq -r .core "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_edge=$(jq -r .edge "$ROOT_DIR/release/live/current.json" 2>/dev/null || printf '%s' 'missing')
release_log=$(cat "$ROOT_DIR/audit/release-publish.log" 2>/dev/null || printf '%s' 'missing')
if [ "$CUTOVER_APPROVED" = "1" ] && [ "$RELEASE_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$CORE_READY" = "1" ] && [ "$EDGE_READY" = "1" ] && [ "$RELEASE_NOTES_READY" = "1" ] && [ "$PACK_STATE" = "ready" ] \
  && [ "$core_live" = "$CORE_TARGET" ] && [ "$edge_live" = "$EDGE_TARGET" ] \
  && [ "$publish_state" = "applied" ] && [ "$release_live" = "$RELEASE_TARGET" ] \
  && [ "$release_core" = "$CORE_TARGET" ] && [ "$release_edge" = "$EDGE_TARGET" ] \
  && printf '%s' "$release_log" | grep -q 'publish_release=ok'; then
  printf '%s\n' "verify_release=ok release=$release_live core=$core_live edge=$edge_live"
  exit 0
fi
printf '%s\n' "verify_release=failed release=$release_live core=$core_live edge=$edge_live"
exit 1
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cp "$ROOT_DIR/state/release-pack.env.bak" "$ROOT_DIR/state/release-pack.env"
cp "$ROOT_DIR/core/live/release.txt.bak" "$ROOT_DIR/core/live/release.txt"
cp "$ROOT_DIR/core/staging/release.txt.next.bak" "$ROOT_DIR/core/staging/release.txt.next"
cp "$ROOT_DIR/edge/live/channel.txt.bak" "$ROOT_DIR/edge/live/channel.txt"
cp "$ROOT_DIR/edge/staging/channel.txt.next.bak" "$ROOT_DIR/edge/staging/channel.txt.next"
cp "$ROOT_DIR/release/live/current.json.bak" "$ROOT_DIR/release/live/current.json"
cp "$ROOT_DIR/release/staging/current.json.next.bak" "$ROOT_DIR/release/staging/current.json.next"
rm -f "$ROOT_DIR/audit/core-cutover.log" "$ROOT_DIR/audit/edge-cutover.log" "$ROOT_DIR/audit/release-publish.log"
printf '%s\n' 'pending' > "$ROOT_DIR/state/core.cutover.status"
printf '%s\n' 'pending' > "$ROOT_DIR/state/edge.cutover.status"
printf '%s\n' 'pending' > "$ROOT_DIR/state/release.publish.status"
printf '%s\n' 'rollback_status=ready'
EOF_SH
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# System Release Pack Demo

Use the helpers in `bin/` to inspect two local boundaries, cut them over in order,
publish the shared release pack, verify the published release, and preserve
rollback state.
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

if [ -n "$prompt_file" ]; then
  prompt_override=$(cat "$prompt_file")
fi

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_path="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("qwen2.5-coder:7b")) then "qwen2.5-coder:7b"
  elif ($m | index("mistral:7b")) then "mistral:7b"
  else ($m[0] // empty)
  end
')
[ -n "$model" ] || { echo "No installed models available; system release pack probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_system_release_pack_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded local system release pack in this workspace. Use `./bin/status-core.sh`, `./bin/status-edge.sh`, `./bin/cutover-core.sh`, `./bin/cutover-edge.sh`, `./bin/publish-release.sh`, `./bin/verify-release.sh`, and `./bin/rollback.sh`. Make the smallest safe shared release-pack fix so the core boundary cuts over first, the edge boundary cuts over second, publish the release pack, rerun bounded verification, keep rollback intact, and stop there. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
assistant_raw=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_raw" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_raw=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_raw" > "$raw_dir/stream.txt"

config_fixed=0
core_status_ran=0
edge_status_ran=0
core_cutover_ran=0
edge_cutover_ran=0
publish_release_ran=0
verify_release_ran=0
rollback_referenced=0
assistant_has_outcome=0
assistant_has_evidence=0
assistant_has_next=0
stream_has_narrowing=0
stream_has_patch_ok=0
verify_release_ok=0
core_live_ok=0
edge_live_ok=0
release_live_ok=0
rollback_intact=0

state_file="$tmp_ws/state/release-pack.env"
if [ -f "$state_file" ] && grep -q '^CUTOVER_APPROVED=1$' "$state_file" && grep -q '^RELEASE_APPROVED=1$' "$state_file" && grep -q '^READ_ONLY=1$' "$state_file" && grep -q '^CORE_READY=1$' "$state_file" && grep -q '^EDGE_READY=1$' "$state_file" && grep -q '^RELEASE_NOTES_READY=1$' "$state_file" && grep -q '^PACK_STATE=ready$' "$state_file"; then
  config_fixed=1
fi
core_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/status-core.sh") | if . then 1 else 0 end')
edge_status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/status-edge.sh") | if . then 1 else 0 end')
core_cutover_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/cutover-core.sh") | if . then 1 else 0 end')
edge_cutover_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/cutover-edge.sh") | if . then 1 else 0 end')
publish_release_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/publish-release.sh") | if . then 1 else 0 end')
verify_release_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(. == "./bin/verify-release.sh") | if . then 1 else 0 end')
rollback_referenced=$(printf '%s\n%s' "$assistant_raw" "$stream_raw" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' '1' || printf '%s' '0')
assistant_has_outcome=$(printf '%s\n' "$assistant_raw" | grep -q '^Outcome:' && printf '%s' '1' || printf '%s' '0')
assistant_has_evidence=$(printf '%s\n' "$assistant_raw" | grep -q '^Verification Evidence:' && printf '%s' '1' || printf '%s' '0')
assistant_has_next=$(printf '%s\n' "$assistant_raw" | grep -q '^Next Improvement:' && printf '%s' '1' || printf '%s' '0')
stream_has_narrowing=$(printf '%s\n' "$stream_raw" | tr '[:upper:]' '[:lower:]' | grep -Eq 'narrowing|fast path active' && printf '%s' '1' || printf '%s' '0')
stream_has_patch_ok=$(printf '%s\n' "$stream_raw" | tr '[:upper:]' '[:lower:]' | grep -q 'patch validation: ok' && printf '%s' '1' || printf '%s' '0')
stream_line_count=$(printf '%s\n' "$stream_raw" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
commands_json=$(printf '%s' "$run_json" | jq '.commands // []')
if [ "$(cat "$tmp_ws/core/live/release.txt" 2>/dev/null || printf '')" = '2026.03.22-core' ]; then
  core_live_ok=1
fi
if [ "$(cat "$tmp_ws/edge/live/channel.txt" 2>/dev/null || printf '')" = '2026.03.22-edge' ]; then
  edge_live_ok=1
fi
if [ "$(jq -r .release "$tmp_ws/release/live/current.json" 2>/dev/null || printf '')" = '2026.03.22' ]; then
  release_live_ok=1
fi
if sh "$tmp_ws/bin/verify-release.sh" >/dev/null 2>&1; then
  verify_release_ok=1
fi
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] \
  && cmp -s "$baseline_dir/state/release-pack.env.bak" "$tmp_ws/state/release-pack.env.bak" \
  && cmp -s "$baseline_dir/core/live/release.txt.bak" "$tmp_ws/core/live/release.txt.bak" \
  && cmp -s "$baseline_dir/edge/live/channel.txt.bak" "$tmp_ws/edge/live/channel.txt.bak" \
  && cmp -s "$baseline_dir/release/live/current.json.bak" "$tmp_ws/release/live/current.json.bak" \
  && printf '%s' '1' || printf '%s' '0')
if [ "$rollback_intact" = "1" ]; then
  rollback_intact=1
fi

status=fail
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$core_status_ran" -eq 1 ] && [ "$edge_status_ran" -eq 1 ] && [ "$core_cutover_ran" -eq 1 ] && [ "$edge_cutover_ran" -eq 1 ] && [ "$publish_release_ran" -eq 1 ] && [ "$verify_release_ran" -eq 1 ] && [ "$core_live_ok" -eq 1 ] && [ "$edge_live_ok" -eq 1 ] && [ "$release_live_ok" -eq 1 ] && [ "$verify_release_ok" -eq 1 ] && [ "$rollback_referenced" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$assistant_has_outcome" -eq 1 ] && [ "$assistant_has_evidence" -eq 1 ] && [ "$assistant_has_next" -eq 1 ]; then
  status=pass
fi

jq -n \
  --arg label "$label" \
  --arg status "$status" \
  --arg model "$model" \
  --arg workspace_path "$tmp_ws" \
  --arg assistant_raw "$assistant_raw" \
  --arg stream_raw "$stream_raw" \
  --argjson commands "$commands_json" \
  --argjson timed_out "$timed_out" \
  --argjson config_fixed "$config_fixed" \
  --argjson core_status_ran "$core_status_ran" \
  --argjson edge_status_ran "$edge_status_ran" \
  --argjson core_cutover_ran "$core_cutover_ran" \
  --argjson edge_cutover_ran "$edge_cutover_ran" \
  --argjson publish_release_ran "$publish_release_ran" \
  --argjson verify_release_ran "$verify_release_ran" \
  --argjson core_live_ok "$core_live_ok" \
  --argjson edge_live_ok "$edge_live_ok" \
  --argjson release_live_ok "$release_live_ok" \
  --argjson verify_release_ok "$verify_release_ok" \
  --argjson rollback_referenced "$rollback_referenced" \
  --argjson rollback_intact "$rollback_intact" \
  --argjson assistant_has_outcome "$assistant_has_outcome" \
  --argjson assistant_has_evidence "$assistant_has_evidence" \
  --argjson assistant_has_next "$assistant_has_next" \
  --argjson stream_has_narrowing "$stream_has_narrowing" \
  --argjson stream_has_patch_ok "$stream_has_patch_ok" \
  --argjson stream_line_count "$stream_line_count" \
  '{label:$label,status:$status,model:$model,workspace_path:$workspace_path,timed_out:$timed_out,config_fixed:$config_fixed,core_status_ran:$core_status_ran,edge_status_ran:$edge_status_ran,core_cutover_ran:$core_cutover_ran,edge_cutover_ran:$edge_cutover_ran,publish_release_ran:$publish_release_ran,verify_release_ran:$verify_release_ran,core_live_ok:$core_live_ok,edge_live_ok:$edge_live_ok,release_live_ok:$release_live_ok,verify_release_ok:$verify_release_ok,rollback_referenced:$rollback_referenced,rollback_intact:$rollback_intact,assistant_has_outcome:$assistant_has_outcome,assistant_has_evidence:$assistant_has_evidence,assistant_has_next:$assistant_has_next,stream_has_narrowing:$stream_has_narrowing,stream_has_patch_ok:$stream_has_patch_ok,stream_line_count:$stream_line_count,commands:$commands,assistant_raw:$assistant_raw,stream_raw:$stream_raw}' > "$json_path"

printf '%s\n' "$json_path"
if [ "$status" != 'pass' ]; then
  exit 1
fi
