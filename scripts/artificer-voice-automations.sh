#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
backend_script="$script_dir/artificer-native-backend.sh"
home=${HOME:?}
state_root=${ARTIFICER_NATIVE_STATE_ROOT:-${XDG_STATE_HOME:-"$home/.local/state"}/artificer-native}
config_root=${XDG_CONFIG_HOME:-"$home/.config"}/artificer
prefs_file="$config_root/ui-prefs.env"
daemon_dir="$state_root/voice-automations"
status_file="$daemon_dir/status.env"
lock_dir="$daemon_dir/tick.lock"
label="com.artificer.voice-automations"
plist="$home/Library/LaunchAgents/$label.plist"
log_file="$daemon_dir/voice-automations.log"

usage() {
  cat <<'USAGE'
Usage: artificer-voice-automations.sh status|enable|disable|daemon|tick

Runs Artificer's local voice automation listener.
USAGE
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1] if len(sys.argv) > 1 else ""))
PY
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

payload = {}
try:
    payload = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
    payload = {}

value = payload
for part in (sys.argv[2] if len(sys.argv) > 2 else "").split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
        break

if isinstance(value, bool):
    print("1" if value else "0")
elif value is None:
    print("")
else:
    print(str(value))
PY
}

normalize_phrase() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
text = text.lower()
text = re.sub(r"[^a-z0-9 ]+", " ", text)
text = re.sub(r"\s+", " ", text).strip()
print(text)
PY
}

phrase_in_list() {
  phrase=$1
  list=$2
  python3 - "$phrase" "$list" <<'PY'
import re
import sys

phrase = sys.argv[1] if len(sys.argv) > 1 else ""
items = sys.argv[2] if len(sys.argv) > 2 else ""

def normalize(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text

allowed = {normalize(item) for item in re.split(r"[,;|]", items) if normalize(item)}
raise SystemExit(0 if phrase in allowed else 1)
PY
}

ensure_dirs() {
  mkdir -p "$daemon_dir" "$config_root" "$home/Library/LaunchAgents"
}

read_pref_raw() {
  key=$1
  [ -f "$prefs_file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$prefs_file"
}

pref_bool() {
  key=$1
  value=$(read_pref_raw "$key" 2>/dev/null || printf '0')
  case "$value" in
    1|true|yes|on|enabled) printf '1' ;;
    *) printf '0' ;;
  esac
}

pref_text() {
  key=$1
  read_pref_raw "$key" 2>/dev/null || printf ''
}

write_status() {
  ensure_dirs
  status=$1
  message=$2
  phrase=$3
  action=$4
  now=$(date +%s 2>/dev/null || printf '0')
  tmp_file="$status_file.$$"
  {
    printf 'status=%s\n' "$status"
    printf 'message=%s\n' "$message"
    printf 'last_phrase=%s\n' "$phrase"
    printf 'last_action=%s\n' "$action"
    printf 'updated_at=%s\n' "$now"
  } > "$tmp_file"
  mv "$tmp_file" "$status_file"
}

status_value() {
  key=$1
  [ -f "$status_file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$status_file"
}

status_json() {
  enabled=false
  active=false
  launchd_enabled=false
  [ "$(pref_bool voice_automations)" = 1 ] && enabled=true
  [ -f "$plist" ] && launchd_enabled=true
  if launchctl list 2>/dev/null | grep -F "$label" >/dev/null 2>&1; then
    active=true
  fi
  status=$(status_value status 2>/dev/null || printf 'disabled')
  message=$(status_value message 2>/dev/null || printf '')
  last_phrase=$(status_value last_phrase 2>/dev/null || printf '')
  last_action=$(status_value last_action 2>/dev/null || printf '')
  updated_at=$(status_value updated_at 2>/dev/null || printf '0')
  printf '{"success":true,"supported":true,"enabled":%s,"launchd_enabled":%s,"active":%s,"status":%s,"message":%s,"last_phrase":%s,"last_action":%s,"updated_at":%s,"label":%s,"log_path":%s}\n' \
    "$enabled" \
    "$launchd_enabled" \
    "$active" \
    "$(json_escape "$status")" \
    "$(json_escape "$message")" \
    "$(json_escape "$last_phrase")" \
    "$(json_escape "$last_action")" \
    "$(json_escape "$updated_at")" \
    "$(json_escape "$label")" \
    "$(json_escape "$log_file")"
}

enable_launchd() {
  ensure_dirs
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$script_dir/artificer-voice-automations.sh</string>
    <string>daemon</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_file</string>
  <key>StandardErrorPath</key>
  <string>$log_file</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist" >/dev/null 2>&1 || true
  write_status idle "Voice automations enabled." "" ""
}

disable_launchd() {
  launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
  write_status disabled "Voice automations disabled." "" ""
}

run_known_action() {
  phrase=$1
  for slot in 1 2; do
    name=$(pref_text "voice_local_action_${slot}_name")
    command_text=$(pref_text "voice_local_action_${slot}_command")
    phrases=$(pref_text "voice_local_action_${slot}_phrases")
    [ -n "$command_text" ] || continue
    [ -n "$phrases" ] || continue
    [ -n "$name" ] || name="Local action $slot"
    if phrase_in_list "$phrase" "$phrases"; then
      if /bin/sh -c "$command_text" >/dev/null 2>&1; then
        write_status triggered "Ran local action: $name." "$phrase" "$command_text"
        return 0
      fi
      write_status error "Local action failed: $name." "$phrase" "$command_text"
      return 1
    fi
  done
  return 2
}

llm_prompt_from_phrase() {
  phrase=$1
  case "$phrase" in
    "artificer "*) printf '%s\n' "${phrase#artificer }" ;;
    "ask artificer "*) printf '%s\n' "${phrase#ask artificer }" ;;
    "hey artificer "*) printf '%s\n' "${phrase#hey artificer }" ;;
    *) return 1 ;;
  esac
}

