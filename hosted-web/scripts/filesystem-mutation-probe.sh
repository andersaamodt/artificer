#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="filesystem-mutation-pack-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for filesystem mutation probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: filesystem-mutation-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded filesystem-mutation probe against a demo workspace and checks
whether Artificer can inventory, apply a bounded archive/promote/link mutation,
verify the result, and keep rollback intact.
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

create_filesystem_mutation_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/layout/live" "$workspace_dir/layout/staging" "$workspace_dir/layout/archive" "$workspace_dir/state"
  cat > "$workspace_dir/layout/live/config.yml" <<'EOF_CFG'
version: legacy
mode: stale
owner: demo
EOF_CFG
  cat > "$workspace_dir/layout/staging/config.yml.next" <<'EOF_CFG'
version: 2026-03-22
mode: healthy
owner: demo
EOF_CFG
  cp "$workspace_dir/layout/live/config.yml" "$workspace_dir/layout/live/config.yml.bak"
  cp "$workspace_dir/layout/staging/config.yml.next" "$workspace_dir/layout/staging/config.yml.next.bak"
  cat > "$workspace_dir/state/layout.env" <<'EOF_ENV'
LIVE_DIR=layout/live
STAGING_FILE=layout/staging/config.yml.next
ARCHIVE_DIR=layout/archive
ACTIVE_LINK=layout/current-config.yml
TARGET_NAME=config.yml
APPLY_READY=0
LINK_READY=0
READ_ONLY=0
EOF_ENV
  cp "$workspace_dir/state/layout.env" "$workspace_dir/state/layout.env.bak"
  cat > "$workspace_dir/bin/inventory.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/layout.env"
live_file="$ROOT_DIR/$LIVE_DIR/$TARGET_NAME"
staging_file="$ROOT_DIR/$STAGING_FILE"
link_file="$ROOT_DIR/$ACTIVE_LINK"
if [ "$APPLY_READY" = "1" ] && [ "$LINK_READY" = "1" ] && [ "$READ_ONLY" = "1" ] \
  && [ -f "$staging_file" ] && [ -f "$live_file" ]; then
  printf '%s\n' "layout_state=ready live=$live_file staging=$staging_file link=$link_file"
else
  printf '%s\n' "layout_state=stale live=$live_file staging=$staging_file link=$link_file"
  printf '%s\n' "expected_fix=APPLY_READY=1 LINK_READY=1 READ_ONLY=1 then archive current live file, promote staging file, and refresh the current link"
fi
EOF_BIN
  cat > "$workspace_dir/bin/apply.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/layout.env"
live_dir="$ROOT_DIR/$LIVE_DIR"
staging_file="$ROOT_DIR/$STAGING_FILE"
archive_dir="$ROOT_DIR/$ARCHIVE_DIR"
link_file="$ROOT_DIR/$ACTIVE_LINK"
live_file="$live_dir/$TARGET_NAME"
archive_file="$archive_dir/$TARGET_NAME.previous"
if [ "$APPLY_READY" != "1" ] || [ "$LINK_READY" != "1" ] || [ "$READ_ONLY" != "1" ] || [ ! -f "$staging_file" ] || [ ! -f "$live_file" ]; then
  printf '%s\n' "apply=failed target=$TARGET_NAME"
  exit 1
fi
mkdir -p "$archive_dir"
mv "$live_file" "$archive_file"
mv "$staging_file" "$live_file"
ln -sfn "live/$TARGET_NAME" "$link_file"
printf '%s\n' "apply=ok archived=$archive_file promoted=$live_file link=$link_file"
EOF_BIN
  cat > "$workspace_dir/bin/verify.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/layout.env"
live_file="$ROOT_DIR/$LIVE_DIR/$TARGET_NAME"
staging_file="$ROOT_DIR/$STAGING_FILE"
archive_file="$ROOT_DIR/$ARCHIVE_DIR/$TARGET_NAME.previous"
link_file="$ROOT_DIR/$ACTIVE_LINK"
link_target=$(readlink "$link_file" 2>/dev/null || printf '%s' '')
if [ "$APPLY_READY" = "1" ] && [ "$LINK_READY" = "1" ] && [ "$READ_ONLY" = "1" ] \
  && [ -f "$live_file" ] && [ ! -f "$staging_file" ] && [ -f "$archive_file" ] \
  && [ "$link_target" = "live/$TARGET_NAME" ] && grep -q '^mode: healthy$' "$live_file"; then
  printf '%s\n' "verify=ok live=$live_file archived=$archive_file link=$link_target"
  exit 0
