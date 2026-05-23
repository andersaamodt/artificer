#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
APP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
API_SCRIPT="$APP_ROOT/hosted-web/cgi/artificer-api"

# Shared shell helpers.
. "$SCRIPT_DIR/lib/http_form.sh"
. "$SCRIPT_DIR/lib/kv.sh"
. "$SCRIPT_DIR/lib/lockdir.sh"

STATE_ROOT=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/artificer}
LOCK_DIR="$STATE_ROOT/automation-worker.lock"
DAEMON_LABEL="com.artificer.automations"
SYSTEMD_TIMER="artificer-automations.timer"
SYSTEMD_SERVICE="artificer-automations.service"
CRON_MARKER="ARTIFICER_AUTOMATIONS"

log_file_path() {
  printf '%s' "$STATE_ROOT/automation-daemon.log"
}

api_post_json() {
  body=$1
  if [ ! -x "$API_SCRIPT" ]; then
    printf '%s\n' '{"success":false,"error":"artificer-api is not executable"}'
    return 0
  fi
  raw=$(REQUEST_METHOD=POST sh "$API_SCRIPT" <<EOF
$body
EOF
)
  json=$(printf '%s' "$raw" | json_only)
  if [ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ]; then
    printf '%s\n' '{"success":false,"error":"API response did not include JSON payload"}'
    return 0
  fi
  printf '%s\n' "$json"
}

acquire_lock() {
  lockdir_acquire "$LOCK_DIR" "$$"
}

release_lock() {
  lockdir_release "$LOCK_DIR"
}

queue_targets_from_state_json() {
  state_json=$1
  python3 - "$state_json" <<'PY'
import json
import sys

payload = {}
try:
    payload = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
    payload = {}

for workspace in payload.get("workspaces", []) or []:
    workspace_id = str((workspace or {}).get("id", ""))
    if not workspace_id:
        continue
    for conversation in (workspace or {}).get("conversations", []) or []:
        conv = conversation or {}
        conversation_id = str(conv.get("id", ""))
        if not conversation_id:
            continue
        running = str(conv.get("queue_running", "0")) == "1"
        pending_raw = str(conv.get("queue_pending", "0"))
        try:
            pending = int(pending_raw)
        except Exception:
            pending = 0
        if running or pending <= 0:
            continue
        print(f"{workspace_id}\t{conversation_id}")
PY
}

take_response_to_run_body_kv() {
  take_json=$1
  workspace_id=$2
  conversation_id=$3
  python3 - "$take_json" "$workspace_id" "$conversation_id" <<'PY'
import json
import sys
import urllib.parse

payload = {}
try:
    payload = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
    payload = {"success": False, "error": "invalid JSON"}

workspace_id = sys.argv[2] if len(sys.argv) > 2 else ""
conversation_id = sys.argv[3] if len(sys.argv) > 3 else ""

if not payload.get("success"):
    error_text = str(payload.get("error", "queue_take failed"))
    print("status=error")
    print("error=" + urllib.parse.quote(error_text, safe=""))
    raise SystemExit(0)

if payload.get("busy"):
    print("status=busy")
    raise SystemExit(0)

if not payload.get("has_item"):
    print("status=none")
    raise SystemExit(0)

item = payload.get("item") if isinstance(payload.get("item"), dict) else {}
attachments = item.get("attachments") if isinstance(item.get("attachments"), list) else []
skills = item.get("explicit_skill_ids") if isinstance(item.get("explicit_skill_ids"), list) else []

params = {
    "action": "run",
    "workspace_id": workspace_id,
    "conversation_id": conversation_id,
    "queue_item_id": str(item.get("id", "")),
    "prompt": str(item.get("prompt", "")),
    "attachment_ids": ",".join(str(v) for v in attachments if str(v)),
    "run_mode": str(item.get("run_mode", "")),
    "assistant_mode_id": str(item.get("assistant_mode_id", "")),
    "compute_budget": str(item.get("compute_budget", "")),
    "reasoning_effort": str(item.get("reasoning_effort", "")),
    "command_exec_mode": str(item.get("command_exec_mode", "")),
    "permission_mode": str(item.get("permission_mode", "")),
    "programmer_review": str(item.get("programmer_review", "")),
    "programmer_review_rounds": str(item.get("programmer_review_rounds", "")),
    "explicit_skill_ids": ",".join(str(v) for v in skills if str(v)),
}

print("status=item")
print("body=" + urllib.parse.urlencode(params))
PY
}

