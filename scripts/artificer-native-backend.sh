#!/bin/sh

case "${1-}" in
--help|--usage|-h)
  cat <<'USAGE'
Usage: artificer-native-backend.sh ACTION [ARGS...]

Actions:
  doctor
  prefs-get
  prefs-set-core-root CORE_ROOT
  desktop-prefs-get
  desktop-prefs-set KEY ENABLED
  desktop-value-set KEY VALUE
  desktop-selection-set WORKSPACE_ID CONVERSATION_ID
  voice-automations-status
  voice-automations-tick
  mobile-status
  mobile-enable
  mobile-disable
  mobile-restart
  mobile-install-tor
  mobile-set KEY VALUE
  health
  projects
  project-add PATH NAME [COMMAND_EXEC_MODE]
  project-rename WORKSPACE_ID NAME
  project-delete WORKSPACE_ID
  sessions WORKSPACE_ID
  session WORKSPACE_ID CONVERSATION_ID
  session-create WORKSPACE_ID TITLE [MODEL]
  session-archive WORKSPACE_ID CONVERSATION_ID
  session-set-model WORKSPACE_ID CONVERSATION_ID MODEL
  session-message WORKSPACE_ID CONVERSATION_ID PROMPT RUN_MODE COMPUTE_BUDGET COMMAND_EXEC_MODE PERMISSION_MODE PROGRAMMER_REVIEW PROGRAMMER_REVIEW_ROUNDS REFLEXIVE_KNOWLEDGE SELF_ACTUATION [ATTACHMENT_IDS] [REASONING_EFFORT]
  draft-get WORKSPACE_ID
  draft-save WORKSPACE_ID DRAFT
  conversation-draft-save WORKSPACE_ID CONVERSATION_ID DRAFT
  attachment-upload WORKSPACE_ID CONVERSATION_ID FILE_PATH [MIME]
  session-run-next WORKSPACE_ID CONVERSATION_ID
  session-events WORKSPACE_ID CONVERSATION_ID [STREAM_SESSION] [OFFSET]
  git-status WORKSPACE_ID
  git-diff WORKSPACE_ID
  git-branches WORKSPACE_ID
  git-checkout-branch WORKSPACE_ID BRANCH [CREATE]
  git-commit WORKSPACE_ID INCLUDE_UNSTAGED MESSAGE [PUSH]
  git-push WORKSPACE_ID
  open-project-target WORKSPACE_ID TARGET
  queue-list WORKSPACE_ID CONVERSATION_ID [LIMIT]
  queue-update WORKSPACE_ID CONVERSATION_ID ITEM_ID PROMPT
  queue-reorder WORKSPACE_ID CONVERSATION_ID ITEM_IDS
  queue-cancel WORKSPACE_ID CONVERSATION_ID [ITEM_ID]
  queue-stop WORKSPACE_ID CONVERSATION_ID
  approval-answer WORKSPACE_ID CONVERSATION_ID DECISION SCOPE MATCH_MODE [PATTERN] [COMMAND]
  command-rules-list WORKSPACE_ID
  command-rules-clear WORKSPACE_ID SCOPE
  command-rule-delete WORKSPACE_ID SCOPE INDEX
  decision-answer WORKSPACE_ID CONVERSATION_ID ANSWER
  terminal-session-start WORKSPACE_ID
  terminal-session-poll WORKSPACE_ID SESSION_ID [OFFSET]
  terminal-session-input WORKSPACE_ID SESSION_ID INPUT
  terminal-session-stop WORKSPACE_ID SESSION_ID
  dictation-status
  dictation-language-get
  dictation-language-set LANGUAGE
  dictation-prewarm-get
  dictation-prewarm-set ENABLED
  dictation-shortcuts-get
  dictation-shortcuts-set HOLD TOGGLE
  dictation-install-start
  dictation-install-status JOB_ID
  dictation-install-cancel JOB_ID
  dictation-start [LANGUAGE]
  dictation-levels [SESSION_ID]
  dictation-stop SESSION_ID
  dictation-transcribe-file AUDIO_PATH [LANGUAGE]
  voice-automations-handle-text TEXT
  self-improve-settings
  self-improve-codex-work-check-set ENABLED
  self-improve-run-options-set OBJECTIVE COMPETITION_ENABLED CHALLENGER_MODEL CODEX_WORK_CHECK SOURCE_PAPERS SOURCE_WEB SOURCE_RUNTIME SOURCE_REPO SOURCE_PLATFORM
  self-improve-run MODEL OBJECTIVE COMPETITION_ENABLED CHALLENGER_MODEL CODEX_WORK_CHECK SOURCE_PAPERS SOURCE_WEB SOURCE_RUNTIME SOURCE_REPO SOURCE_PLATFORM
  automations
  automation-upsert WORKSPACE_ID CONVERSATION_ID NAME PROMPT SCHEDULE_KIND SCHEDULE_VALUE ENABLED ALLOW_SELF_RESCHEDULE RUN_MODE COMPUTE_BUDGET COMMAND_EXEC_MODE PERMISSION_MODE PROGRAMMER_REVIEW PROGRAMMER_REVIEW_ROUNDS NEXT_RUN [AUTOMATION_ID]
  automation-run AUTOMATION_ID
  automation-toggle AUTOMATION_ID ENABLED
  automation-delete AUTOMATION_ID
  models
  model-catalog
  model-install-start MODEL
  model-install-status JOB_ID
  model-uninstall MODEL
  llm-runtime-settings-get
  llm-runtime-settings-set USE_GPU DEFAULT_MODEL SMART_TITLES
  git-runtime-settings-get
  git-runtime-settings-set WORKFLOW_POLICY AMBIGUITY_POLICY
  automation-daemon-status
  automation-daemon-enable
  automation-daemon-pause
  automation-daemon-resume
  automation-daemon-disable
  automation-daemon-tick
  open-web
USAGE
  exit 0
  ;;
esac

set -eu

action=${1-}
shift || true

home=${HOME:?}
nl='
'
cr=$(printf '\r')
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

config_root() {
  printf '%s\n' "${XDG_CONFIG_HOME:-"$home/.config"}/wizardry-apps/artificer-native"
}

prefs_file() {
  printf '%s\n' "$(config_root)/ui-prefs.conf"
}

