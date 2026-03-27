#!/bin/sh
set -eu

WIZARDRY_DIR=${WIZARDRY_DIR:-$HOME/.wizardry}
PATH="$WIZARDRY_DIR/spells/.imps/cgi:$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin"
ARTIFICER_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

http-ok-json

request_method=${REQUEST_METHOD:-GET}
query_data=${QUERY_STRING:-}
post_data=""

if [ "$request_method" = "POST" ]; then
  content_length=${CONTENT_LENGTH:-}
  case "$content_length" in
    ""|*[!0-9]*)
      content_length=0
      ;;
  esac
  if [ "$content_length" -gt 0 ]; then
    post_data=$(dd bs=1 count="$content_length" 2>/dev/null || cat)
  else
    post_data=$(cat)
  fi
fi

data_root=$(get-site-data-dir "artificer")
workspaces_dir="$data_root/workspaces"
git_settings_dir="$data_root/git"
selected_ssh_pub_file="$git_settings_dir/selected_ssh_pub"
model_installs_dir="$data_root/model-installs"
dictation_installs_dir="$data_root/dictation-installs"
dictation_live_dir="$data_root/dictation-live"
command_policy_root="$data_root/command-policy"
terminal_sessions_root="$data_root/terminal-sessions"
mode_runtime_root="$data_root/mode-runtime"
automations_root="$data_root/automations"
automations_runtime_root="$data_root/automations-runtime"
llm_settings_dir="$data_root/llm-settings"
llm_use_gpu_file="$llm_settings_dir/use-gpu"
self_improve_plugins_dir="$llm_settings_dir/self-improve-plugins"
self_improve_model_file="$llm_settings_dir/self-improve-model"
self_improve_last_run_file="$llm_settings_dir/self-improve-last-run.json"
self_improve_run_options_file="$llm_settings_dir/self-improve-run-options.json"
dictation_settings_dir="$data_root/dictation-settings"
dictation_shortcut_hold_file="$dictation_settings_dir/shortcut-hold"
dictation_shortcut_toggle_file="$dictation_settings_dir/shortcut-toggle"
dictation_prewarm_enabled_file="$dictation_settings_dir/prewarm-enabled"
dictation_language_file="$dictation_settings_dir/language"
ui_state_dir="$data_root/ui-state"
state_light_cache_file="$data_root/state-light-cache.json"
state_light_cache_revision_file="$data_root/state-light-cache.revision"
state_revision_file="$data_root/state.revision"
ALLOW_NETWORK=0
ALLOW_WEB=0
ARTIFICER_STATE_ROOT=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/artificer}
ARTIFICER_ASSAY_REPORTS_DIR=${ARTIFICER_ASSAY_REPORTS_DIR:-$ARTIFICER_STATE_ROOT/assay-reports}
ARTIFICER_ASSAY_RUNS_DIR=${ARTIFICER_ASSAY_RUNS_DIR:-$ARTIFICER_STATE_ROOT/assay-runs}

mkdir -p "$workspaces_dir"
mkdir -p "$model_installs_dir"
mkdir -p "$dictation_installs_dir"
mkdir -p "$dictation_live_dir"
mkdir -p "$command_policy_root"
mkdir -p "$terminal_sessions_root"
mkdir -p "$mode_runtime_root"
mkdir -p "$automations_root"
mkdir -p "$automations_runtime_root"
mkdir -p "$llm_settings_dir"
mkdir -p "$self_improve_plugins_dir"
mkdir -p "$dictation_settings_dir"
mkdir -p "$ui_state_dir"
mkdir -p "$ARTIFICER_ASSAY_REPORTS_DIR"
mkdir -p "$ARTIFICER_ASSAY_RUNS_DIR"

DICTATION_MAX_RECORDING_SECONDS=${DICTATION_MAX_RECORDING_SECONDS:-600}
case "$DICTATION_MAX_RECORDING_SECONDS" in
  ""|*[!0-9]*)
    DICTATION_MAX_RECORDING_SECONDS=600
    ;;