tick_once_kv() {
  if ! acquire_lock; then
    cat <<'EOF'
busy=1
checked=0
triggered=0
errors=0
attempted=0
processed=0
failures=0
message=automation worker already running
EOF
    return 0
  fi

  trap 'release_lock' EXIT HUP INT TERM

  tick_json=$(api_post_json "$(form_body action automations_tick)")
  tick_info=$(python3 - "$tick_json" <<'PY'
import json
import sys

payload = {}
try:
    payload = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
    payload = {"success": False, "error": "invalid JSON"}

if not payload.get("success"):
    print("ok=0")
    print("checked=0")
    print("triggered=0")
    print("errors=1")
    print("message=" + str(payload.get("error", "automations_tick failed")))
else:
    print("ok=1")
    print("checked=" + str(payload.get("checked", "0")))
    print("triggered=" + str(payload.get("triggered", "0")))
    print("errors=" + str(payload.get("errors", "0")))
    print("message=")
PY
)

ok=$(kv_get ok "$tick_info")
checked=$(kv_get checked "$tick_info")
triggered=$(kv_get triggered "$tick_info")
errors=$(kv_get errors "$tick_info")
message=$(kv_get message "$tick_info")

attempted=0
processed=0
failures=0

if [ "$ok" = "1" ]; then
  state_json=$(api_post_json "$(form_body action state)")
  targets=$(queue_targets_from_state_json "$state_json")

  max_runs=${ARTIFICER_AUTOMATION_MAX_RUNS_PER_TICK:-6}
  case "$max_runs" in
    ''|*[!0-9]*)
      max_runs=6
      ;;
  esac
  if [ "$max_runs" -lt 1 ]; then
    max_runs=1
  fi
  if [ "$max_runs" -gt 30 ]; then
    max_runs=30
  fi

  while IFS="$(printf '\t')" read -r workspace_id conversation_id || [ -n "$workspace_id$conversation_id" ]; do
    [ -n "$workspace_id" ] || continue
    [ -n "$conversation_id" ] || continue
    if [ "$attempted" -ge "$max_runs" ]; then
      break
    fi

    take_json=$(api_post_json "$(form_body action queue_take workspace_id "$workspace_id" conversation_id "$conversation_id")")
    take_kv=$(take_response_to_run_body_kv "$take_json" "$workspace_id" "$conversation_id")
    take_status=$(kv_get status "$take_kv")

    case "$take_status" in
      busy|none)
        continue
        ;;
      error)
        failures=$((failures + 1))
        continue
        ;;
      item)
        run_body=$(kv_get body "$take_kv")
        if [ -z "$run_body" ]; then
          failures=$((failures + 1))
          continue
        fi
        attempted=$((attempted + 1))
        run_json=$(api_post_json "$run_body")
        run_success=$(python3 - "$run_json" <<'PY'
import json
import sys
try:
    payload = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
    payload = {"success": False}
print("1" if payload.get("success") else "0")
PY
)
        if [ "$run_success" = "1" ]; then
          processed=$((processed + 1))
        else
          failures=$((failures + 1))
        fi
        ;;
      *)
        failures=$((failures + 1))
        ;;
    esac
  done <<EOF
$targets
EOF
fi

cat <<EOF
busy=0
checked=${checked:-0}
triggered=${triggered:-0}
errors=${errors:-0}
attempted=$attempted
processed=$processed
failures=$failures
message=${message}
EOF
}

daemon_interval_seconds() {
  interval=${ARTIFICER_AUTOMATION_DAEMON_INTERVAL_SEC:-30}
  case "$interval" in
    ''|*[!0-9]*)
      interval=30
      ;;
  esac
  if [ "$interval" -lt 15 ]; then
    interval=15
  fi
  if [ "$interval" -gt 600 ]; then
    interval=600
  fi
  printf '%s' "$interval"
}