desktop_prefs_dir() {
  printf '%s\n' "${XDG_CONFIG_HOME:-"$home/.config"}/artificer"
}

desktop_prefs_file() {
  printf '%s\n' "$(desktop_prefs_dir)/ui-prefs.env"
}

reject_line_breaks() {
  value=${1-}
  label=${2-value}
  case "$value" in
    *"$nl"*|*"$cr"*)
      printf '%s\n' "artificer-native-backend: $label must not contain line breaks" >&2
      exit 2
      ;;
  esac
}

voice_recognition_root_dir() {
  if [ -n "${VOICE_RECOGNITION_ROOT_DIR-}" ]; then
    reject_line_breaks "$VOICE_RECOGNITION_ROOT_DIR" "voice recognition root"
    printf '%s\n' "$VOICE_RECOGNITION_ROOT_DIR"
    return 0
  fi
  if [ -n "${WIZARDRY_VOICE_RECOGNITION_DIR-}" ]; then
    reject_line_breaks "$WIZARDRY_VOICE_RECOGNITION_DIR" "voice recognition root"
    printf '%s\n' "$WIZARDRY_VOICE_RECOGNITION_DIR"
    return 0
  fi
  root="${XDG_STATE_HOME:-"$home/.local/state"}/wizardry/voice-recognition"
  reject_line_breaks "$root" "voice recognition root"
  printf '%s\n' "$root"
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1] if len(sys.argv) > 1 else ""))
PY
}

json_error() {
  message=${1-error}
  printf '{"success":false,"error":%s}\n' "$(json_escape "$message")"
}

read_pref() {
  key=$1
  file=$(prefs_file)
  [ -f "$file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$file"
}

write_pref() {
  key=$1
  value=$2
  reject_line_breaks "$key" "preference key"
  reject_line_breaks "$value" "preference value"
  case "$key" in
    core_root) ;;
    *)
      printf '%s\n' "artificer-native-backend: unsupported preference key" >&2
      exit 2
      ;;
  esac
  mkdir -p "$(config_root)"
  file=$(prefs_file)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-native-prefs.XXXXXX")
  if [ -f "$file" ]; then
    awk -F= -v wanted="$key" '$1 != wanted' "$file" > "$tmp_file"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  mv "$tmp_file" "$file"
}

canonical_desktop_pref_key() {
  key=$1
  reject_line_breaks "$key" "desktop preference key"
  case "$key" in
    background_mode|menu_bar_icon|voice_automations|voice_automation_sound|voice_builtin_commands|voice_dictation_commands|voice_automation_llm_prompts|voice_automation_llm_actions|mobile_bridge|mobile_tor|mobile_lan|mobile_allow_execute|mobile_allow_self_actuation)
      printf '%s\n' "$key"
      ;;
    *)
      printf '%s\n' "artificer-native-backend: unsupported desktop preference key" >&2
      exit 2
      ;;
  esac
}

canonical_desktop_value_key() {
  key=$1
  reject_line_breaks "$key" "desktop preference key"
  case "$key" in
    selected_workspace_id|selected_conversation_id|theme_id|organize_mode|organize_sort|organize_show|workspace_order|conversation_order_by_workspace|voice_local_action_1_name|voice_local_action_1_command|voice_local_action_1_phrases|voice_local_action_2_name|voice_local_action_2_command|voice_local_action_2_phrases)
      printf '%s\n' "$key"
      ;;
    *)
      printf '%s\n' "artificer-native-backend: unsupported desktop value key" >&2
      exit 2
      ;;
  esac
}

bool_pref_value() {
  value=$1
  reject_line_breaks "$value" "desktop preference value"
  case "$value" in
    1|true|yes|on|enabled) printf '%s\n' 1 ;;
    0|false|no|off|disabled) printf '%s\n' 0 ;;
    *)
      printf '%s\n' "artificer-native-backend: desktop preference value must be boolean" >&2
      exit 2
      ;;
  esac
}