fi
printf '%s\n' "verify=failed live=$live_file archived=$archive_file link=$link_target"
exit 1
EOF_BIN
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_BIN'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
rm -f "$ROOT_DIR/layout/current-config.yml"
cp "$ROOT_DIR/state/layout.env.bak" "$ROOT_DIR/state/layout.env"
cp "$ROOT_DIR/layout/live/config.yml.bak" "$ROOT_DIR/layout/live/config.yml"
cp "$ROOT_DIR/layout/staging/config.yml.next.bak" "$ROOT_DIR/layout/staging/config.yml.next"
rm -f "$ROOT_DIR/layout/archive/config.yml.previous"
printf '%s\n' "rollback_status=ready"
EOF_BIN
  chmod +x "$workspace_dir/bin/"*.sh
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Filesystem Mutation Demo

Use the scripts in `bin/` to inventory, apply, verify, and roll back the bounded layout mutation.
The layout is healthy only when the staged config is promoted into the live path, the previous live file is archived,
and the current link points at the promoted live config in read-only mode.
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
[ -n "$model" ] || { echo "No installed models available; filesystem mutation probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_filesystem_mutation_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Handle the bounded filesystem mutation pack in this workspace. Use `./bin/inventory.sh`, `./bin/apply.sh`, `./bin/verify.sh`, and `./bin/rollback.sh`. Make the smallest safe layout-state fix so the staged config is promoted into the live path, the previous live file is archived, the current link points at the promoted file, rerun verification, keep rollback intact, and do not widen beyond this one layout pack. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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
if grep -q '^APPLY_READY=1$' "$tmp_ws/state/layout.env" \
  && grep -q '^LINK_READY=1$' "$tmp_ws/state/layout.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/state/layout.env"; then
  config_fixed=1
fi

inventory_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/inventory.sh")) | if . then 1 else 0 end')
apply_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/apply.sh")) | if . then 1 else 0 end')
verify_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/verify.sh")) | if . then 1 else 0 end')
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
verify_ok=$(sh "$tmp_ws/bin/verify.sh" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
live_promoted=$([ -f "$tmp_ws/layout/live/config.yml" ] && grep -q '^mode: healthy$' "$tmp_ws/layout/live/config.yml" && [ ! -f "$tmp_ws/layout/staging/config.yml.next" ] && printf '%s' "1" || printf '%s' "0")
archive_written=$([ -f "$tmp_ws/layout/archive/config.yml.previous" ] && grep -q '^mode: stale$' "$tmp_ws/layout/archive/config.yml.previous" && printf '%s' "1" || printf '%s' "0")
link_updated=$([ "$(readlink "$tmp_ws/layout/current-config.yml" 2>/dev/null || printf '%s' '')" = "live/config.yml" ] && printf '%s' "1" || printf '%s' "0")
rollback_intact=$([ -x "$tmp_ws/bin/rollback.sh" ] \
  && cmp -s "$baseline_dir/state/layout.env.bak" "$tmp_ws/state/layout.env.bak" \
  && cmp -s "$baseline_dir/layout/live/config.yml.bak" "$tmp_ws/layout/live/config.yml.bak" \
  && cmp -s "$baseline_dir/layout/staging/config.yml.next.bak" "$tmp_ws/layout/staging/config.yml.next.bak" \
  && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$config_fixed" -eq 1 ] && [ "$inventory_ran" -eq 1 ] && [ "$apply_ran" -eq 1 ] && [ "$verify_ran" -eq 1 ] && [ "$verify_ok" -eq 1 ] && [ "$live_promoted" -eq 1 ] && [ "$archive_written" -eq 1 ] && [ "$link_updated" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$rollback_intact" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"config_fixed":%s,"inventory_ran":%s,"apply_ran":%s,"verify_ran":%s,"verify_ok":%s,"live_promoted":%s,"archive_written":%s,"link_updated":%s,"rollback_referenced":%s,"rollback_intact":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$config_fixed" "$inventory_ran" "$apply_ran" "$verify_ran" "$verify_ok" "$live_promoted" "$archive_written" "$link_updated" "$rollback_ref" "$rollback_intact" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Filesystem Mutation Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Config fixed: %s\n' "$config_fixed"
  printf -- '- `inventory.sh` ran: %s\n' "$inventory_ran"
  printf -- '- `apply.sh` ran: %s\n' "$apply_ran"
  printf -- '- `verify.sh` ran: %s\n' "$verify_ran"
  printf -- '- Verify now passes: %s\n' "$verify_ok"
  printf -- '- Live config promoted: %s\n' "$live_promoted"
  printf -- '- Previous live file archived: %s\n' "$archive_written"
  printf -- '- Current link updated: %s\n' "$link_updated"
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
