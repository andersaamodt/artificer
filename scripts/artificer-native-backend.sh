#!/bin/sh

case "${1-}" in
--help|--usage|-h)
  cat <<'USAGE'
Usage: artificer-native-backend.sh ACTION [ARGS...]

Actions:
  doctor
  prefs-get
  prefs-set-core-root CORE_ROOT
  health
  projects
  project-add PATH NAME [COMMAND_EXEC_MODE]
  sessions WORKSPACE_ID
  session WORKSPACE_ID CONVERSATION_ID
  session-create WORKSPACE_ID TITLE [MODEL]
  session-message WORKSPACE_ID CONVERSATION_ID PROMPT RUN_MODE COMPUTE_BUDGET COMMAND_EXEC_MODE PERMISSION_MODE PROGRAMMER_REVIEW PROGRAMMER_REVIEW_ROUNDS REFLEXIVE_KNOWLEDGE SELF_ACTUATION
  session-run-next WORKSPACE_ID CONVERSATION_ID
  session-events WORKSPACE_ID CONVERSATION_ID [STREAM_SESSION] [OFFSET]
  automations
  automation-run AUTOMATION_ID
  automation-toggle AUTOMATION_ID ENABLED
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

candidate_core_roots() {
  if [ -n "${ARTIFICER_CORE_ROOT-}" ]; then
    printf '%s\n' "$ARTIFICER_CORE_ROOT"
  fi
  if value=$(read_pref core_root 2>/dev/null); then
    [ -n "$value" ] && printf '%s\n' "$value"
  fi
  printf '%s\n' "$project_dir/vendor/artificer"
  printf '%s\n' "$project_dir/../artificer"
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
    json_error "Artificer core runtime was not found. Set the core root in Settings."
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
    runtime_client session message \
      --workspace-id "$workspace_id" \
      --conversation-id "$conversation_id" \
      --prompt "$prompt" \
      --run-mode "$run_mode" \
      --compute-budget "$compute_budget" \
      --command-exec-mode "$command_exec_mode" \
      --permission-mode "$permission_mode" \
      --programmer-review "$programmer_review" \
      --programmer-review-rounds "$programmer_review_rounds" \
      --reflexive-knowledge "$reflexive_knowledge" \
      --self-actuation "$self_actuation"
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
  automations)
    runtime_client automation list
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