read_desktop_pref() {
  key=$(canonical_desktop_pref_key "$1")
  file=$(desktop_prefs_file)
  [ -f "$file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$file"
}

write_desktop_pref() {
  key=$(canonical_desktop_pref_key "$1")
  value=$(bool_pref_value "$2")
  mkdir -p "$(desktop_prefs_dir)"
  file=$(desktop_prefs_file)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-native-desktop-prefs.XXXXXX")
  if [ -f "$file" ]; then
    awk -F= -v wanted="$key" '$1 != wanted' "$file" > "$tmp_file"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  mv "$tmp_file" "$file"
}

write_desktop_value() {
  key=$(canonical_desktop_value_key "$1")
  value=$2
  reject_line_breaks "$value" "desktop preference value"
  mkdir -p "$(desktop_prefs_dir)"
  file=$(desktop_prefs_file)
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/artificer-native-desktop-prefs.XXXXXX")
  if [ -f "$file" ]; then
    awk -F= -v wanted="$key" '$1 != wanted' "$file" > "$tmp_file"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  mv "$tmp_file" "$file"
}

read_desktop_value() {
  key=$(canonical_desktop_value_key "$1")
  file=$(desktop_prefs_file)
  [ -f "$file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); found = 1 } END { exit found ? 0 : 1 }' "$file"
}

desktop_prefs_json() {
  background_mode=$(read_desktop_pref background_mode 2>/dev/null || printf '%s\n' 0)
  menu_bar_icon=$(read_desktop_pref menu_bar_icon 2>/dev/null || printf '%s\n' 0)
  voice_automations=$(read_desktop_pref voice_automations 2>/dev/null || printf '%s\n' 0)
  voice_automation_sound=$(read_desktop_pref voice_automation_sound 2>/dev/null || printf '%s\n' 0)
  voice_builtin_commands=$(read_desktop_pref voice_builtin_commands 2>/dev/null || printf '%s\n' 1)
  voice_dictation_commands=$(read_desktop_pref voice_dictation_commands 2>/dev/null || printf '%s\n' 1)
  voice_automation_llm_prompts=$(read_desktop_pref voice_automation_llm_prompts 2>/dev/null || printf '%s\n' 0)
  voice_automation_llm_actions=$(read_desktop_pref voice_automation_llm_actions 2>/dev/null || printf '%s\n' 0)
  voice_local_action_1_name=$(read_desktop_value voice_local_action_1_name 2>/dev/null || printf '')
  voice_local_action_1_command=$(read_desktop_value voice_local_action_1_command 2>/dev/null || printf '')
  voice_local_action_1_phrases=$(read_desktop_value voice_local_action_1_phrases 2>/dev/null || printf '')
  voice_local_action_2_name=$(read_desktop_value voice_local_action_2_name 2>/dev/null || printf '')
  voice_local_action_2_command=$(read_desktop_value voice_local_action_2_command 2>/dev/null || printf '')
  voice_local_action_2_phrases=$(read_desktop_value voice_local_action_2_phrases 2>/dev/null || printf '')
  theme_id=$(read_desktop_value theme_id 2>/dev/null || printf 'system')
  organize_mode=$(read_desktop_value organize_mode 2>/dev/null || printf 'project')
  organize_sort=$(read_desktop_value organize_sort 2>/dev/null || printf 'updated')
  organize_show=$(read_desktop_value organize_show 2>/dev/null || printf 'all')
  workspace_order=$(read_desktop_value workspace_order 2>/dev/null || printf '[]')
  conversation_order_by_workspace=$(read_desktop_value conversation_order_by_workspace 2>/dev/null || printf '{}')
  mobile_bridge=$(read_desktop_pref mobile_bridge 2>/dev/null || printf '%s\n' 0)
  mobile_tor=$(read_desktop_pref mobile_tor 2>/dev/null || printf '%s\n' 0)
  mobile_lan=$(read_desktop_pref mobile_lan 2>/dev/null || printf '%s\n' 0)
  mobile_allow_execute=$(read_desktop_pref mobile_allow_execute 2>/dev/null || printf '%s\n' 0)
  mobile_allow_self_actuation=$(read_desktop_pref mobile_allow_self_actuation 2>/dev/null || printf '%s\n' 0)
  background_mode=$(bool_pref_value "$background_mode" 2>/dev/null || printf '%s\n' 0)
  menu_bar_icon=$(bool_pref_value "$menu_bar_icon" 2>/dev/null || printf '%s\n' 0)
  voice_automations=$(bool_pref_value "$voice_automations" 2>/dev/null || printf '%s\n' 0)
  voice_automation_sound=$(bool_pref_value "$voice_automation_sound" 2>/dev/null || printf '%s\n' 0)
  voice_builtin_commands=$(bool_pref_value "$voice_builtin_commands" 2>/dev/null || printf '%s\n' 1)
  voice_dictation_commands=$(bool_pref_value "$voice_dictation_commands" 2>/dev/null || printf '%s\n' 1)
  voice_automation_llm_prompts=$(bool_pref_value "$voice_automation_llm_prompts" 2>/dev/null || printf '%s\n' 0)
  voice_automation_llm_actions=$(bool_pref_value "$voice_automation_llm_actions" 2>/dev/null || printf '%s\n' 0)
  case "$organize_mode" in project|chrono) ;; *) organize_mode=project ;; esac
  case "$organize_sort" in updated|created) ;; *) organize_sort=updated ;; esac
  case "$organize_show" in all|relevant|running) ;; *) organize_show=all ;; esac
  mobile_bridge=$(bool_pref_value "$mobile_bridge" 2>/dev/null || printf '%s\n' 0)
  mobile_tor=$(bool_pref_value "$mobile_tor" 2>/dev/null || printf '%s\n' 0)
  mobile_lan=$(bool_pref_value "$mobile_lan" 2>/dev/null || printf '%s\n' 0)
  mobile_allow_execute=$(bool_pref_value "$mobile_allow_execute" 2>/dev/null || printf '%s\n' 0)
  mobile_allow_self_actuation=$(bool_pref_value "$mobile_allow_self_actuation" 2>/dev/null || printf '%s\n' 0)
  printf '{"success":true,"background_mode":%s,"menu_bar_icon":%s,"voice_automations":%s,"voice_automation_sound":%s,"voice_builtin_commands":%s,"voice_dictation_commands":%s,"voice_automation_llm_prompts":%s,"voice_automation_llm_actions":%s,"voice_local_action_1_name":%s,"voice_local_action_1_command":%s,"voice_local_action_1_phrases":%s,"voice_local_action_2_name":%s,"voice_local_action_2_command":%s,"voice_local_action_2_phrases":%s,"theme_id":%s,"organize_mode":%s,"organize_sort":%s,"organize_show":%s,"workspace_order":%s,"conversation_order_by_workspace":%s,"mobile_bridge":%s,"mobile_tor":%s,"mobile_lan":%s,"mobile_allow_execute":%s,"mobile_allow_self_actuation":%s}\n' \
    "$([ "$background_mode" = 1 ] && printf true || printf false)" \
    "$([ "$menu_bar_icon" = 1 ] && printf true || printf false)" \
    "$([ "$voice_automations" = 1 ] && printf true || printf false)" \
    "$([ "$voice_automation_sound" = 1 ] && printf true || printf false)" \
    "$([ "$voice_builtin_commands" = 1 ] && printf true || printf false)" \
    "$([ "$voice_dictation_commands" = 1 ] && printf true || printf false)" \
    "$([ "$voice_automation_llm_prompts" = 1 ] && printf true || printf false)" \
    "$([ "$voice_automation_llm_actions" = 1 ] && printf true || printf false)" \
    "$(json_escape "$voice_local_action_1_name")" \
    "$(json_escape "$voice_local_action_1_command")" \
    "$(json_escape "$voice_local_action_1_phrases")" \
    "$(json_escape "$voice_local_action_2_name")" \
    "$(json_escape "$voice_local_action_2_command")" \
    "$(json_escape "$voice_local_action_2_phrases")" \
    "$(json_escape "$theme_id")" \
    "$(json_escape "$organize_mode")" \
    "$(json_escape "$organize_sort")" \
    "$(json_escape "$organize_show")" \
    "$(json_escape "$workspace_order")" \
    "$(json_escape "$conversation_order_by_workspace")" \
    "$([ "$mobile_bridge" = 1 ] && printf true || printf false)" \
    "$([ "$mobile_tor" = 1 ] && printf true || printf false)" \
    "$([ "$mobile_lan" = 1 ] && printf true || printf false)" \
    "$([ "$mobile_allow_execute" = 1 ] && printf true || printf false)" \
    "$([ "$mobile_allow_self_actuation" = 1 ] && printf true || printf false)"
}

