#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="partial-system-rollback-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for partial system rollback probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: partial-system-rollback-probe.sh [--label NAME] [--prompt TEXT] [--prompt-file PATH]

Runs a live bounded partial-system-rollback probe against a demo workspace and
checks whether Artificer can inspect a mixed local state, approve the smallest
safe rollback, execute the rollback, and verify that health is restored.
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

create_partial_system_rollback_workspace() {
  workspace_dir=$1
  mkdir -p "$workspace_dir/bin" "$workspace_dir/service" "$workspace_dir/backup" "$workspace_dir/state" "$workspace_dir/audit"
  cat > "$workspace_dir/service/release.txt" <<'EOF_TXT'
2026.03.22-bad
EOF_TXT
  cat > "$workspace_dir/service/package.txt" <<'EOF_TXT'
2.4.0-bad
EOF_TXT
  cat > "$workspace_dir/service/worker.mode" <<'EOF_TXT'
degraded
EOF_TXT
  cat > "$workspace_dir/backup/release.txt" <<'EOF_TXT'
2026.03.15
EOF_TXT
  cat > "$workspace_dir/backup/package.txt" <<'EOF_TXT'
2.3.1
EOF_TXT
  cat > "$workspace_dir/backup/worker.mode" <<'EOF_TXT'
healthy
EOF_TXT
  cat > "$workspace_dir/state/system.env" <<'EOF_ENV'
CURRENT_RELEASE=2026.03.22-bad
STABLE_RELEASE=2026.03.15
CURRENT_PACKAGE=2.4.0-bad
STABLE_PACKAGE=2.3.1
CURRENT_WORKER=degraded
STABLE_WORKER=healthy
ROLLBACK_APPROVED=0
READ_ONLY=0
PARTIAL_STATE=mixed
EOF_ENV
  cp "$workspace_dir/state/system.env" "$workspace_dir/state/system.env.bak"
  printf '%s\n' "not_applied" > "$workspace_dir/state/rollback.status"
  cat > "$workspace_dir/bin/status.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/system.env"
live_release=$(cat "$ROOT_DIR/service/release.txt" 2>/dev/null || printf '%s' 'missing')
live_package=$(cat "$ROOT_DIR/service/package.txt" 2>/dev/null || printf '%s' 'missing')
live_worker=$(cat "$ROOT_DIR/service/worker.mode" 2>/dev/null || printf '%s' 'missing')
if [ "$CURRENT_RELEASE" = "$STABLE_RELEASE" ] && [ "$CURRENT_PACKAGE" = "$STABLE_PACKAGE" ] && [ "$CURRENT_WORKER" = "$STABLE_WORKER" ] \
  && [ "$ROLLBACK_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PARTIAL_STATE" = "rolled_back" ] \
  && [ "$live_release" = "$STABLE_RELEASE" ] && [ "$live_package" = "$STABLE_PACKAGE" ] && [ "$live_worker" = "$STABLE_WORKER" ]; then
  printf '%s\n' "rollback_state=healthy release=$live_release package=$live_package worker=$live_worker"
else
  printf '%s\n' "rollback_state=mixed release=$live_release package=$live_package worker=$live_worker"
  printf '%s\n' "expected_fix=approve rollback, make system read-only, restore stable release/package/worker state, and verify health"
fi
EOF_SH
  cat > "$workspace_dir/bin/rollback.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/system.env"
if [ "$ROLLBACK_APPROVED" != "1" ] || [ "$READ_ONLY" != "1" ] || [ "$PARTIAL_STATE" != "rolled_back" ]; then
  printf '%s\n' "rollback_status=blocked"
  exit 1
fi
cp "$ROOT_DIR/backup/release.txt" "$ROOT_DIR/service/release.txt"
cp "$ROOT_DIR/backup/package.txt" "$ROOT_DIR/service/package.txt"
cp "$ROOT_DIR/backup/worker.mode" "$ROOT_DIR/service/worker.mode"
printf '%s\n' "applied" > "$ROOT_DIR/state/rollback.status"
printf '%s\n' "rollback_applied release=$(cat "$ROOT_DIR/service/release.txt") package=$(cat "$ROOT_DIR/service/package.txt") worker=$(cat "$ROOT_DIR/service/worker.mode")" > "$ROOT_DIR/audit/rollback.log"
printf '%s\n' "rollback_status=ok"
EOF_SH
  cat > "$workspace_dir/bin/health.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/system.env"
live_release=$(cat "$ROOT_DIR/service/release.txt" 2>/dev/null || printf '%s' 'missing')
live_package=$(cat "$ROOT_DIR/service/package.txt" 2>/dev/null || printf '%s' 'missing')
live_worker=$(cat "$ROOT_DIR/service/worker.mode" 2>/dev/null || printf '%s' 'missing')
rollback_state=$(cat "$ROOT_DIR/state/rollback.status" 2>/dev/null || printf '%s' 'missing')
if [ "$CURRENT_RELEASE" = "$STABLE_RELEASE" ] && [ "$CURRENT_PACKAGE" = "$STABLE_PACKAGE" ] && [ "$CURRENT_WORKER" = "$STABLE_WORKER" ] \
  && [ "$ROLLBACK_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PARTIAL_STATE" = "rolled_back" ] \
  && [ "$live_release" = "$STABLE_RELEASE" ] && [ "$live_package" = "$STABLE_PACKAGE" ] && [ "$live_worker" = "$STABLE_WORKER" ] \
  && [ "$rollback_state" = "applied" ]; then
  printf '%s\n' "health=ok"
  exit 0
fi
printf '%s\n' "health=failed"
exit 1
EOF_SH
  cat > "$workspace_dir/bin/verify.sh" <<'EOF_SH'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT_DIR/state/system.env"
rollback_log=$(cat "$ROOT_DIR/audit/rollback.log" 2>/dev/null || printf '%s' 'missing')
if [ "$CURRENT_RELEASE" = "$STABLE_RELEASE" ] && [ "$CURRENT_PACKAGE" = "$STABLE_PACKAGE" ] && [ "$CURRENT_WORKER" = "$STABLE_WORKER" ] \
  && [ "$ROLLBACK_APPROVED" = "1" ] && [ "$READ_ONLY" = "1" ] && [ "$PARTIAL_STATE" = "rolled_back" ] \
  && [ -f "$ROOT_DIR/backup/release.txt" ] && [ -f "$ROOT_DIR/backup/package.txt" ] && [ -f "$ROOT_DIR/backup/worker.mode" ] \
  && printf '%s' "$rollback_log" | grep -q 'rollback_applied'; then
  printf '%s\n' "verify=ok"
  exit 0
fi
printf '%s\n' "verify=failed"
exit 1
EOF_SH
  cat > "$workspace_dir/README.md" <<'EOF_README'
# Partial System Rollback Demo

Use the scripts in `bin/` to inspect the bounded mixed state, apply the smallest
safe rollback, and verify that the release, package, and worker state are back
at the stable read-only baseline.
EOF_README
  chmod +x "$workspace_dir/bin/"*.sh
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
[ -n "$model" ] || { echo "No installed models available; partial system rollback probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_partial_system_rollback_workspace "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Diagnose the bounded partially landed local mutation in this workspace. Use the provided `bin/status.sh`, `bin/rollback.sh`, `bin/health.sh`, and `bin/verify.sh` helpers. Roll back only the mixed local release, package, and worker state, make the smallest safe state fix so rollback is approved, run the rollback, rerun health and verify, and stop there. Do not widen beyond this one bounded rollback. End with sections: Outcome, Verification Evidence, Risks, Next Improvement.
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

state_rewritten=0
if grep -q '^CURRENT_RELEASE=2026.03.15$' "$tmp_ws/state/system.env" \
  && grep -q '^CURRENT_PACKAGE=2.3.1$' "$tmp_ws/state/system.env" \
  && grep -q '^CURRENT_WORKER=healthy$' "$tmp_ws/state/system.env" \
  && grep -q '^ROLLBACK_APPROVED=1$' "$tmp_ws/state/system.env" \
  && grep -q '^READ_ONLY=1$' "$tmp_ws/state/system.env" \
  && grep -q '^PARTIAL_STATE=rolled_back$' "$tmp_ws/state/system.env"; then
  state_rewritten=1
fi

status_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/status.sh")) | if . then 1 else 0 end')
rollback_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/rollback.sh")) | if . then 1 else 0 end')
health_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/health.sh")) | if . then 1 else 0 end')
verify_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/verify.sh")) | if . then 1 else 0 end')
rollback_log_present=$([ -f "$tmp_ws/audit/rollback.log" ] && printf '%s' "1" || printf '%s' "0")
rollback_applied=$(grep -q '^applied$' "$tmp_ws/state/rollback.status" 2>/dev/null && printf '%s' "1" || printf '%s' "0")
health_ok=$(sh "$tmp_ws/bin/health.sh" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
verify_ok=$(sh "$tmp_ws/bin/verify.sh" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
rollback_ref=$(printf '%s\n%s' "$assistant_text" "$stream_text" | tr '[:upper:]' '[:lower:]' | grep -q 'rollback' && printf '%s' "1" || printf '%s' "0")
has_outcome=$(printf '%s\n' "$assistant_text" | grep -q '^Outcome:' && printf '%s' "1" || printf '%s' "0")
has_verify=$(printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:' && printf '%s' "1" || printf '%s' "0")
has_risks=$(printf '%s\n' "$assistant_text" | grep -q '^Risks:' && printf '%s' "1" || printf '%s' "0")
has_next=$(printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:' && printf '%s' "1" || printf '%s' "0")
stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$state_rewritten" -eq 1 ] && [ "$status_ran" -eq 1 ] && [ "$rollback_ran" -eq 1 ] && [ "$health_ran" -eq 1 ] && [ "$verify_ran" -eq 1 ] && [ "$rollback_applied" -eq 1 ] && [ "$rollback_log_present" -eq 1 ] && [ "$health_ok" -eq 1 ] && [ "$verify_ok" -eq 1 ] && [ "$rollback_ref" -eq 1 ] && [ "$has_outcome" -eq 1 ] && [ "$has_verify" -eq 1 ] && [ "$has_risks" -eq 1 ] && [ "$has_next" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","model":"%s","timed_out":%s,"state_rewritten":%s,"status_ran":%s,"rollback_ran":%s,"health_ran":%s,"verify_ran":%s,"rollback_applied":%s,"rollback_log_present":%s,"health_ok":%s,"verify_ok":%s,"rollback_referenced":%s,"has_outcome":%s,"has_verify":%s,"has_risks":%s,"has_next":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$model" "$timed_out" "$state_rewritten" "$status_ran" "$rollback_ran" "$health_ran" "$verify_ran" "$rollback_applied" "$rollback_log_present" "$health_ok" "$verify_ok" "$rollback_ref" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$stream_line_count" > "$json_file"

{
  printf '# Partial System Rollback Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- State rewritten: %s\n' "$state_rewritten"
  printf -- '- `status.sh` ran: %s\n' "$status_ran"
  printf -- '- `rollback.sh` ran: %s\n' "$rollback_ran"
  printf -- '- `health.sh` ran: %s\n' "$health_ran"
  printf -- '- `verify.sh` ran: %s\n' "$verify_ran"
  printf -- '- Rollback applied: %s\n' "$rollback_applied"
  printf -- '- Rollback log present: %s\n' "$rollback_log_present"
  printf -- '- Health now passes: %s\n' "$health_ok"
  printf -- '- Verify now passes: %s\n' "$verify_ok"
  printf -- '- Rollback referenced: %s\n' "$rollback_ref"
  printf -- '- Outcome section: %s\n' "$has_outcome"
  printf -- '- Verification section: %s\n' "$has_verify"
  printf -- '- Risks section: %s\n' "$has_risks"
  printf -- '- Next Improvement section: %s\n' "$has_next"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