daemon_method() {
  os=$(uname -s 2>/dev/null || printf unknown)
  case "$os" in
    Darwin)
      printf 'launchd'
      return 0
      ;;
    Linux)
      if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files >/dev/null 2>&1; then
        printf 'systemd'
        return 0
      fi
      if command -v crontab >/dev/null 2>&1; then
        printf 'cron'
        return 0
      fi
      ;;
  esac
  printf 'none'
}

daemon_status_kv() {
  method=$(daemon_method)
  enabled=0
  active=0
  supported=1
  detail=""

  case "$method" in
    launchd)
      plist="$HOME/Library/LaunchAgents/$DAEMON_LABEL.plist"
      if [ -f "$plist" ]; then
        enabled=1
      fi
      if launchctl list 2>/dev/null | grep -F "$DAEMON_LABEL" >/dev/null 2>&1; then
        active=1
      fi
      detail="$plist"
      ;;
    systemd)
      if systemctl --user is-enabled "$SYSTEMD_TIMER" >/dev/null 2>&1; then
        enabled=1
      fi
      if systemctl --user is-active "$SYSTEMD_TIMER" >/dev/null 2>&1; then
        active=1
      fi
      detail="$SYSTEMD_TIMER"
      ;;
    cron)
      if crontab -l 2>/dev/null | grep -F "$CRON_MARKER" >/dev/null 2>&1; then
        enabled=1
        active=1
      fi
      detail="crontab"
      ;;
    none)
      supported=0
      detail="unsupported platform"
      ;;
  esac

  cat <<EOF
supported=$supported
method=$method
enabled=$enabled
active=$active
label=$DAEMON_LABEL
detail=$detail
EOF
}

daemon_enable_launchd() {
  interval=$(daemon_interval_seconds)
  plist_dir="$HOME/Library/LaunchAgents"
  plist="$plist_dir/$DAEMON_LABEL.plist"
  log_file=$(log_file_path)
  mkdir -p "$plist_dir" "$STATE_ROOT"

  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$DAEMON_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$SCRIPT_DIR/artificer-automations.sh</string>
    <string>tick</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>$interval</integer>
  <key>StandardOutPath</key>
  <string>$log_file</string>
  <key>StandardErrorPath</key>
  <string>$log_file</string>
</dict>
</plist>
EOF

  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist" >/dev/null 2>&1
}

daemon_disable_launchd() {
  plist="$HOME/Library/LaunchAgents/$DAEMON_LABEL.plist"
  launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
}

daemon_enable_systemd() {
  interval=$(daemon_interval_seconds)
  user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  service_file="$user_dir/$SYSTEMD_SERVICE"
  timer_file="$user_dir/$SYSTEMD_TIMER"
  mkdir -p "$user_dir" "$STATE_ROOT"

  cat > "$service_file" <<EOF
[Unit]
Description=Artificer automations tick

[Service]
Type=oneshot
ExecStart=/bin/sh $SCRIPT_DIR/artificer-automations.sh tick
EOF

  cat > "$timer_file" <<EOF
[Unit]
Description=Run Artificer automations on a timer

[Timer]
OnBootSec=45s
OnUnitActiveSec=${interval}s
Persistent=true
Unit=$SYSTEMD_SERVICE

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now "$SYSTEMD_TIMER"
}