candidate_core_roots() {
  if [ -n "${ARTIFICER_CORE_ROOT-}" ]; then
    printf '%s\n' "$ARTIFICER_CORE_ROOT"
  fi
  if value=$(read_pref core_root 2>/dev/null); then
    [ -n "$value" ] && printf '%s\n' "$value"
  fi
  printf '%s\n' "$project_dir/vendor/artificer"
  printf '%s\n' "$project_dir/../artificer"
  printf '%s\n' "$home/git/artificer-nonnative"
  printf '%s\n' "$home/.local/share/artificer/app"
  printf '%s\n' "$home/git/artificer"
}

resolve_core_root() {
  candidate_core_roots | while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    reject_line_breaks "$candidate" "core root"
    if [ -x "$candidate/hosted-web/scripts/artificer-runtime-client" ] && [ -x "$candidate/hosted-web/cgi/artificer-api" ]; then
      cd "$candidate" 2>/dev/null && pwd -P
      exit 0
    fi
  done
}

core_root=$(resolve_core_root 2>/dev/null || true)

require_core_root() {
  [ -n "$core_root" ] || {
    json_error "Artificer core runtime was not found. Set the core root in Preferences."
    exit 1
  }
}

runtime_client() {
  require_core_root
  "$core_root/hosted-web/scripts/artificer-runtime-client" "$@"
}

automations_script() {
  require_core_root
  sh "$core_root/scripts/artificer-automations.sh" "$@"
}

voice_automations_script() {
  sh "$script_dir/artificer-voice-automations.sh" "$@"
}

mobile_bridge_script() {
  sh "$script_dir/artificer-mobile-bridge.sh" "$@"
}

api_script() {
  require_core_root
  printf '%s\n' "$core_root/hosted-web/cgi/artificer-api"
}

url_encode_arg() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1] if len(sys.argv) > 1 else "", safe=""))
PY
}

strip_cgi_headers() {
  awk '
    BEGIN { body = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (body == 1) {
        print line
        next
      }
      if (line == "") {
        body = 1
      }
    }
  '
}

api_get() {
  action_name=$1
  shift
  query="action=$(url_encode_arg "$action_name")"
  while [ "$#" -gt 0 ]; do
    key=$1
    value=$2
    shift 2
    query="${query}&$(url_encode_arg "$key")=$(url_encode_arg "$value")"
  done
  voice_root=$(voice_recognition_root_dir)
  voice_hf_home="$voice_root/huggingface"
  VOICE_RECOGNITION_ROOT_DIR="$voice_root" WIZARDRY_VOICE_RECOGNITION_DIR="$voice_root" WIZARDRY_VOICE_RECOGNITION_HF_HOME="$voice_hf_home" REQUEST_METHOD=GET QUERY_STRING="$query" "$(api_script)" 2>&1 | strip_cgi_headers
}

api_post() {
  action_name=$1
  shift
  body="action=$(url_encode_arg "$action_name")"
  while [ "$#" -gt 0 ]; do
    key=$1
    value=$2
    shift 2
    body="${body}&$(url_encode_arg "$key")=$(url_encode_arg "$value")"
  done
  content_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
  voice_root=$(voice_recognition_root_dir)
  voice_hf_home="$voice_root/huggingface"
  printf '%s' "$body" | VOICE_RECOGNITION_ROOT_DIR="$voice_root" WIZARDRY_VOICE_RECOGNITION_DIR="$voice_root" WIZARDRY_VOICE_RECOGNITION_HF_HOME="$voice_hf_home" REQUEST_METHOD=POST CONTENT_TYPE='application/x-www-form-urlencoded' CONTENT_LENGTH="$content_length" "$(api_script)" 2>&1 | strip_cgi_headers
}

upload_attachment_file() {
  workspace_id=$1
  conversation_id=$2
  file_path=$3
  mime_value=${4-}
  reject_line_breaks "$workspace_id" "workspace id"
  reject_line_breaks "$conversation_id" "conversation id"
  reject_line_breaks "$file_path" "attachment path"
  reject_line_breaks "$mime_value" "attachment MIME type"
  [ -f "$file_path" ] || {
    json_error "Attachment file not found."
    exit 1
  }
  if [ -z "$mime_value" ]; then
    mime_value=$(file -b --mime-type "$file_path" 2>/dev/null || printf 'application/octet-stream')
  fi
  python3 - "$(api_script)" "$workspace_id" "$conversation_id" "$file_path" "$mime_value" <<'PY'
import base64
import json
import mimetypes
import os
import subprocess
import sys
import urllib.parse

api_script, workspace_id, conversation_id, file_path, mime_value = sys.argv[1:6]
try:
    size = os.path.getsize(file_path)
except OSError as exc:
    print(json.dumps({"success": False, "error": str(exc)}))
    raise SystemExit(1)
if size > 15 * 1024 * 1024:
    print(json.dumps({"success": False, "error": "attachment exceeds 15 MB limit"}))
    raise SystemExit(0)
name = os.path.basename(file_path)
if not mime_value or mime_value == "application/octet-stream":
    guessed, _ = mimetypes.guess_type(file_path)
    if guessed:
        mime_value = guessed
with open(file_path, "rb") as handle:
    encoded = base64.b64encode(handle.read()).decode("ascii")
body = urllib.parse.urlencode({
    "action": "upload_attachment",
    "workspace_id": workspace_id,
    "conversation_id": conversation_id,
    "name": name,
    "mime": mime_value,
    "data": encoded,
})
env = os.environ.copy()
env.update({
    "REQUEST_METHOD": "POST",
    "CONTENT_TYPE": "application/x-www-form-urlencoded",
    "CONTENT_LENGTH": str(len(body.encode("utf-8"))),
})
proc = subprocess.run([api_script], input=body, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, check=False)
payload = proc.stdout.replace("\r\n", "\n")
if "\n\n" in payload:
    payload = payload.split("\n\n", 1)[1]
print(payload.strip())
PY
}