queue_llm_prompt() {
  phrase=$1
  prompt=$(llm_prompt_from_phrase "$phrase" || true)
  [ -n "$prompt" ] || return 2
  [ "$(pref_bool voice_automation_llm_prompts)" = 1 ] || return 2

  workspace_id=$(pref_text selected_workspace_id)
  conversation_id=$(pref_text selected_conversation_id)
  if [ -z "$workspace_id" ] || [ -z "$conversation_id" ]; then
    write_status error "Voice prompt has no selected Artificer thread." "$phrase" "llm-prompt"
    return 1
  fi

  if [ "$(pref_bool voice_automation_llm_actions)" = 1 ]; then
    command_mode=all
    self_actuation=1
  else
    command_mode=none
    self_actuation=0
  fi

  "$backend_script" session-message "$workspace_id" "$conversation_id" "$prompt" auto medium "$command_mode" default 1 2 0 "$self_actuation" "" >/dev/null
  "$backend_script" session-run-next "$workspace_id" "$conversation_id" >/dev/null
  write_status triggered "Queued voice prompt for Artificer." "$phrase" "llm-prompt"
  return 0
}

tick_once() {
  ensure_dirs
  if [ "$(pref_bool voice_automations)" != 1 ]; then
    write_status disabled "Voice automations are off." "" ""
    return 0
  fi

  if ! mkdir "$lock_dir" 2>/dev/null; then
    write_status busy "Voice automation tick already running." "" ""
    return 0
  fi
  trap 'rmdir "$lock_dir" >/dev/null 2>&1 || true' EXIT HUP INT TERM
  tick_once_locked
  tick_rc=$?
  rmdir "$lock_dir" >/dev/null 2>&1 || true
  trap - EXIT HUP INT TERM
  return "$tick_rc"
}

tick_once_locked() {
  status_json=$("$backend_script" dictation-status 2>/dev/null || printf '{}')
  installed=$(json_get "$status_json" installed)
  if [ "$installed" != 1 ]; then
    write_status waiting "Local dictation backend is not installed." "" ""
    return 0
  fi

  start_json=$("$backend_script" dictation-start auto 2>/dev/null || printf '{}')
  session_id=$(json_get "$start_json" session.id)
  if [ -z "$session_id" ]; then
    message=$(json_get "$start_json" error)
    [ -n "$message" ] || message="Dictation did not start."
    write_status error "$message" "" ""
    return 0
  fi

  window_seconds=${ARTIFICER_VOICE_AUTOMATION_WINDOW_SECONDS:-3}
  case "$window_seconds" in
    ''|*[!0-9]*)
      window_seconds=3
      ;;
  esac
  if [ "$window_seconds" -lt 2 ]; then
    window_seconds=2
  fi
  if [ "$window_seconds" -gt 8 ]; then
    window_seconds=8
  fi
  sleep "$window_seconds"

  stop_json=$("$backend_script" dictation-stop "$session_id" 2>/dev/null || printf '{}')
  text=$(json_get "$stop_json" text)
  if [ -z "$text" ]; then
    write_status listening "Listening for voice automation phrases." "" ""
    return 0
  fi

  phrase=$(normalize_phrase "$text")
  if [ -z "$phrase" ]; then
    write_status listening "Listening for voice automation phrases." "" ""
    return 0
  fi

  if run_known_action "$phrase"; then
    return 0
  fi
  action_rc=$?
  if [ "$action_rc" != 2 ]; then
    return 0
  fi

  if queue_llm_prompt "$phrase"; then
    return 0
  fi
  prompt_rc=$?
  if [ "$prompt_rc" != 2 ]; then
    return 0
  fi

  write_status listening "No voice automation phrase matched." "$phrase" ""
}

daemon_loop() {
  ensure_dirs
  write_status listening "Voice automations listening locally." "" ""
  while [ "$(pref_bool voice_automations)" = 1 ]; do
    tick_once || true
    cooldown=${ARTIFICER_VOICE_AUTOMATION_COOLDOWN_SECONDS:-2}
    case "$cooldown" in
      ''|*[!0-9]*)
        cooldown=2
        ;;
    esac
    if [ "$cooldown" -lt 1 ]; then
      cooldown=1
    fi
    if [ "$cooldown" -gt 30 ]; then
      cooldown=30
    fi
    sleep "$cooldown"
  done
  write_status disabled "Voice automations are off." "" ""
}

case "${1-}" in
  --help|--usage|-h)
    usage
    ;;
  status)
    status_json
    ;;
  enable)
    enable_launchd
    status_json
    ;;
  disable)
    disable_launchd
    status_json
    ;;
  tick)
    tick_once
    status_json
    ;;
  daemon)
    daemon_loop
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