daemon_disable_systemd() {
  user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  service_file="$user_dir/$SYSTEMD_SERVICE"
  timer_file="$user_dir/$SYSTEMD_TIMER"
  systemctl --user disable --now "$SYSTEMD_TIMER" >/dev/null 2>&1 || true
  systemctl --user disable "$SYSTEMD_SERVICE" >/dev/null 2>&1 || true
  rm -f "$service_file" "$timer_file"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

daemon_enable_cron() {
  log_file=$(log_file_path)
  mkdir -p "$STATE_ROOT"
  entry="* * * * * /bin/sh \"$SCRIPT_DIR/artificer-automations.sh\" tick >> \"$log_file\" 2>&1 # $CRON_MARKER"
  current=$(crontab -l 2>/dev/null || true)
  next=$(printf '%s\n' "$current" | sed "/$CRON_MARKER/d")
  if [ -n "$next" ]; then
    printf '%s\n%s\n' "$next" "$entry" | crontab -
  else
    printf '%s\n' "$entry" | crontab -
  fi
}

daemon_disable_cron() {
  current=$(crontab -l 2>/dev/null || true)
  next=$(printf '%s\n' "$current" | sed "/$CRON_MARKER/d")
  if [ -n "$next" ]; then
    printf '%s\n' "$next" | crontab -
  else
    crontab -r >/dev/null 2>&1 || true
  fi
}

daemon_enable() {
  method=$(daemon_method)
  case "$method" in
    launchd)
      daemon_enable_launchd
      ;;
    systemd)
      daemon_enable_systemd
      ;;
    cron)
      daemon_enable_cron
      ;;
    *)
      printf '%s\n' 'automation daemon is not supported on this platform' >&2
      return 1
      ;;
  esac
  daemon_status_kv
}

daemon_disable() {
  method=$(daemon_method)
  case "$method" in
    launchd)
      daemon_disable_launchd
      ;;
    systemd)
      daemon_disable_systemd
      ;;
    cron)
      daemon_disable_cron
      ;;
    *)
      printf '%s\n' 'automation daemon is not supported on this platform' >&2
      return 1
      ;;
  esac
  daemon_status_kv
}

status_json() {
  status_kv=$1
  python3 - "$status_kv" <<'PY'
import json
import sys

pairs = {}
for line in str(sys.argv[1] if len(sys.argv) > 1 else "").splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    pairs[key] = value

def as_bool(text):
    return str(text).strip().lower() in {"1", "true", "yes", "on", "enabled"}

payload = {
    "success": True,
    "supported": as_bool(pairs.get("supported", "0")),
    "enabled": as_bool(pairs.get("enabled", "0")),
    "active": as_bool(pairs.get("active", "0")),
    "method": pairs.get("method", "none"),
    "label": pairs.get("label", ""),
    "detail": pairs.get("detail", ""),
}
print(json.dumps(payload, separators=(",", ":")))
PY
}

print_status_human() {
  status_kv=$1
  supported=$(kv_get supported "$status_kv")
  enabled=$(kv_get enabled "$status_kv")
  active=$(kv_get active "$status_kv")
  method=$(kv_get method "$status_kv")
  detail=$(kv_get detail "$status_kv")

  if [ "$supported" != "1" ]; then
    printf '%s\n' 'Automation daemon: unsupported on this platform.'
    return 0
  fi

  daemon_state='disabled'
  if [ "$enabled" = "1" ]; then
    daemon_state='enabled'
  fi
  running_state='inactive'
  if [ "$active" = "1" ]; then
    running_state='active'
  fi
  printf '%s\n' "Automation daemon: $daemon_state ($running_state) via $method"
  if [ -n "$detail" ]; then
    printf '%s\n' "Detail: $detail"
  fi
}

usage() {
  cat <<'EOF'
Usage: artificer-automations.sh <command>

Commands:
  tick             Run one automation tick and drain queued runs.
  loop [seconds]   Run ticks continuously.
  status           Print daemon status (human-readable).
  status-kv        Print daemon status as key=value lines.
  status-json      Print daemon status JSON.
  enable           Enable background daemon.
  disable          Disable background daemon.
EOF
}

command=${1-status}
case "$command" in
  tick)
    tick_once_kv
    ;;
  loop)
    interval=${2-30}
    case "$interval" in
      ''|*[!0-9]*)
        interval=30
        ;;
    esac
    if [ "$interval" -lt 5 ]; then
      interval=5
    fi
    while :; do
      tick_once_kv
      sleep "$interval"
    done
    ;;
  status)
    status_kv=$(daemon_status_kv)
    print_status_human "$status_kv"
    ;;
  status-kv)
    daemon_status_kv
    ;;
  status-json)
    status_kv=$(daemon_status_kv)
    status_json "$status_kv"
    ;;
  enable)
    daemon_enable
    ;;
  disable)
    daemon_disable
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