daemon_fast_status_json() {
  require_core_root
  state_root=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$home/.local/state}/artificer}
  label="com.artificer.automations"
  method="none"
  enabled=false
  active=false
  paused=false
  detail=""
  os=$(uname -s 2>/dev/null || printf unknown)
  case "$os" in
    Darwin)
      method="launchd"
      detail="$home/Library/LaunchAgents/$label.plist"
      [ -f "$detail" ] && enabled=true
      if launchctl list 2>/dev/null | grep -F "$label" >/dev/null 2>&1; then
        active=true
      fi
      ;;
    Linux)
      if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files >/dev/null 2>&1; then
        method="systemd"
        detail="artificer-automations.timer"
        if systemctl --user is-enabled artificer-automations.timer >/dev/null 2>&1; then
          enabled=true
        fi
        if systemctl --user is-active artificer-automations.timer >/dev/null 2>&1; then
          active=true
        fi
      elif command -v crontab >/dev/null 2>&1; then
        method="cron"
        detail="crontab"
        if crontab -l 2>/dev/null | grep -F "ARTIFICER_AUTOMATIONS" >/dev/null 2>&1; then
          enabled=true
          active=true
        fi
      fi
      ;;
  esac
  [ -f "$state_root/automation-daemon.paused" ] && paused=true
  status="disabled"
  if [ "$enabled" = true ]; then
    status="idle"
    [ "$paused" = true ] && status="paused"
  fi
  printf '{"success":true,"supported":%s,"enabled":%s,"active":%s,"paused":%s,"method":%s,"status":%s,"label":%s,"detail":%s,"log_path":%s,"state_root":%s,"worker_busy":false,"worker_pid":"","worker_stale_lock":false,"last_tick_at":"0","last_tick_message":"","last_error":"","checked":"0","triggered":"0","errors":"0","attempted":"0","processed":"0","failures":"0","task_pending":"0","task_running":"0","task_total":"0","recent_tasks":[]}\n' \
    "$([ "$method" = none ] && printf false || printf true)" \
    "$enabled" \
    "$active" \
    "$paused" \
    "$(json_escape "$method")" \
    "$(json_escape "$status")" \
    "$(json_escape "$label")" \
    "$(json_escape "$detail")" \
    "$(json_escape "$state_root/automation-daemon.log")" \
    "$(json_escape "$state_root")"
}