esac

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN {
      ORS = ""
      first = 1
    }
    {
      gsub(/\033\[[0-9;?]*[A-Za-z]/, "")
      gsub(/\033/, "")
      gsub(/[\001-\010\013\014\016-\037]/, "")
      if (!first) {
        printf "\\n"
      }
      first = 0
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      printf "%s", $0
    }
  '
}

emit_error() {
  message=$(json_escape "$1")
  printf '{"success":false,"error":"%s"}\n' "$message"
}

emit_ok_message() {
  message=$(json_escape "$1")
  printf '{"success":true,"message":"%s"}\n' "$message"
}

strip_model_install_progress_noise() {
  if [ "$#" -gt 0 ]; then
    input_text=$1
  else
    input_text=$(cat)
  fi
  if ! printf '%s\n' "$input_text" | grep -Eiq 'pulling manifest|verifying sha256 digest|writing manifest|^[[:space:]]*pulling [0-9a-f]{12,}:'; then
    printf '%s' "$input_text"
    return 0
  fi

  printf '%s\n' "$input_text" | awk '
    BEGIN {
      saw_install_noise = 0
    }
    {
      line = $0
      lower = tolower(line)
      if (lower ~ /^[[:space:]]*pulling manifest([[:space:]]+pulling manifest)*[[:space:]]*$/) {
        saw_install_noise = 1
        next
      }
      if (lower ~ /^[[:space:]]*pulling [0-9a-f]{12,}:[[:space:]]*[0-9]{1,3}%/) {
        saw_install_noise = 1
        next
      }
      if (lower ~ /^[[:space:]]*(verifying sha256 digest|writing manifest)[[:space:]]*$/) {
        saw_install_noise = 1
        next
      }
      if (saw_install_noise == 1 && lower ~ /^[[:space:]]*success[[:space:]]*$/) {
        next
      }
      print line
    }
  ' | sed '/^[[:space:]]*$/d'
}

strip_terminal_noise() {
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CS -pe '
      s/\e\[[0-9;?]*[ -\/]*[@-~]//g;                 # ANSI CSI sequences
      s/\e\][^\a]*(?:\a|\e\\)//g;                    # OSC sequences
      s/\eP(?:.|\n)*?\e\\//g;                        # DCS sequences
      s/\r//g;                                       # carriage returns from spinners
      s/[\x{2800}-\x{28FF}]//g;                      # braille spinner glyphs
      s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;             # control chars except tab/newline
    ' | sed '/^[[:space:]]*$/d' | strip_model_install_progress_noise
    return 0
  fi

  esc=$(printf '\033')
  printf '%s' "$1" \
    | tr '\r' '\n' \
    | sed "s/${esc}\\[[0-9;?]*[ -\\/]*[@-~]//g" \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed '/^[[:space:]]*$/d' \
    | strip_model_install_progress_noise
}