open_url() {
  url=$1
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

case "$action" in
  doctor)
    core_json=$(json_escape "$core_root")
    project_json=$(json_escape "$project_dir")
    prefs_json=$(json_escape "$(prefs_file)")
    jq_status=false
    python_status=false
    ollama_status=false
    command -v jq >/dev/null 2>&1 && jq_status=true
    command -v python3 >/dev/null 2>&1 && python_status=true
    command -v ollama >/dev/null 2>&1 && ollama_status=true
    core_ready=false
    [ -n "$core_root" ] && core_ready=true
    printf '{"success":true,"project_dir":%s,"core_root":%s,"prefs_file":%s,"core_ready":%s,"jq_ready":%s,"python3_ready":%s,"ollama_cli_ready":%s}\n' \
      "$project_json" "$core_json" "$prefs_json" "$core_ready" "$jq_status" "$python_status" "$ollama_status"
    ;;
  prefs-get)
    value=""
    if value=$(read_pref core_root 2>/dev/null); then :; fi
    printf '{"success":true,"core_root":%s,"resolved_core_root":%s,"prefs_file":%s}\n' \
      "$(json_escape "$value")" "$(json_escape "$core_root")" "$(json_escape "$(prefs_file)")"
    ;;
  prefs-set-core-root)
    value=${1-}
    reject_line_breaks "$value" "core root"
    [ -n "$value" ] || {
      printf '%s\n' "artificer-native-backend: core root is required" >&2
      exit 2
    }
    [ -d "$value" ] || {
      printf '%s\n' "artificer-native-backend: core root directory not found" >&2
      exit 1
    }
    abs_value=$(cd "$value" && pwd -P)
    [ -x "$abs_value/hosted-web/scripts/artificer-runtime-client" ] || {
      printf '%s\n' "artificer-native-backend: missing hosted-web/scripts/artificer-runtime-client" >&2
      exit 1
    }
    write_pref core_root "$abs_value"
    printf '{"success":true,"core_root":%s}\n' "$(json_escape "$abs_value")"
    ;;
  desktop-prefs-get)
    desktop_prefs_json
    ;;
  desktop-prefs-set)
    key=${1-}
    enabled_value=${2-0}
    write_desktop_pref "$key" "$enabled_value"
    if [ "$key" = "voice_automations" ]; then
      # Voice automation capture must run from the native app process so macOS
      # microphone permission applies to Artificer, not to a launchd shell.
      normalized_enabled=$(bool_pref_value "$enabled_value")
      if [ "$normalized_enabled" = 1 ]; then
        voice_automations_script app-hosted >/dev/null
      else
        voice_automations_script disable >/dev/null
      fi
    elif [ "$key" = "mobile_bridge" ]; then
      normalized_enabled=$(bool_pref_value "$enabled_value")
      if [ "$normalized_enabled" = 1 ]; then
        mobile_bridge_script enable >/dev/null
      else
        mobile_bridge_script disable >/dev/null
      fi
    elif [ "$key" = "mobile_tor" ]; then
      normalized_enabled=$(bool_pref_value "$enabled_value")
      mobile_bridge_script set tor_enabled "$normalized_enabled" >/dev/null
      if [ "$normalized_enabled" = 1 ]; then
        mobile_bridge_script restart >/dev/null
      fi
    elif [ "$key" = "mobile_lan" ]; then
      normalized_enabled=$(bool_pref_value "$enabled_value")
      if [ "$normalized_enabled" = 1 ]; then
        mobile_bridge_script set bind_host 0.0.0.0 >/dev/null
      else
        mobile_bridge_script set bind_host 127.0.0.1 >/dev/null
      fi
      if [ "$(read_desktop_pref mobile_bridge 2>/dev/null || printf 0)" = 1 ]; then
        mobile_bridge_script restart >/dev/null
      fi
    elif [ "$key" = "mobile_allow_execute" ]; then
      normalized_enabled=$(bool_pref_value "$enabled_value")
      mobile_bridge_script set allow_execute "$normalized_enabled" >/dev/null
      if [ "$(read_desktop_pref mobile_bridge 2>/dev/null || printf 0)" = 1 ]; then
        mobile_bridge_script restart >/dev/null
      fi
    elif [ "$key" = "mobile_allow_self_actuation" ]; then
      normalized_enabled=$(bool_pref_value "$enabled_value")
      mobile_bridge_script set allow_self_actuation "$normalized_enabled" >/dev/null
      if [ "$(read_desktop_pref mobile_bridge 2>/dev/null || printf 0)" = 1 ]; then
        mobile_bridge_script restart >/dev/null
      fi
    fi
    desktop_prefs_json
    ;;
  desktop-value-set)
    key=${1-}
    value=${2-}
    write_desktop_value "$key" "$value"
    desktop_prefs_json
    ;;
  desktop-selection-set)
    workspace_id=${1-}
    conversation_id=${2-}
    reject_line_breaks "$workspace_id" "workspace id"
    reject_line_breaks "$conversation_id" "conversation id"
    write_desktop_value selected_workspace_id "$workspace_id"
    write_desktop_value selected_conversation_id "$conversation_id"
    printf '{"success":true}\n'
    ;;
  voice-automations-status)
    voice_automations_script status
    ;;
  voice-automations-tick)
    voice_automations_script tick
    ;;
  voice-automations-handle-text)
    text=${1-}
    voice_automations_script handle-text "$text"
    ;;
  mobile-status)
    mobile_bridge_script status
    ;;
  mobile-enable)
    write_desktop_pref mobile_bridge 1
    mobile_bridge_script enable
    ;;
  mobile-disable)
    write_desktop_pref mobile_bridge 0
    mobile_bridge_script disable
    ;;
  mobile-restart)
    mobile_bridge_script restart
    ;;
  mobile-install-tor)
    mobile_bridge_script install-tor
    ;;
  mobile-set)
    key=${1-}
    value=${2-}
    mobile_bridge_script set "$key" "$value"
    ;;
  health)
    runtime_client health
    ;;
  projects)
    runtime_client project list
    ;;
  project-add)
    path_value=${1-}
    name_value=${2-}
    command_exec_mode=${3:-ask-some}
    reject_line_breaks "$path_value" "workspace path"
    reject_line_breaks "$name_value" "workspace name"
    runtime_client project add --path "$path_value" --name "$name_value" --command-exec-mode "$command_exec_mode"
    ;;
  project-rename)
    workspace_id=${1-}
    name_value=${2-}
    reject_line_breaks "$workspace_id" "workspace id"
    reject_line_breaks "$name_value" "workspace name"
    runtime_client project rename --workspace-id "$workspace_id" --name "$name_value"
    ;;
  project-delete)
    workspace_id=${1-}
    reject_line_breaks "$workspace_id" "workspace id"
    runtime_client project delete --workspace-id "$workspace_id"
    ;;
  sessions)
    workspace_id=${1-}
    runtime_client session list --workspace-id "$workspace_id"
    ;;
  session)
    workspace_id=${1-}
    conversation_id=${2-}
    runtime_client session get --workspace-id "$workspace_id" --conversation-id "$conversation_id"
    ;;
  session-create)
    workspace_id=${1-}
    title=${2:-New session}
    model=${3-}
    reject_line_breaks "$title" "session title"
    runtime_client session create --workspace-id "$workspace_id" --title "$title" --model "$model"
    ;;
  session-archive)
    workspace_id=${1-}
    conversation_id=${2-}
    runtime_client session archive --workspace-id "$workspace_id" --conversation-id "$conversation_id"
    ;;
  session-set-model)
    workspace_id=${1-}
    conversation_id=${2-}
    model_name=${3-}
    reject_line_breaks "$workspace_id" "workspace id"
    reject_line_breaks "$conversation_id" "conversation id"
    reject_line_breaks "$model_name" "model"
    api_post set_model workspace_id "$workspace_id" conversation_id "$conversation_id" model "$model_name"
    ;;
  session-message)
    workspace_id=${1-}
    conversation_id=${2-}
    prompt=${3-}
    run_mode=${4:-auto}
    compute_budget=${5:-auto}
    command_exec_mode=${6:-ask-some}
    permission_mode=${7:-default}
    programmer_review=${8:-1}
    programmer_review_rounds=${9:-2}
    reflexive_knowledge=${10:-0}
    self_actuation=${11:-0}
    attachments=${12:-}
    reasoning_effort=${13:-}
    runtime_client session message \
      --workspace-id "$workspace_id" \
      --conversation-id "$conversation_id" \
      --prompt "$prompt" \
      --attachments "$attachments" \
      --run-mode "$run_mode" \
      --compute-budget "$compute_budget" \
      --reasoning-effort "$reasoning_effort" \
      --command-exec-mode "$command_exec_mode" \
      --permission-mode "$permission_mode" \
      --programmer-review "$programmer_review" \
      --programmer-review-rounds "$programmer_review_rounds" \
      --reflexive-knowledge "$reflexive_knowledge" \
      --self-actuation "$self_actuation"
    ;;
  draft-get)
    workspace_id=${1-}
    reject_line_breaks "$workspace_id" "workspace id"
    api_get get_draft workspace_id "$workspace_id"
    ;;
  draft-save)
    workspace_id=${1-}
    draft_text=${2-}
    reject_line_breaks "$workspace_id" "workspace id"
    api_post save_draft workspace_id "$workspace_id" draft "$draft_text"
    ;;
  conversation-draft-save)
    workspace_id=${1-}
    conversation_id=${2-}
    draft_text=${3-}
    reject_line_breaks "$workspace_id" "workspace id"
    reject_line_breaks "$conversation_id" "conversation id"
    api_post save_conversation_draft workspace_id "$workspace_id" conversation_id "$conversation_id" draft "$draft_text"
    ;;
  attachment-upload)
    workspace_id=${1-}
    conversation_id=${2-}
    file_path=${3-}
    mime_value=${4-}
    upload_attachment_file "$workspace_id" "$conversation_id" "$file_path" "$mime_value"
    ;;
  session-run-next)
    workspace_id=${1-}
    conversation_id=${2-}
    runtime_client session run-next --workspace-id "$workspace_id" --conversation-id "$conversation_id"
    ;;
  session-events)
    workspace_id=${1-}
    conversation_id=${2-}
    stream_session=${3-}
    offset=${4:-0}
    runtime_client session events --workspace-id "$workspace_id" --conversation-id "$conversation_id" --stream-session "$stream_session" --offset "$offset"
    ;;
  git-status)
    workspace_id=${1-}
    api_get git_status workspace_id "$workspace_id"
    ;;
  git-diff)
    workspace_id=${1-}
    api_get git_diff workspace_id "$workspace_id"
    ;;
  git-branches)
    workspace_id=${1-}
    api_get git_branches workspace_id "$workspace_id"
    ;;
  git-checkout-branch)
    workspace_id=${1-}
    branch_name=${2-}
    create_branch=${3:-0}
    reject_line_breaks "$branch_name" "branch"
    api_post git_checkout_branch workspace_id "$workspace_id" branch "$branch_name" create "$create_branch"
    ;;
  git-commit)
    workspace_id=${1-}
    include_unstaged=${2:-1}
    message=${3-}
    push_after=${4:-0}
    api_post git_commit workspace_id "$workspace_id" include_unstaged "$include_unstaged" message "$message" push "$push_after"
    ;;
  git-push)
    workspace_id=${1-}
    api_post git_push workspace_id "$workspace_id"
    ;;
  open-project-target)
    workspace_id=${1-}
    target=${2:-finder}
    reject_line_breaks "$target" "open target"
    api_post open_in workspace_id "$workspace_id" target "$target"
    ;;
  queue-list)
    workspace_id=${1-}
    conversation_id=${2-}
    limit_value=${3:-20}
    api_get queue_list workspace_id "$workspace_id" conversation_id "$conversation_id" limit "$limit_value"
    ;;
  queue-update)
    workspace_id=${1-}
    conversation_id=${2-}
    item_id=${3-}
    prompt_text=${4-}
    api_post queue_update workspace_id "$workspace_id" conversation_id "$conversation_id" item_id "$item_id" prompt "$prompt_text"
    ;;
  queue-reorder)
    workspace_id=${1-}
    conversation_id=${2-}
    item_ids=${3-}
    reject_line_breaks "$item_ids" "queue item ids"
    api_post queue_reorder workspace_id "$workspace_id" conversation_id "$conversation_id" item_ids "$item_ids"
    ;;
  queue-cancel)
    workspace_id=${1-}
    conversation_id=${2-}
    item_id=${3-}
    api_post queue_cancel workspace_id "$workspace_id" conversation_id "$conversation_id" item_id "$item_id"
    ;;
  queue-stop)
    workspace_id=${1-}
    conversation_id=${2-}
    api_post queue_stop workspace_id "$workspace_id" conversation_id "$conversation_id"
    ;;
  approval-answer)
    workspace_id=${1-}
    conversation_id=${2-}
    decision=${3:-deny}
    scope_value=${4:-once}
    match_mode=${5:-exact}
    pattern_value=${6-}
    command_value=${7-}
    api_post approval_answer workspace_id "$workspace_id" conversation_id "$conversation_id" decision "$decision" scope "$scope_value" match_mode "$match_mode" pattern "$pattern_value" command "$command_value"
    ;;
  command-rules-list)
    workspace_id=${1-}
    api_get command_rules_list workspace_id "$workspace_id"
    ;;
  command-rules-clear)
    workspace_id=${1-}
    scope_value=${2:-remember}
    api_post command_rules_clear workspace_id "$workspace_id" scope "$scope_value"
    ;;
  command-rule-delete)
    workspace_id=${1-}
    scope_value=${2:-remember}
    index_value=${3-}
    api_post command_rule_delete workspace_id "$workspace_id" scope "$scope_value" index "$index_value"
    ;;
  decision-answer)
    workspace_id=${1-}
    conversation_id=${2-}
    answer=${3-}
    api_post decision_answer workspace_id "$workspace_id" conversation_id "$conversation_id" answer "$answer"
    ;;
  terminal-session-start)
    workspace_id=${1-}
    api_post terminal_session_start workspace_id "$workspace_id"
    ;;
  terminal-session-poll)
    workspace_id=${1-}
    session_id=${2-}
    offset=${3:-0}
    api_get terminal_session_poll workspace_id "$workspace_id" session_id "$session_id" offset "$offset"
    ;;
  terminal-session-input)
    workspace_id=${1-}
    session_id=${2-}
    input_text=${3-}
    api_post terminal_session_input workspace_id "$workspace_id" session_id "$session_id" input "$input_text"
    ;;
  terminal-session-stop)
    workspace_id=${1-}
    session_id=${2-}
    api_post terminal_session_stop workspace_id "$workspace_id" session_id "$session_id"
    ;;
  dictation-status)
    api_get dictation_status
    ;;
  dictation-language-get)
    api_get dictation_language_get
    ;;
  dictation-language-set)
    language=${1:-auto}
    api_post dictation_language_set language "$language"
    ;;
  dictation-prewarm-get)
    api_get dictation_prewarm_get
    ;;
  dictation-prewarm-set)
    enabled_value=${1:-0}
    api_post dictation_prewarm_set enabled "$enabled_value"
    ;;
  dictation-shortcuts-get)
    api_get dictation_shortcuts_get
    ;;
  dictation-shortcuts-set)
    hold_value=${1:-none}
    toggle_value=${2:-none}
    api_post dictation_shortcuts_set hold "$hold_value" toggle "$toggle_value"
    ;;
  dictation-install-start)
    api_post dictation_install_start
    ;;
  dictation-install-status)
    job_id=${1-}
    api_get dictation_install_status job_id "$job_id"
    ;;
  dictation-install-cancel)
    job_id=${1-}
    api_post dictation_install_cancel job_id "$job_id"
    ;;
  dictation-start)
    language=${1:-auto}
    now_ms=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000' 2>/dev/null || date +%s000)
    api_post dictate_start language "$language" requested_started_ms "$now_ms"
    ;;
  dictation-levels)
    session_id=${1-}
    api_get dictate_levels session_id "$session_id"
    ;;
  dictation-stop)
    session_id=${1-}
    api_post dictate_stop session_id "$session_id"
    ;;
  dictation-transcribe-file)
    audio_path=${1-}
    language=${2:-auto}
    api_post dictate_transcribe_file audio_path "$audio_path" language "$language"
    ;;
  self-improve-settings)
    api_get self_improve_settings_get
    ;;
  self-improve-codex-work-check-set)
    enabled_value=${1:-0}
    case "$enabled_value" in
      1|true|yes|on|enabled) enabled_value=1 ;;
      *) enabled_value=0 ;;
    esac
    api_post self_improve_run_options_set codex_work_check_enabled "$enabled_value"
    ;;
  self-improve-run-options-set)
    objective=${1-}
    competition_enabled=${2:-1}
    challenger_model=${3-}
    codex_work_check_enabled=${4:-0}
    source_papers=${5:-1}
    source_web=${6:-1}
    source_runtime=${7:-1}
    source_repo=${8:-1}
    source_platform=${9:-1}
    api_post self_improve_run_options_set \
      objective "$objective" \
      competition_enabled "$competition_enabled" \
      challenger_model "$challenger_model" \
      codex_work_check_enabled "$codex_work_check_enabled" \
      source_papers "$source_papers" \
      source_web "$source_web" \
      source_runtime "$source_runtime" \
      source_repo "$source_repo" \
      source_platform "$source_platform"
    ;;
  self-improve-run)
    model_name=${1-}
    objective=${2-}
    competition_enabled=${3:-1}
    challenger_model=${4-}
    codex_work_check_enabled=${5:-0}
    source_papers=${6:-1}
    source_web=${7:-1}
    source_runtime=${8:-1}
    source_repo=${9:-1}
    source_platform=${10:-1}
    api_post self_improve_run \
      model "$model_name" \
      objective "$objective" \
      competition_enabled "$competition_enabled" \
      challenger_model "$challenger_model" \
      codex_work_check_enabled "$codex_work_check_enabled" \
      source_papers "$source_papers" \
      source_web "$source_web" \
      source_runtime "$source_runtime" \
      source_repo "$source_repo" \
      source_platform "$source_platform"
    ;;
  automations)
    runtime_client automation list
    ;;
  automation-upsert)
    workspace_id=${1-}
    conversation_id=${2-}
    name=${3-}
    prompt=${4-}
    schedule_kind=${5-}
    schedule_value=${6-}
    enabled=${7-1}
    allow_self_reschedule=${8-0}
    run_mode=${9:-assistant}
    compute_budget=${10:-auto}
    command_exec_mode=${11:-ask-some}
    permission_mode=${12:-default}
    programmer_review=${13:-1}
    programmer_review_rounds=${14:-2}
    next_run=${15:-}
    automation_id=${16:-}
    if [ -n "$automation_id" ]; then
      runtime_client automation upsert \
        --automation-id "$automation_id" \
        --workspace-id "$workspace_id" \
        --conversation-id "$conversation_id" \
        --name "$name" \
        --prompt "$prompt" \
        --schedule-kind "$schedule_kind" \
        --schedule-value "$schedule_value" \
        --enabled "$enabled" \
        --allow-self-reschedule "$allow_self_reschedule" \
        --run-mode "$run_mode" \
        --compute-budget "$compute_budget" \
        --command-exec-mode "$command_exec_mode" \
        --permission-mode "$permission_mode" \
        --programmer-review "$programmer_review" \
        --programmer-review-rounds "$programmer_review_rounds" \
        --next-run "$next_run"
      exit $?
    fi
    runtime_client automation upsert \
      --workspace-id "$workspace_id" \
      --conversation-id "$conversation_id" \
      --name "$name" \
      --prompt "$prompt" \
      --schedule-kind "$schedule_kind" \
      --schedule-value "$schedule_value" \
      --enabled "$enabled" \
      --allow-self-reschedule "$allow_self_reschedule" \
      --run-mode "$run_mode" \
      --compute-budget "$compute_budget" \
      --command-exec-mode "$command_exec_mode" \
      --permission-mode "$permission_mode" \
      --programmer-review "$programmer_review" \
      --programmer-review-rounds "$programmer_review_rounds" \
      --next-run "$next_run"
    ;;
  automation-run)
    automation_id=${1-}
    runtime_client automation run-now --automation-id "$automation_id"
    ;;
  automation-toggle)
    automation_id=${1-}
    enabled=${2-}
    runtime_client automation toggle --automation-id "$automation_id" --enabled "$enabled"
    ;;
  automation-delete)
    automation_id=${1-}
    runtime_client automation delete --automation-id "$automation_id"
    ;;
  automation-daemon-status)
    daemon_fast_status_json
    ;;
  automation-daemon-enable)
    automations_script enable >/dev/null
    daemon_fast_status_json
    ;;
  automation-daemon-pause)
    automations_script pause >/dev/null
    daemon_fast_status_json
    ;;
  automation-daemon-resume)
    automations_script resume >/dev/null
    daemon_fast_status_json
    ;;
  automation-daemon-disable)
    automations_script disable >/dev/null
    daemon_fast_status_json
    ;;
  automation-daemon-tick)
    automations_script tick >/dev/null
    daemon_fast_status_json
    ;;
  models)
    api_get models
    ;;
  model-catalog)
    api_get model_catalog
    ;;
  model-install-start)
    model_name=${1-}
    api_post model_install_start model "$model_name"
    ;;
  model-install-status)
    job_id=${1-}
    api_get model_install_status job_id "$job_id"
    ;;
  model-uninstall)
    model_name=${1-}
    api_post model_uninstall model "$model_name"
    ;;
  llm-runtime-settings-get)
    api_get llm_runtime_settings_get
    ;;
  llm-runtime-settings-set)
    use_gpu=${1-}
    default_model=${2-}
    smart_titles=${3-}
    api_post llm_runtime_settings_set use_gpu "$use_gpu" default_model "$default_model" smart_titles "$smart_titles"
    ;;
  git-runtime-settings-get)
    api_get git_runtime_settings_get
    ;;
  git-runtime-settings-set)
    workflow_policy=${1-}
    ambiguity_policy=${2-}
    api_post git_runtime_settings_set workflow_policy "$workflow_policy" ambiguity_policy "$ambiguity_policy"
    ;;
  open-web)
    require_core_root
    url=$(sh "$core_root/run-artificer" url)
    open_url "$url" || true
    printf '{"success":true,"url":%s}\n' "$(json_escape "$url")"
    ;;
  *)
    printf '%s\n' "artificer-native-backend: unsupported action: $action" >&2
    exit 2
    ;;
esac