canonicalize_controller_output() {
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CS -0777 -pe '
      s/\r/\n/g;
      s/\e\[[0-9;?]*[ -\/]*[@-~]//g;                 # ANSI CSI sequences
      s/\e\][^\a]*(?:\a|\e\\)//g;                    # OSC sequences
      s/\eP(?:.|\n)*?\e\\//g;                        # DCS sequences
      s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;             # control chars except tab/newline
      s/[\x{2800}-\x{28FF}]//g;                      # braille spinner glyphs

      # Some local models collapse section headers into a single line.
      s/\s*(MODE_UPDATE|COMMANDS|CONTRACT|PATCH|DONE_CLAIM|PLAN_UPDATE|CHECKPOINT|DECISION_REQUEST|FINAL):\s*/\n$1:\n/g;
      s/\n{3,}/\n\n/g;

      # Recover key/value lines that were flattened.
      s/(target=[^\n]*?)\s+(blocking=)/$1\n$2/g;
      s/(blocking=[^\n]*?)\s+(confidence=)/$1\n$2/g;
      s/([^\n])\.blocking=/$1\nblocking=/g;
      s/([^\n])\.confidence=/$1\nconfidence=/g;
      s/(question=[^\n]*?)\s+(option=)/$1\n$2/g;
      s/\s+(option=)/\n$1/g;

      s/[ \t]+\n/\n/g;
      s/\n[ \t]+/\n/g;
      s/^\s+//;
      s/\s+$//;
    ' | sed '/^[[:space:]]*$/d'
    return 0
  fi

  esc=$(printf '\033')
  printf '%s' "$1" \
    | tr '\r' '\n' \
    | sed "s/${esc}\\[[0-9;?]*[ -\\/]*[@-~]//g" \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed \
        -e 's/[[:space:]]*\(MODE_UPDATE\|COMMANDS\|CONTRACT\|PATCH\|DONE_CLAIM\|PLAN_UPDATE\|CHECKPOINT\|DECISION_REQUEST\|FINAL\):[[:space:]]*/\
\1:\
/g' \
        -e 's/\(target=[^\n]*\)[[:space:]]\{1,\}\(blocking=\)/\1\
\2/g' \
        -e 's/\(blocking=[^\n]*\)[[:space:]]\{1,\}\(confidence=\)/\1\
\2/g' \
        -e 's/\(question=[^\n]*\)[[:space:]]\{1,\}\(option=\)/\1\
\2/g' \
        -e 's/[[:space:]]\{1,\}\(option=\)/\
\1/g' \
        -e 's/[[:space:]][[:space:]]*$//' \
    | awk '
        NF == 0 {
          if (blank == 1) {
            next
          }
          blank = 1
          print ""
          next
        }
        {
          blank = 0
          print
        }
      '
}

pick_workspace_path_macos() {
  if ! command -v osascript >/dev/null 2>&1; then
    return 1
  fi

  osascript <<'EOF'
try
  set chosenFolder to POSIX path of (choose folder with prompt "Select workspace folder")
  return chosenFolder
on error number -128
  return ""
end try
EOF
}

pick_ssh_pub_path_macos() {
  if ! command -v osascript >/dev/null 2>&1; then
    return 1
  fi

  osascript <<'EOF'
try
  set homeDir to POSIX path of (path to home folder)
  set sshDir to POSIX file (homeDir & ".ssh/")
  set chosenFile to POSIX path of (choose file with prompt "Select SSH public key (.pub)" default location sshDir)
  return chosenFile
on error number -128
  return ""
on error
  try
    set chosenFile to POSIX path of (choose file with prompt "Select SSH public key (.pub)")
    return chosenFile
  on error number -128
    return ""
  end try
end try
EOF
}

selected_ssh_pub_path() {
  read_file_line "$selected_ssh_pub_file" ""
}

set_selected_ssh_pub_path() {
  selected_path=$1
  mkdir -p "$git_settings_dir"
  printf '%s\n' "$selected_path" > "$selected_ssh_pub_file"
}

clear_selected_ssh_pub_path() {
  rm -f "$selected_ssh_pub_file"
}

llm_use_gpu_enabled() {
  raw_value=$(trim "$(read_file_line "$llm_use_gpu_file" "1")")
  case "$raw_value" in
    0|false|FALSE|False|no|NO|No|off|OFF|Off)
      printf '%s' "0"
      ;;
    *)
      printf '%s' "1"
      ;;
  esac
}

set_llm_use_gpu_enabled() {
  next_value=$1
  mkdir -p "$llm_settings_dir"
  case "$next_value" in
    1)
      printf '%s\n' "1" > "$llm_use_gpu_file"
      ;;
    *)
      printf '%s\n' "0" > "$llm_use_gpu_file"
      ;;
  esac
}
