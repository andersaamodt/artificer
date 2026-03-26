workspace_draft_file_for() {
  workspace_id=$1
  printf '%s/%s/draft-first-message.txt' "$workspaces_dir" "$workspace_id"
}

conversation_draft_file_for() {
  workspace_id=$1
  conversation_id=$2
  printf '%s/conversations/%s/draft-message.txt' "$(workspace_dir_for "$workspace_id")" "$conversation_id"
}

workspace_path_for_id() {
  workspace_id=$1
  ws_dir=$(workspace_dir_for "$workspace_id")
  if [ ! -d "$ws_dir" ]; then
    printf '%s' ""
    return 0
  fi
  workspace_path=$(trim "$(read_file_line "$ws_dir/path" "")")
  printf '%s' "$workspace_path"
}

terminal_session_dir_for_workspace() {
  workspace_id=$1
  printf '%s/%s' "$terminal_sessions_root" "$workspace_id"
}

terminal_session_id_file_for_workspace() {
  workspace_id=$1
  printf '%s/id' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_pid_file_for_workspace() {
  workspace_id=$1
  printf '%s/pid' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_input_fifo_for_workspace() {
  workspace_id=$1
  printf '%s/in.fifo' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_output_file_for_workspace() {
  workspace_id=$1
  printf '%s/out.log' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_workspace_file_for_workspace() {
  workspace_id=$1
  printf '%s/workspace_path' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_started_file_for_workspace() {
  workspace_id=$1
  printf '%s/started' "$(terminal_session_dir_for_workspace "$workspace_id")"
}

terminal_session_pid_for_workspace() {
  workspace_id=$1
  read_file_line "$(terminal_session_pid_file_for_workspace "$workspace_id")" ""
}

terminal_session_id_for_workspace() {
  workspace_id=$1
  read_file_line "$(terminal_session_id_file_for_workspace "$workspace_id")" ""
}

terminal_session_running_for_workspace() {
  workspace_id=$1
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  case "$shell_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$shell_pid" 2>/dev/null
}

terminal_session_cleanup_for_workspace() {
  workspace_id=$1
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  case "$shell_pid" in
    ""|*[!0-9]*) ;;
    *)
      kill "$shell_pid" 2>/dev/null || true
      sleep 0.05
      kill -9 "$shell_pid" 2>/dev/null || true
      ;;
  esac
  session_dir=$(terminal_session_dir_for_workspace "$workspace_id")
  rm -rf "$session_dir"
}

terminal_session_start_for_workspace() {
  workspace_id=$1
  workspace_path=$2

  session_dir=$(terminal_session_dir_for_workspace "$workspace_id")
  shell_pid=$(terminal_session_pid_for_workspace "$workspace_id")
  existing_id=$(terminal_session_id_for_workspace "$workspace_id")
  existing_workspace=$(read_file_line "$(terminal_session_workspace_file_for_workspace "$workspace_id")" "")

  if terminal_session_running_for_workspace "$workspace_id" && [ -n "$existing_id" ] && [ "$existing_workspace" = "$workspace_path" ]; then
    printf '%s' "$existing_id"
    return 0
  fi

  terminal_session_cleanup_for_workspace "$workspace_id"
  mkdir -p "$session_dir"

  session_id=$(new_id)
  input_fifo=$(terminal_session_input_fifo_for_workspace "$workspace_id")
  output_file=$(terminal_session_output_file_for_workspace "$workspace_id")
  pid_file=$(terminal_session_pid_file_for_workspace "$workspace_id")
  id_file=$(terminal_session_id_file_for_workspace "$workspace_id")
  workspace_file=$(terminal_session_workspace_file_for_workspace "$workspace_id")
  started_file=$(terminal_session_started_file_for_workspace "$workspace_id")

  mkfifo "$input_fifo"
  : > "$output_file"
  printf '%s\n' "$session_id" > "$id_file"
  printf '%s\n' "$workspace_path" > "$workspace_file"
  date +%s > "$started_file"

  (
    cd "$workspace_path" || exit 1
    nohup script -q /dev/null /bin/zsh -i <"$input_fifo" >"$output_file" 2>&1 &
    printf '%s\n' "$!" > "$pid_file"
  )

  sleep 0.08
  if ! terminal_session_running_for_workspace "$workspace_id"; then
    tail_preview=$(tail -n 40 "$output_file" 2>/dev/null || true)
    terminal_session_cleanup_for_workspace "$workspace_id"
    printf '%s' "could not start terminal session: $(trim "$tail_preview")"
    return 1
  fi

  printf '%s' "$session_id"
  return 0
}

terminal_output_delta_json() {
  output_file=$1
  offset_raw=$2
  offset=0
  case "$offset_raw" in
    ""|*[!0-9]*)
      offset=0
      ;;
    *)
      offset=$offset_raw
      ;;
  esac

  if [ ! -f "$output_file" ]; then
    printf '{"delta":"","offset":0}'
    return 0
  fi

  total_bytes=$(wc -c < "$output_file" | tr -d ' ')
  case "$total_bytes" in
    ""|*[!0-9]*)
      total_bytes=0
      ;;
  esac

  if [ "$offset" -lt 0 ]; then
    offset=0
  fi
  if [ "$offset" -gt "$total_bytes" ]; then
    offset=$total_bytes
  fi

  if [ "$offset" -ge "$total_bytes" ]; then
    printf '{"delta":"","offset":%s}' "$total_bytes"
    return 0
  fi

  start_byte=$((offset + 1))
  delta_text=$(tail -c +"$start_byte" "$output_file" 2>/dev/null || true)
  delta_json=$(json_escape "$delta_text")
  printf '{"delta":"%s","offset":%s}' "$delta_json" "$total_bytes"
}

kv_get() {
  key=$1
  text=$2
  printf '%s\n' "$text" | sed -n "s/^$key=//p" | sed -n '1p'
}

ARTIFICER_GIT_BIN=${ARTIFICER_GIT_BIN:-$WIZARDRY_DIR/spells/.arcana/ai-dev/artificer-git}
AI_DEV_DIR=${AI_DEV_DIR:-$WIZARDRY_DIR/spells/.arcana/ai-dev}
DICTATE_BIN=${DICTATE_BIN:-$WIZARDRY_DIR/spells/psi/dictate}
VOICE_RECOGNITION_ROOT_DIR=${VOICE_RECOGNITION_ROOT_DIR:-$HOME/.wizardry/voice-recognition}
VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN=${VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-ctranslate2-whisper}
VOICE_RECOGNITION_INSTALL_MLX_BIN=${VOICE_RECOGNITION_INSTALL_MLX_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-mlx-whisper}
VOICE_RECOGNITION_INSTALL_PARAKEET_BIN=${VOICE_RECOGNITION_INSTALL_PARAKEET_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/install-parakeet}
VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN=${VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-ctranslate2-whisper}
VOICE_RECOGNITION_UNINSTALL_MLX_BIN=${VOICE_RECOGNITION_UNINSTALL_MLX_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-mlx-whisper}
VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN=${VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/uninstall-parakeet}
VOICE_RECOGNITION_BACKEND_BIN=${VOICE_RECOGNITION_BACKEND_BIN:-$WIZARDRY_DIR/spells/.arcana/voice-recognition/voice-recognition-backend}

resolve_artificer_git_bin() {
  if [ -x "$ARTIFICER_GIT_BIN" ]; then
    printf '%s' "$ARTIFICER_GIT_BIN"
    return 0
  fi
  if command -v artificer-git >/dev/null 2>&1; then
    ARTIFICER_GIT_BIN=$(command -v artificer-git)
    printf '%s' "$ARTIFICER_GIT_BIN"
    return 0
  fi
  return 1
}

run_artificer_git() {
  git_bin=$(resolve_artificer_git_bin || true)
  if [ -z "$git_bin" ]; then
    printf '%s' "artificer-git helper is unavailable"
    return 1
  fi
  selected_pub=$(selected_ssh_pub_path)
  if [ -n "$selected_pub" ] && [ -f "$selected_pub" ]; then
    selected_private=${selected_pub%.pub}
    if [ -f "$selected_private" ]; then
      GIT_SSH_COMMAND="ssh -i \"$selected_private\" -o IdentitiesOnly=yes"
      export GIT_SSH_COMMAND
    fi
  fi
  "$git_bin" "$@"
}

run_ai_dev_script() {
  script_name=$1
  shift

  case "$script_name" in
    ''|*[!a-zA-Z0-9_-]*)
      printf '%s' "invalid ai-dev script name: $script_name"
      return 1
      ;;
  esac

  if [ -z "${WIZARDRY_DIR-}" ]; then
    WIZARDRY_DIR="$HOME/.wizardry"
  fi
  if [ -z "${AI_DEV_DIR-}" ]; then
    AI_DEV_DIR="$WIZARDRY_DIR/spells/.arcana/ai-dev"
  fi
  PATH="$WIZARDRY_DIR/spells/.imps/cgi:$WIZARDRY_DIR/spells/.imps/sys:$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin"
  export WIZARDRY_DIR AI_DEV_DIR PATH

  script_path="$AI_DEV_DIR/$script_name"
  if [ -x "$script_path" ]; then
    "$script_path" "$@"
    return $?
  fi
  if command -v "$script_name" >/dev/null 2>&1; then
    "$script_name" "$@"
    return $?
  fi
  printf '%s' "ai-dev script unavailable: $script_name (AI_DEV_DIR=$AI_DEV_DIR)"
  return 1
}

resolve_dictate_bin() {
  if [ -x "$DICTATE_BIN" ]; then
    printf '%s' "$DICTATE_BIN"
    return 0
  fi
  if command -v dictate >/dev/null 2>&1; then
    DICTATE_BIN=$(command -v dictate)
    printf '%s' "$DICTATE_BIN"
    return 0
  fi
  return 1
}

resolve_voice_recognition_install_bin() {
  component=$1
  configured_bin=""
  command_name=""
  case "$component" in
    ctranslate2-whisper)
      configured_bin=$VOICE_RECOGNITION_INSTALL_CTRANSLATE2_BIN
      command_name="install-ctranslate2-whisper"
      ;;
    mlx-whisper)
      configured_bin=$VOICE_RECOGNITION_INSTALL_MLX_BIN
      command_name="install-mlx-whisper"
      ;;
    parakeet)
      configured_bin=$VOICE_RECOGNITION_INSTALL_PARAKEET_BIN
      command_name="install-parakeet"
      ;;
    *)
      return 1
      ;;
  esac

  if [ -n "$configured_bin" ] && [ -x "$configured_bin" ]; then
    printf '%s' "$configured_bin"
    return 0
  fi

  if [ -n "$command_name" ] && command -v "$command_name" >/dev/null 2>&1; then
    printf '%s' "$(command -v "$command_name")"
    return 0
  fi

  return 1
}

resolve_voice_recognition_uninstall_bin() {
  component=$1
  configured_bin=""
  command_name=""
  case "$component" in
    ctranslate2-whisper)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_CTRANSLATE2_BIN
      command_name="uninstall-ctranslate2-whisper"
      ;;
    mlx-whisper)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_MLX_BIN
      command_name="uninstall-mlx-whisper"
      ;;
    parakeet)
      configured_bin=$VOICE_RECOGNITION_UNINSTALL_PARAKEET_BIN
      command_name="uninstall-parakeet"
      ;;
    *)
      return 1
      ;;
  esac

  if [ -n "$configured_bin" ] && [ -x "$configured_bin" ]; then
    printf '%s' "$configured_bin"
    return 0
  fi

  if [ -n "$command_name" ] && command -v "$command_name" >/dev/null 2>&1; then
    printf '%s' "$(command -v "$command_name")"
    return 0
  fi

  return 1
}

resolve_voice_recognition_backend_bin() {
  if [ -x "$VOICE_RECOGNITION_BACKEND_BIN" ]; then
    printf '%s' "$VOICE_RECOGNITION_BACKEND_BIN"
    return 0
  fi
  if command -v voice-recognition-backend >/dev/null 2>&1; then
    VOICE_RECOGNITION_BACKEND_BIN=$(command -v voice-recognition-backend)
    printf '%s' "$VOICE_RECOGNITION_BACKEND_BIN"
    return 0
  fi
  return 1
}

voice_host_is_macos_arm64() {
  host_os=$(uname -s 2>/dev/null || printf 'unknown')
  [ "$host_os" = "Darwin" ] || return 1

  host_arch=$(uname -m 2>/dev/null || printf 'unknown')
  case "$host_arch" in
    arm64|aarch64)
      return 0
      ;;
  esac

  if command -v sysctl >/dev/null 2>&1; then
    arm64_flag=$(sysctl -in hw.optional.arm64 2>/dev/null || printf '0')
    [ "$arm64_flag" = "1" ] && return 0
  fi

  return 1
}

voice_needs_macos_arm64_uname_override() {
  voice_host_is_macos_arm64 || return 1
  host_arch=$(uname -m 2>/dev/null || printf 'unknown')
  case "$host_arch" in
    arm64|aarch64) return 1 ;;
  esac
  return 0
}

voice_can_run_arch_arm64() {
  if ! command -v arch >/dev/null 2>&1; then
    return 1
  fi
  arch -arm64 /usr/bin/true >/dev/null 2>&1
}

run_with_macos_arm64_context() {
  if voice_needs_macos_arm64_uname_override; then
    if voice_can_run_arch_arm64; then
      arch -arm64 "$@"
      return $?
    fi
    printf '%s\n' "voice-recognition: native arm64 execution is unavailable" >&2
    return 126
  fi
  "$@"
}

run_voice_component_command() {
  component=$1
  shift
  if [ "$component" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
    run_with_macos_arm64_context "$@"
    return $?
  fi
  "$@"
}

run_voice_backend_command() {
  backend_bin=$1
  shift
  if voice_needs_macos_arm64_uname_override; then
    run_with_macos_arm64_context "$backend_bin" "$@"
    return $?
  fi
  "$backend_bin" "$@"
}

voice_component_label() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "MLX Whisper"
      ;;
    parakeet)
      printf '%s' "Parakeet"
      ;;
    ctranslate2-whisper)
      printf '%s' "CTranslate2 Whisper"
      ;;
    *)
      printf '%s' "$component"
      ;;
  esac
}

voice_component_model() {
  component=$1
  case "$component" in
    ctranslate2-whisper)
      printf '%s' "small.en"
      ;;
    mlx-whisper)
      printf '%s' "${WIZARDRY_VOICE_MODEL_MLX:-mlx-community/whisper-small-mlx}"
      ;;
    parakeet)
      printf '%s' "${WIZARDRY_VOICE_MODEL_PARAKEET:-nvidia/parakeet-tdt-0.6b-v2}"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_download_size_bytes() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "480000000"
      ;;
    parakeet)
      printf '%s' "6200000000"
      ;;
    ctranslate2-whisper)
      printf '%s' "1500000000"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_hf_repo_id() {
  component=$1
  case "$component" in
    mlx-whisper)
      printf '%s' "mlx-community/whisper-small-mlx"
      ;;
    parakeet)
      printf '%s' "nvidia/parakeet-tdt-0.6b-v2"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

voice_component_download_size_bytes_from_web() {
  component=$1
  repo_id=$(voice_component_hf_repo_id "$component")
  if [ -z "$repo_id" ] || ! command -v curl >/dev/null 2>&1; then
    printf '%s' ""
    return 0
  fi

  api_url="https://huggingface.co/api/models/$repo_id/tree/main?recursive=1"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    model_json=$(timeout 12 curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then
    model_json=$(gtimeout 12 curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  else
    model_json=$(curl -fsSL --max-time 10 "$api_url" 2>/dev/null)
    fetch_rc=$?
  fi
  set -e

  if [ "$fetch_rc" -ne 0 ] || [ -z "$model_json" ]; then
    printf '%s' ""
    return 0
  fi

  size_bytes=$(printf '%s' "$model_json" \
    | tr -d '\n' \
    | sed 's/},{"type":"file"/\
{"type":"file"/g' \
    | awk '
      {
        if (match($0, /"size":[0-9]+/)) {
          token = substr($0, RSTART, RLENGTH)
          gsub(/[^0-9]/, "", token)
          if (token != "") sum += (token + 0)
        }
      }
      END {
        if (sum > 0) printf "%.0f", sum
      }
    ')

  case "$size_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      ;;
    *)
      printf '%s' "$size_bytes"
      ;;
  esac
}

voice_component_state_file() {
  component=$1
  printf '%s/%s/installed\n' "$VOICE_RECOGNITION_ROOT_DIR" "$component"
}

voice_component_python_bin() {
  component=$1
  printf '%s/%s/venv/bin/python\n' "$VOICE_RECOGNITION_ROOT_DIR" "$component"
}

voice_component_installed() {
  component=$1
  state_file=$(voice_component_state_file "$component")
  python_bin=$(voice_component_python_bin "$component")
  [ -f "$state_file" ] && [ -x "$python_bin" ]
}

voice_usage_bytes_for_path() {
  target_path=$1
  if [ ! -d "$target_path" ]; then
    printf '%s' "0"
    return 0
  fi
  usage_kb=$(du -sk "$target_path" 2>/dev/null | awk 'NR==1 { print $1 + 0 }')
  if [ -z "$usage_kb" ]; then
    printf '%s' "0"
    return 0
  fi
  awk -v kb="$usage_kb" 'BEGIN { printf "%.0f", kb * 1024 }'
}

voice_runtime_usage_bytes() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    printf '%s' "0"
    return 0
  fi
  voice_usage_bytes_for_path "$root"
}

voice_component_download_cache_path() {
  component=$1
  case "$component" in
    ctranslate2-whisper|mlx-whisper|parakeet)
      printf '%s/%s\n' "$VOICE_RECOGNITION_ROOT_DIR" "huggingface"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

voice_component_download_usage_bytes() {
  component=$1
  cache_path=$(voice_component_download_cache_path "$component")
  if [ -z "$cache_path" ]; then
    printf '%s' ""
    return 0
  fi
  voice_usage_bytes_for_path "$cache_path"
}

voice_download_cache_root_path() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  printf '%s/%s\n' "$root" "huggingface"
}

voice_component_cache_slug() {
  component=$1
  repo_id=$(voice_component_hf_repo_id "$component")
  if [ -z "$repo_id" ]; then
    printf '%s' ""
    return 0
  fi
  # Hugging Face hub cache directories use models--org--repo naming.
  repo_slug=$(printf '%s' "$repo_id" | sed 's#/#--#g')
  printf '%s' "models--$repo_slug"
}

dictation_cleanup_trash_dir() {
  printf '%s/.cleanup-trash' "$dictation_installs_dir"
}

quarantine_path_for_async_delete() {
  source_path=$1
  label=$2
  if [ ! -e "$source_path" ]; then
    return 0
  fi

  trash_root=$(dictation_cleanup_trash_dir)
  mkdir -p "$trash_root" 2>/dev/null || return 1
  ts=$(date +%s 2>/dev/null || printf '0')
  nonce=$(new_id)
  target_path="$trash_root/$ts-$nonce-$label"

  mv "$source_path" "$target_path" 2>/dev/null || return 1
  spawn_detached_job rm -rf "$target_path" >/dev/null 2>&1 || true
  return 0
}

remove_voice_component_artifacts() {
  component=$1
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi

  component_dir="$root/$component"
  case "$component_dir" in
    "$root"/*)
      if [ -e "$component_dir" ]; then
        quarantine_path_for_async_delete "$component_dir" "${component}-runtime" || return 1
      fi
      ;;
  esac

  cache_slug=$(voice_component_cache_slug "$component")
  if [ -n "$cache_slug" ]; then
    hf_hub_dir="$root/huggingface/hub"
    for entry in "$hf_hub_dir/$cache_slug" "$hf_hub_dir/$cache_slug".* "$hf_hub_dir/$cache_slug"-*; do
      if [ -e "$entry" ]; then
        quarantine_path_for_async_delete "$entry" "${component}-hub" || return 1
      fi
    done
    hf_locks_dir="$root/huggingface/.locks"
    for lock_entry in "$hf_locks_dir/$cache_slug" "$hf_locks_dir/$cache_slug".* "$hf_locks_dir/$cache_slug"-*; do
      if [ -e "$lock_entry" ]; then
        quarantine_path_for_async_delete "$lock_entry" "${component}-lock" || return 1
      fi
    done
  fi
  return 0
}

remove_voice_download_cache() {
  cache_root=$(voice_download_cache_root_path 2>/dev/null || true)
  if [ -z "$cache_root" ]; then
    return 1
  fi
  if [ ! -d "$cache_root" ]; then
    return 0
  fi
  quarantine_path_for_async_delete "$cache_root" "voice-download-cache" || return 1
  return 0
}

dictation_live_session_dir() {
  printf '%s/session' "$dictation_live_dir"
}

dictation_live_session_file() {
  key=$1
  printf '%s/%s' "$(dictation_live_session_dir)" "$key"
}

clear_dictation_live_session() {
  session_dir=$(dictation_live_session_dir)
  rm -rf "$session_dir" 2>/dev/null || true
}

dictation_live_session_value() {
  key=$1
  read_file_line "$(dictation_live_session_file "$key")" ""
}

dictation_live_has_active_capture() {
  capture_pid=$(dictation_live_session_value "pid")
  case "$capture_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$capture_pid" 2>/dev/null
}

dictation_live_status() {
  read_file_line "$(dictation_live_session_file "status")" ""
}

current_time_millis() {
  now_ms=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000' 2>/dev/null || true)
  case "$now_ms" in
    ""|*[!0-9]*)
      now_s=$(date +%s 2>/dev/null || printf '0')
      case "$now_s" in
        ""|*[!0-9]*) now_s=0 ;;
      esac
      now_ms=$((now_s * 1000))
      ;;
  esac
  printf '%s' "$now_ms"
}

arm_dictation_prepare_guard() {
  session_dir=$1
  capture_pid=$2
  guard_script="$session_dir/prepare-guard.sh"
  cat > "$guard_script" <<'EOF'
#!/bin/sh
set -eu
session_dir=$1
capture_pid=$2
sleep 20
status_file="$session_dir/status"
pid_file="$session_dir/pid"
status_val=$(cat "$status_file" 2>/dev/null || printf '')
pid_val=$(cat "$pid_file" 2>/dev/null || printf '')
if [ "$status_val" = "prepared" ] && [ "$pid_val" = "$capture_pid" ]; then
  kill -INT "$capture_pid" 2>/dev/null || true
  sleep 0.08
  kill -TERM "$capture_pid" 2>/dev/null || true
  rm -rf "$session_dir" 2>/dev/null || true
fi
EOF
  chmod +x "$guard_script"
  guard_pid=$(spawn_detached_job "$guard_script" "$session_dir" "$capture_pid")
  printf '%s\n' "$guard_pid" > "$session_dir/prepare_guard_pid"
}

dictation_live_level_for_session() {
  levels_file=$(dictation_live_session_value "levels_file")
  if [ -z "$levels_file" ] || [ ! -f "$levels_file" ]; then
    printf '%s' "0"
    return 0
  fi

  # Prefer Overall RMS-derived telemetry for steadier behavior.
  # Newer ffmpeg astats emits `RMS_peak` instead of `RMS_level`.
  # Some ffmpeg builds include NUL bytes in ametadata output; strip binary bytes first.
  recent_levels=$(tail -n 320 "$levels_file" 2>/dev/null | tr -d '\000\r' || true)
  level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.Peak_level' | tail -n 1 || true)
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_level' | grep -aE -iv 'Overall\.Peak_level' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_level' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_peak' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'RMS_(level|peak)' | tail -n 1 || true)
  fi
  if [ -z "$level_line" ]; then
    level_line=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_(level|count)' | tail -n 1 || true)
  fi
  level_db=$(printf '%s' "$level_line" | sed -E 's/.*(RMS_(level|peak)|Peak_(level|count))[^-0-9iInNfF]*(-?inf|-?[0-9]+(\.[0-9]+)?).*/\4/I')
  if [ -z "$level_db" ]; then
    printf '%s' "0"
    return 0
  fi
  if printf '%s' "$level_db" | grep -Eq '^-?inf$'; then
    printf '%s' "0"
    return 0
  fi
  awk -v db="$level_db" '
    BEGIN {
      v = db + 0.0
      if (v < -74) v = -74
      if (v > -18) v = -18
      level = (v + 74) / 56
      # Keep ambient room noise near baseline while lifting normal speech variance.
      level = level * level
      if (level < 0) level = 0
      if (level > 1) level = 1
      printf "%.5f", level
    }
  '
}

dictation_live_levels_json_for_session() {
  levels_file=$(dictation_live_session_value "levels_file")
  if [ -z "$levels_file" ] || [ ! -f "$levels_file" ]; then
    printf '%s' "[]"
    return 0
  fi

  # Emit recent peak-derived levels so UI bars react at finer temporal granularity.
  recent_levels=$(tail -n 960 "$levels_file" 2>/dev/null | tr -d '\000\r' || true)
  rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.Peak_level' || true)
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_level' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_level' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'RMS_(level|peak)' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Overall\.RMS_peak' || true)
  fi
  if [ -z "$rms_lines" ]; then
    rms_lines=$(printf '%s\n' "$recent_levels" | grep -aE -i 'Peak_(level|count)' || true)
  fi
  if [ -z "$rms_lines" ]; then
    printf '%s' "[]"
    return 0
  fi

  raw_levels=$(printf '%s\n' "$rms_lines" \
    | sed -nE 's/.*(RMS_(level|peak)|Peak_(level|count))[^-0-9iInNfF]*(-?inf|-?[0-9]+(\.[0-9]+)?).*/\4/Ip' \
    | tail -n 24)
  if [ -z "$raw_levels" ]; then
    printf '%s' "[]"
    return 0
  fi

  levels_json=$(printf '%s\n' "$raw_levels" | awk '
    BEGIN {
      first = 1
      printf "["
    }
    {
      raw = $0
      if (raw ~ /[iI][nN][fF]/) {
        next
      }
      v = raw + 0.0
      if (v < -74) v = -74
      if (v > -18) v = -18
      level = (v + 74) / 56
      level = level * level
      if (level < 0) level = 0
      if (level > 1) level = 1
      if (!first) {
        printf ","
      }
      printf "%.5f", level
      first = 0
    }
    END {
      printf "]"
    }
  ')
  if [ -z "$levels_json" ]; then
    levels_json="[]"
  fi
  printf '%s' "$levels_json"
}

stop_capture_pid_gracefully() {
  capture_pid=$1
  case "$capture_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac

  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  kill -INT "$capture_pid" 2>/dev/null || true
  waited=0
  while kill -0 "$capture_pid" 2>/dev/null && [ "$waited" -lt 3000 ]; do
    sleep 0.05
    waited=$((waited + 50))
  done
  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  kill -TERM "$capture_pid" 2>/dev/null || true
  waited=0
  while kill -0 "$capture_pid" 2>/dev/null && [ "$waited" -lt 3000 ]; do
    sleep 0.05
    waited=$((waited + 50))
  done
  if ! kill -0 "$capture_pid" 2>/dev/null; then
    return 0
  fi

  stop_process_tree_by_pid "$capture_pid"
}

wait_for_audio_capture_file() {
  audio_file=$1
  max_wait_ms=$2
  case "$max_wait_ms" in
    ""|*[!0-9]*)
      max_wait_ms=1200
      ;;
  esac
  waited=0
  while [ "$waited" -le "$max_wait_ms" ]; do
    if [ -f "$audio_file" ]; then
      bytes=$(wc -c < "$audio_file" 2>/dev/null | tr -d ' ')
      case "$bytes" in
        ""|*[!0-9]*) bytes=0 ;;
      esac
      # 44-byte RIFF header is valid but often indicates effectively empty audio.
      # Still treat it as captured so the transcriber can return a precise result.
      if [ "$bytes" -ge 44 ]; then
        return 0
      fi
    fi
    sleep 0.05
    waited=$((waited + 50))
  done
  return 1
}

transcribe_dictation_audio() {
  backend=$1
  model_name=$2
  language=$3
  audio_path=$4
  python_bin=$5

  [ -x "$python_bin" ] || return 1

  transcribe_rc=0
  if [ "$backend" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
    if voice_can_run_arch_arm64; then
      DICTATE_AUDIO_PATH="$audio_path" \
      DICTATE_BACKEND="$backend" \
      DICTATE_MODEL="$model_name" \
      DICTATE_LANGUAGE="$language" \
      HF_HOME="${WIZARDRY_VOICE_RECOGNITION_HF_HOME:-$HOME/.wizardry/voice-recognition/huggingface}" \
      HF_HUB_OFFLINE=1 \
      TRANSFORMERS_OFFLINE=1 \
      arch -arm64 "$python_bin" <<'PY'
import os
import sys

backend = os.environ.get("DICTATE_BACKEND", "")
audio_path = os.environ.get("DICTATE_AUDIO_PATH", "")
model_name = os.environ.get("DICTATE_MODEL", "")
language = os.environ.get("DICTATE_LANGUAGE", "").strip()
if not language:
    language = None


def squash(text):
    return " ".join(str(text or "").strip().split())


text = ""

try:
    if backend == "ctranslate2-whisper":
        from faster_whisper import WhisperModel

        model = WhisperModel(model_name, device="auto", compute_type="int8")
        kwargs = {"vad_filter": True}
        if language:
            kwargs["language"] = language
        segments, _info = model.transcribe(audio_path, **kwargs)
        parts = []
        for segment in segments:
            segment_text = squash(getattr(segment, "text", ""))
            if segment_text:
                parts.append(segment_text)
        text = " ".join(parts)
    elif backend == "mlx-whisper":
        import mlx_whisper

        kwargs = {"path_or_hf_repo": model_name}
        if language:
            kwargs["language"] = language
        result = mlx_whisper.transcribe(audio_path, **kwargs)
        if isinstance(result, dict):
            text = squash(result.get("text", ""))
    elif backend == "parakeet":
        import nemo.collections.asr as nemo_asr

        model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name)
        try:
            outputs = model.transcribe([audio_path])
        except TypeError:
            outputs = model.transcribe([audio_path], batch_size=1)

        item = ""
        if isinstance(outputs, list) and outputs:
            item = outputs[0]
        else:
            item = outputs

        if hasattr(item, "text"):
            text = squash(getattr(item, "text", ""))
        elif isinstance(item, dict):
            text = squash(item.get("text", ""))
        else:
            text = squash(item)
    else:
        raise RuntimeError("unknown backend")
except Exception as exc:
    sys.stderr.write(f"backend runtime failed: {exc}\n")
    sys.exit(1)

text = squash(text)
if not text:
    sys.stderr.write("no speech detected\n")
    sys.exit(1)

sys.stdout.write(text + "\n")
PY
      transcribe_rc=$?
    else
      printf '%s\n' "backend runtime failed: native arm64 execution is unavailable" >&2
      transcribe_rc=126
    fi
  else
    DICTATE_AUDIO_PATH="$audio_path" \
    DICTATE_BACKEND="$backend" \
    DICTATE_MODEL="$model_name" \
    DICTATE_LANGUAGE="$language" \
    HF_HOME="${WIZARDRY_VOICE_RECOGNITION_HF_HOME:-$HOME/.wizardry/voice-recognition/huggingface}" \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    "$python_bin" <<'PY'
import os
import sys

backend = os.environ.get("DICTATE_BACKEND", "")
audio_path = os.environ.get("DICTATE_AUDIO_PATH", "")
model_name = os.environ.get("DICTATE_MODEL", "")
language = os.environ.get("DICTATE_LANGUAGE", "").strip()
if not language:
    language = None


def squash(text):
    return " ".join(str(text or "").strip().split())


text = ""

try:
    if backend == "ctranslate2-whisper":
        from faster_whisper import WhisperModel

        model = WhisperModel(model_name, device="auto", compute_type="int8")
        kwargs = {"vad_filter": True}
        if language:
            kwargs["language"] = language
        segments, _info = model.transcribe(audio_path, **kwargs)
        parts = []
        for segment in segments:
            segment_text = squash(getattr(segment, "text", ""))
            if segment_text:
                parts.append(segment_text)
        text = " ".join(parts)
    elif backend == "mlx-whisper":
        import mlx_whisper

        kwargs = {"path_or_hf_repo": model_name}
        if language:
            kwargs["language"] = language
        result = mlx_whisper.transcribe(audio_path, **kwargs)
        if isinstance(result, dict):
            text = squash(result.get("text", ""))
    elif backend == "parakeet":
        import nemo.collections.asr as nemo_asr

        model = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name)
        try:
            outputs = model.transcribe([audio_path])
        except TypeError:
            outputs = model.transcribe([audio_path], batch_size=1)

        item = ""
        if isinstance(outputs, list) and outputs:
            item = outputs[0]
        else:
            item = outputs

        if hasattr(item, "text"):
            text = squash(getattr(item, "text", ""))
        elif isinstance(item, dict):
            text = squash(item.get("text", ""))
        else:
            text = squash(item)
    else:
        raise RuntimeError("unknown backend")
except Exception as exc:
    sys.stderr.write(f"backend runtime failed: {exc}\n")
    sys.exit(1)

text = squash(text)
if not text:
    sys.stderr.write("no speech detected\n")
    sys.exit(1)

sys.stdout.write(text + "\n")
PY
    transcribe_rc=$?
  fi

  return "$transcribe_rc"
}

progress_pct_max() {
  current=$1
  candidate=$2
  if [ -z "$candidate" ]; then
    printf '%s' "$current"
    return 0
  fi
  if [ -z "$current" ]; then
    current="0"
  fi
  printf '%s %s\n' "$current" "$candidate" | awk '
    {
      a = $1 + 0
      b = $2 + 0
      if (b > a) a = b
      if (a < 0) a = 0
      if (a > 100) a = 100
      printf "%.1f", a
    }
  '
}

progress_pct_from_bytes() {
  delta_bytes=$1
  total_bytes=$2
  case "$delta_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      return 0
      ;;
  esac
  case "$total_bytes" in
    *[!0-9]*|"")
      printf '%s' ""
      return 0
      ;;
  esac
  awk -v delta="$delta_bytes" -v total="$total_bytes" '
    BEGIN {
      d = delta + 0
      t = total + 0
      if (t <= 0) {
        exit 1
      }
      if (d < 0) d = 0
      p = (d * 100.0) / t
      if (p < 0) p = 0
      if (p > 99.9) p = 99.9
      printf "%.1f", p
    }
  ' 2>/dev/null || printf '%s' ""
}

voice_runtime_root_path() {
  root=$VOICE_RECOGNITION_ROOT_DIR
  root=$(trim "$root")
  case "$root" in
    ""|"/"|".")
      return 1
      ;;
  esac
  printf '%s' "$root"
}

remove_voice_runtime_root() {
  root=$(voice_runtime_root_path 2>/dev/null || true)
  if [ -z "$root" ]; then
    return 1
  fi
  if [ ! -d "$root" ]; then
    return 0
  fi
  rm -rf "$root" 2>/dev/null || return 1
  return 0
}

dictation_job_lock_path() {
  printf '%s/.job-lock' "$dictation_installs_dir"
}

acquire_dictation_job_lock() {
  max_wait_ms=$1
  case "$max_wait_ms" in
    ""|*[!0-9]*)
      max_wait_ms=1500
      ;;
  esac

  lock_dir=$(dictation_job_lock_path)
  waited_ms=0

  while :; do
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$lock_dir/pid" 2>/dev/null || true
      date +%s > "$lock_dir/started" 2>/dev/null || true
      return 0
    fi

    lock_pid=$(read_file_line "$lock_dir/pid" "")
    lock_started=$(read_file_line "$lock_dir/started" "0")
    lock_stale=0

    case "$lock_pid" in
      ""|*[!0-9]*)
        lock_stale=1
        ;;
      *)
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          lock_stale=1
        fi
        ;;
    esac

    if [ "$lock_stale" -eq 0 ]; then
      now_epoch=$(date +%s 2>/dev/null || printf '0')
      case "$now_epoch:$lock_started" in
        *[!0-9]*:*|*:*[!0-9]*)
          :
          ;;
        *)
          lock_age=$((now_epoch - lock_started))
          if [ "$lock_age" -gt 120 ] 2>/dev/null; then
            lock_stale=1
          fi
          ;;
      esac
    fi

    if [ "$lock_stale" -eq 1 ]; then
      rm -rf "$lock_dir" 2>/dev/null || true
      continue
    fi

    if [ "$waited_ms" -ge "$max_wait_ms" ] 2>/dev/null; then
      return 1
    fi
    sleep 0.05
    waited_ms=$((waited_ms + 50))
  done
}

release_dictation_job_lock() {
  lock_dir=$(dictation_job_lock_path)
  rm -rf "$lock_dir" 2>/dev/null || true
}

stop_process_tree_by_pid() {
  target_pid=$1
  case "$target_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac

  if ! kill -0 "$target_pid" 2>/dev/null; then
    return 0
  fi

  if command -v pkill >/dev/null 2>&1; then
    pkill -KILL -P "$target_pid" 2>/dev/null || true
  fi
  kill -KILL "$target_pid" 2>/dev/null || true
  sleep 0.05

  if kill -0 "$target_pid" 2>/dev/null; then
    return 1
  fi
  return 0
}

preferred_voice_component_for_host() {
  if voice_host_is_macos_arm64; then
    printf '%s' "mlx-whisper"
    return 0
  fi

  host_os=$(uname -s 2>/dev/null || printf 'unknown')
  if [ "$host_os" = "Linux" ] && command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi -L >/dev/null 2>&1; then
      printf '%s' "parakeet"
      return 0
    fi
  fi

  printf '%s' "ctranslate2-whisper"
}

installed_voice_backend_for_host() {
  preferred_component=$(preferred_voice_component_for_host)

  for component in "$preferred_component" ctranslate2-whisper mlx-whisper parakeet; do
    [ -n "$component" ] || continue
    if voice_component_installed "$component"; then
      printf '%s' "$component"
      return 0
    fi
  done

  return 1
}

run_with_timeout() {
  timeout_sec=$1
  shift

  case "$timeout_sec" in
    ""|*[!0-9]*)
      timeout_sec=180
      ;;
  esac
  if [ "$timeout_sec" -lt 1 ]; then
    timeout_sec=1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_sec" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_sec" "$@"
    return $?
  fi
  "$@"
}

spawn_detached_job() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -MPOSIX -e 'POSIX::setsid() or die "setsid failed: $!"; exec @ARGV or die "exec failed: $!";' "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  if command -v nohup >/dev/null 2>&1; then
    nohup "$@" >/dev/null 2>&1 < /dev/null &
    printf '%s\n' "$!"
    return 0
  fi

  "$@" >/dev/null 2>&1 < /dev/null &
  printf '%s\n' "$!"
}

safe_model_name() {
  model_name=$1
  case "$model_name" in
    ""|*[!a-zA-Z0-9._:/-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

ollama_models_root_dir() {
  if [ -n "${OLLAMA_MODELS-}" ]; then
    printf '%s\n' "$OLLAMA_MODELS"
  else
    printf '%s\n' "$HOME/.ollama/models"
  fi
}

ollama_blobs_dir() {
  printf '%s/blobs\n' "$(ollama_models_root_dir)"
}

count_running_model_installs() {
  running_count=0
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    status=$(read_file_line "$job_dir/status" "")
    install_pid=$(read_file_line "$job_dir/pid" "")
    if [ "$status" = "running" ] && [ -n "$install_pid" ] && kill -0 "$install_pid" 2>/dev/null; then
      running_count=$((running_count + 1))
    fi
  done
  printf '%s\n' "$running_count"
}

model_install_runtime_status_for_model() {
  model_name=$1
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    running_model=$(read_file_line "$job_dir/model" "")
    [ "$running_model" = "$model_name" ] || continue
    status=$(read_file_line "$job_dir/status" "")
    install_pid=$(read_file_line "$job_dir/pid" "")
    if [ "$status" = "running" ] && [ -n "$install_pid" ] && ! kill -0 "$install_pid" 2>/dev/null; then
      status="failed"
    fi
    phase=""
    progress=""
    if [ "$status" = "running" ]; then
      log_tail=$(tail -n 160 "$job_dir/log" 2>/dev/null || true)
      parse_result=$(infer_model_install_phase_progress "$log_tail")
      phase=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      progress=$(printf '%s\n' "$parse_result" | cut -d'|' -f2)
      [ -n "$phase" ] || phase="running"
    fi
    printf '%s|%s|%s' "$status" "$phase" "$progress"
    return 0
  done
  printf '%s' "none||"
}

model_present_in_inventory() {
  model_name=$1
  inventory_text=$2
  [ -n "$(trim "$model_name")" ] || return 1
  [ -n "$(trim "$inventory_text")" ] || return 1
  printf '%s\n' "$inventory_text" | awk -v model="$model_name" '
    $0 == model {
      found = 1
      exit
    }
    END {
      exit(found ? 0 : 1)
    }
  '
}

cleanup_ollama_partial_blobs() {
  cleanup_mode=${1:-full}
  blobs_dir=$(ollama_blobs_dir)
  if [ ! -d "$blobs_dir" ]; then
    printf '%s\n' "removed=0|kept=0|resume_bytes=0|canonicalized=0"
    return 0
  fi
  python3 - "$blobs_dir" "$cleanup_mode" <<'PY'
import glob
import os
import sys

blobs_dir = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else "full"
removed = 0
kept = 0
resume_bytes = 0
canonicalized = 0

def safe_unlink(path):
    global removed
    try:
        os.unlink(path)
        removed += 1
    except FileNotFoundError:
        pass

paths = glob.glob(os.path.join(blobs_dir, "*-partial*"))
groups = {}
for path in paths:
    name = os.path.basename(path)
    if "-partial" not in name:
        continue
    base = name.split("-partial", 1)[0]
    groups.setdefault(base, []).append(path)

for base, items in groups.items():
    complete_path = os.path.join(blobs_dir, base)
    if os.path.exists(complete_path):
      for path in items:
        safe_unlink(path)
      continue

    stats = []
    for path in items:
        try:
            st = os.stat(path)
        except FileNotFoundError:
            continue
        is_canonical = 1 if path.endswith("-partial") else 0
        stats.append((st.st_size, st.st_mtime, is_canonical, path))
    if not stats:
        continue

    canonical_path = os.path.join(blobs_dir, base + "-partial")
    if mode == "stubs":
        keep_path = None
        for size, mtime, is_canonical, path in sorted(stats, key=lambda row: (row[2], row[0], row[1]), reverse=True):
            if keep_path is None and (is_canonical or size > 4096):
                keep_path = path
                break
        if keep_path is None:
            keep_path = max(stats, key=lambda row: (row[2], row[0], row[1]))[3]
    else:
        keep_path = max(stats, key=lambda row: (row[0], row[1], row[2]))[3]

    if mode == "full" and keep_path != canonical_path:
        try:
            if os.path.exists(canonical_path):
                os.unlink(canonical_path)
                removed += 1
            os.rename(keep_path, canonical_path)
            keep_path = canonical_path
            canonicalized += 1
        except OSError:
            pass

    kept += 1
    try:
        resume_bytes = max(resume_bytes, os.stat(keep_path).st_size)
    except FileNotFoundError:
        pass

    for _, _, _, path in stats:
        if path == keep_path:
            continue
        if mode == "stubs":
            try:
                size = os.stat(path).st_size
            except FileNotFoundError:
                continue
            if size > 4096:
                continue
        safe_unlink(path)

print(f"removed={removed}|kept={kept}|resume_bytes={resume_bytes}|canonicalized={canonicalized}")
PY
}

emit_model_installs_json() {
  printf '['
  first=1
  for job_dir in "$model_installs_dir"/*; do
    [ -d "$job_dir" ] || continue
    job_id=$(basename "$job_dir")
    [ -n "$job_id" ] || continue
    model_name=$(read_file_line "$job_dir/model" "")
    status=$(read_file_line "$job_dir/status" "running")
    started=$(read_file_line "$job_dir/started" "0")
    finished=$(read_file_line "$job_dir/finished" "0")
    install_pid=$(read_file_line "$job_dir/pid" "")
    exit_code=$(read_file_line "$job_dir/exit_code" "")
    resume_available=$(read_file_line "$job_dir/resume_available" "0")
    resume_bytes=$(read_file_line "$job_dir/resume_bytes" "0")
    stale_partial_files_removed=$(read_file_line "$job_dir/stale_partial_files_removed" "0")
    if [ "$status" = "running" ] && [ -n "$install_pid" ]; then
      if ! kill -0 "$install_pid" 2>/dev/null; then
        status="failed"
        if [ -n "$exit_code" ]; then
          case "$exit_code" in
            0) status="done" ;;
          esac
        fi
      fi
    fi

    log_tail=$(tail -n 120 "$job_dir/log" 2>/dev/null || true)
    install_phase="running"
    install_progress=""
    if [ "$status" = "done" ]; then
      install_phase="done"
      install_progress="100"
    elif [ "$status" = "failed" ]; then
      install_phase="failed"
      install_progress=""
    else
      parse_result=$(infer_model_install_phase_progress "$log_tail")
      install_phase=$(printf '%s\n' "$parse_result" | cut -d'|' -f1)
      install_progress=$(printf '%s\n' "$parse_result" | cut -d'|' -f2)
      [ -n "$install_phase" ] || install_phase="running"
    fi

    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '{"id":"%s","model":"%s","status":"%s","phase":"%s","progress_pct":"%s","started":"%s","finished":"%s","resume_available":%s,"resume_bytes":"%s","stale_partial_files_removed":"%s"}' \
      "$(json_escape "$job_id")" \
      "$(json_escape "$model_name")" \
      "$(json_escape "$status")" \
      "$(json_escape "$install_phase")" \
      "$(json_escape "$install_progress")" \
      "$(json_escape "$started")" \
      "$(json_escape "$finished")" \
      "$([ "$resume_available" = "1" ] && printf '%s' "true" || printf '%s' "false")" \
      "$(json_escape "$resume_bytes")" \
      "$(json_escape "$stale_partial_files_removed")"
  done
  printf ']'
}

infer_model_install_phase_progress() {
  log_text=$1
  phase="running"
  progress=""
  if [ -n "$log_text" ]; then
    if printf '%s\n' "$log_text" | grep -Eiq 'verifying sha256|writing manifest|extracting|finalizing|installed'; then
      phase="installing"
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'pulling manifest|pulling |downloading '; then
      phase="downloading"
    fi
    raw_progress=$(printf '%s\n' "$log_text" | grep -Eo '([0-9]{1,3})(\.[0-9]+)?%' | tail -n 1 | tr -d '%' || true)
    if [ -n "$raw_progress" ]; then
      progress=$(printf '%s\n' "$raw_progress" | awk '
        {
          v=$1 + 0
          if (v < 0) v = 0
          if (v > 100) v = 100
          printf "%d", v
        }
      ')
      phase="downloading"
      if [ "$progress" -ge 100 ] 2>/dev/null; then
        phase="installing"
      fi
    fi
  fi
  printf '%s|%s\n' "$phase" "$progress"
}

infer_dictation_install_phase_progress() {
  log_text=$1
  phase="downloading"
  progress="0.0"
  if [ -n "$log_text" ]; then
    progress_max() {
      current=$1
      candidate=$2
      printf '%s %s\n' "$current" "$candidate" | awk '
        {
          a = $1 + 0
          b = $2 + 0
          if (b > a) a = b
          if (a < 0) a = 0
          if (a > 100) a = 100
          printf "%.1f", a
        }
      '
    }

    if printf '%s\n' "$log_text" | grep -Eiq 'installing (ctranslate2-whisper|mlx-whisper|parakeet)'; then
      phase="preparing"
      progress=$(progress_max "$progress" "2.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'Fetching [0-9]+ files:'; then
      phase="downloading"
      progress=$(progress_max "$progress" "3.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'creating virtual environment'; then
      phase="preparing"
      progress=$(progress_max "$progress" "18.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'installing [a-z0-9-]+ packages'; then
      phase="installing"
      progress=$(progress_max "$progress" "52.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'preparing local model cache'; then
      phase="downloading"
      progress=$(progress_max "$progress" "82.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'falling back to ctranslate2-whisper'; then
      phase="fallback"
      progress=$(progress_max "$progress" "70.0")
    fi
    raw_progress=$(printf '%s\n' "$log_text" | grep -Eo '([0-9]{1,3})(\.[0-9]+)?%' | tail -n 1 | tr -d '%' || true)
    if [ -n "$raw_progress" ]; then
      progress=$(progress_max "$progress" "$raw_progress")
      if printf '%s\n' "$raw_progress" | awk '{ exit !($1 + 0 >= 100) }'; then
        phase="finalizing"
      fi
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'installed (ctranslate2-whisper|mlx-whisper|parakeet)'; then
      phase="finalizing"
      progress=$(progress_max "$progress" "96.0")
    fi
    if printf '%s\n' "$log_text" | grep -Eiq 'already installed'; then
      phase="finalizing"
      progress=$(progress_max "$progress" "99.0")
    fi
  fi
  printf '%s|%s\n' "$phase" "$progress"
}

dictation_phase_rank() {
  phase=$1
  case "$phase" in
    downloading) printf '%s' "10" ;;
    fallback) printf '%s' "15" ;;
    preparing) printf '%s' "20" ;;
    installing) printf '%s' "30" ;;
    finalizing) printf '%s' "40" ;;
    done) printf '%s' "100" ;;
    *) printf '%s' "0" ;;
  esac
}

dictation_phase_progressive() {
  previous_phase=$1
  next_phase=$2
  prev_rank=$(dictation_phase_rank "$previous_phase")
  next_rank=$(dictation_phase_rank "$next_phase")
  if [ "$next_rank" -lt "$prev_rank" ] 2>/dev/null; then
    printf '%s\n' "$previous_phase"
    return 0
  fi
  printf '%s\n' "$next_phase"
}

OLLAMA_BIN=""

resolve_ollama_bin() {
  if [ -n "$OLLAMA_BIN" ] && [ -x "$OLLAMA_BIN" ]; then
    printf '%s' "$OLLAMA_BIN"
    return 0
  fi

  if command -v ollama >/dev/null 2>&1; then
    OLLAMA_BIN=$(command -v ollama)
    printf '%s' "$OLLAMA_BIN"
    return 0
  fi

  for candidate in \
    /opt/homebrew/bin/ollama \
    /usr/local/bin/ollama \
    /usr/bin/ollama \
    "$HOME/.local/bin/ollama" \
    /Applications/Ollama.app/Contents/Resources/ollama
  do
    if [ -x "$candidate" ]; then
      OLLAMA_BIN=$candidate
      printf '%s' "$OLLAMA_BIN"
      return 0
    fi
  done

  return 1
}

ollama_host_candidates() {
  printf '%s\n%s\n%s\n' \
    "${OLLAMA_HOST:-http://127.0.0.1:11434}" \
    "http://127.0.0.1:11434" \
    "http://localhost:11434" \
    | awk '!seen[$0]++'
}

json_extract_string_field() {
  field_name=$1
  json_text=$2

  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$json_text" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $field = shift @ARGV;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $value = $data->{$field};
      exit 1 if !defined($value) || ref($value);
      print $value;
    ' "$field_name" 2>/dev/null || return 1
    return 0
  fi

  printf '%s' "$json_text" \
    | sed -n "s/.*\"$field_name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
    | sed -n '1p'
}

model_supports_vision() {
  model_name=$1
  host_candidates=$(ollama_host_candidates)

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  payload=$(printf '{"model":"%s"}' "$(json_escape "$model_name")")

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    show_json=$(curl -sS --connect-timeout 3 --max-time 8 \
      -H "Content-Type: application/json" \
      -X POST "$host/api/show" \
      -d "$payload" 2>/dev/null || true)
    [ -n "$show_json" ] || continue

    if printf '%s' "$show_json" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $caps = $data->{capabilities};
      exit 1 if ref($caps) ne "ARRAY";
      for my $item (@{$caps}) {
        next if !defined($item);
        if ($item eq "vision") {
          exit 0;
        }
      }
      exit 1;
    ' 2>/dev/null; then
      return 0
    fi
  done <<EOF
$host_candidates
EOF

  return 1
}

extract_urls_from_text() {
  text=$1
  printf '%s\n' "$text" \
    | grep -Eo 'https?://[^[:space:]<>()"'"'"']+' \
    | awk '!seen[$0]++'
}

url_encode_component() {
  printf '%s' "$1" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $value = <STDIN>;
    $value = "" if !defined($value);
    utf8::encode($value);
    $value =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;
    print $value;
  ' 2>/dev/null
}

normalize_search_result_url() {
  raw_url=$1
  if [ -z "$raw_url" ]; then
    printf '%s' ""
    return 0
  fi
  decoded_param=$(printf '%s' "$raw_url" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $value = <STDIN>;
    $value = "" if !defined($value);
    my $out = "";
    if ($value =~ /[?&]uddg=([^&]+)/) {
      $out = $1;
      $out =~ s/\+/ /g;
      $out =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    }
    print $out;
  ' 2>/dev/null || true)
  if [ -n "$decoded_param" ] && printf '%s' "$decoded_param" | grep -Eq '^https?://'; then
    printf '%s' "$decoded_param"
    return 0
  fi
  if printf '%s' "$raw_url" | grep -Eq '^https?://'; then
    printf '%s' "$raw_url"
    return 0
  fi
  printf '%s' ""
}

text_perfecter_search_queries_from_prompt() {
  prompt_text=$1
  prompt_line=$(printf '%s' "$prompt_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)
  prompt_line=$(trim "$prompt_line")
  [ -n "$prompt_line" ] || prompt_line="improve this text for factual quality and clarity"

  is_recipe_prompt=0
  if printf '%s' "$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')" | grep -Eq 'recipe|ingredients|cook|cooking|bake|oven|simmer|broil|marinate|preheat|teaspoon|tablespoon|cup|serves'; then
    is_recipe_prompt=1
  fi

  printf '%s\n' "$prompt_line"
  if [ "$is_recipe_prompt" -eq 1 ]; then
    printf '%s\n' "$prompt_line best recipe techniques common mistakes variations"
    printf '%s\n' "$prompt_line forum discussion reddit"
    printf '%s\n' "$prompt_line science-based cooking guidance"
  else
    printf '%s\n' "$prompt_line evidence critique alternatives"
    printf '%s\n' "$prompt_line common misconceptions expert discussion"
    printf '%s\n' "$prompt_line forum discussion reddit stackexchange"
  fi
}

gather_search_result_urls_for_query() {
  query_text=$1
  max_results=$2
  [ -n "$query_text" ] || return 0
  case "$max_results" in
    ""|*[!0-9]*)
      max_results=4
      ;;
  esac
  if [ "$max_results" -lt 1 ]; then
    max_results=1
  fi
  if [ "$max_results" -gt 8 ]; then
    max_results=8
  fi

  encoded_query=$(url_encode_component "$query_text")
  [ -n "$encoded_query" ] || return 0
  html=$(curl -LfsS --connect-timeout 4 --max-time 10 "https://duckduckgo.com/html/?q=$encoded_query" 2>/dev/null || true)
  [ -n "$html" ] || return 0

  result_urls=$(printf '%s' "$html" | perl -CS -Mstrict -Mwarnings -e '
    local $/;
    my $raw = <STDIN>;
    $raw = "" if !defined($raw);
    while ($raw =~ m{<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"}gis) {
      print "$1\n";
    }
  ' 2>/dev/null || true)
  if [ -z "$result_urls" ]; then
    result_urls=$(printf '%s' "$html" | perl -CS -Mstrict -Mwarnings -e '
      local $/;
      my $raw = <STDIN>;
      $raw = "" if !defined($raw);
      while ($raw =~ m{<a[^>]*href="([^"]+)"}gis) {
        print "$1\n";
      }
    ' 2>/dev/null || true)
  fi

  count=0
  while IFS= read -r raw_url; do
    [ -n "$raw_url" ] || continue
    normalized_url=$(normalize_search_result_url "$raw_url")
    [ -n "$normalized_url" ] || continue
    if ! printf '%s' "$normalized_url" | grep -Eq '^https?://'; then
      continue
    fi
    printf '%s\n' "$normalized_url"
    count=$((count + 1))
    if [ "$count" -ge "$max_results" ]; then
      break
    fi
  done <<EOF
$result_urls
EOF
}

fetch_url_text_excerpt() {
  source_url=$1
  max_chars=$2
  case "$max_chars" in
    ""|*[!0-9]*)
      max_chars=2200
      ;;
  esac
  if [ "$max_chars" -lt 400 ]; then
    max_chars=400
  fi
  if [ "$max_chars" -gt 8000 ]; then
    max_chars=8000
  fi
  raw=$(curl -LfsS --connect-timeout 4 --max-time 12 "$source_url" 2>/dev/null || true)
  [ -n "$raw" ] || return 0
  text=$(printf '%s' "$raw" | perl -CS -pe '
    s/<script\b[^>]*>.*?<\/script>//gis;
    s/<style\b[^>]*>.*?<\/style>//gis;
    s/<noscript\b[^>]*>.*?<\/noscript>//gis;
    s/<[^>]+>/ /g;
    s/&nbsp;/ /g;
    s/&amp;/&/g;
    s/&lt;/</g;
    s/&gt;/>/g;
    s/\s+/ /g;
  ' | cut -c1-"$max_chars")
  text=$(trim "$text")
  [ -n "$text" ] || return 0
  printf '%s' "$text"
}

fetch_direct_url_context_from_prompt() {
  prompt_text=$1
  max_urls=3
  fetched=0
  urls_file=$(mktemp)
  extract_urls_from_text "$prompt_text" > "$urls_file"
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if [ "$fetched" -ge "$max_urls" ]; then
      break
    fi
    fetched=$((fetched + 1))

    raw=$(curl -LfsS --connect-timeout 3 --max-time 8 "$url" 2>/dev/null || true)
    [ -n "$raw" ] || continue

    text=$(printf '%s' "$raw" | perl -CS -pe '
      s/<script\b[^>]*>.*?<\/script>//gis;
      s/<style\b[^>]*>.*?<\/style>//gis;
      s/<[^>]+>/ /g;
      s/\s+/ /g;
    ' | cut -c1-3500)
    text=$(trim "$text")
    [ -n "$text" ] || continue

    printf 'URL: %s\n%s\n\n' "$url" "$text"
  done < "$urls_file"
  rm -f "$urls_file"
}

fetch_text_perfecter_web_context() {
  prompt_text=$1
  query_cap=4
  source_cap=7
  query_i=0
  fetched_sources=0
  search_urls_file=$(mktemp)
  unique_urls_file=$(mktemp)
  context_file=$(mktemp)

  : > "$search_urls_file"
  : > "$context_file"

  # Keep explicit source links from the user, then widen to broad discovery.
  fetch_direct_url_context_from_prompt "$prompt_text" >> "$context_file"
  extract_urls_from_text "$prompt_text" >> "$search_urls_file"

  while IFS= read -r query_line; do
    query_line=$(trim "$query_line")
    [ -n "$query_line" ] || continue
    query_i=$((query_i + 1))
    if [ "$query_i" -gt "$query_cap" ]; then
      break
    fi
    gather_search_result_urls_for_query "$query_line" 4 >> "$search_urls_file"
  done <<EOF
$(text_perfecter_search_queries_from_prompt "$prompt_text")
EOF

  awk '!seen[$0]++' "$search_urls_file" > "$unique_urls_file"
  while IFS= read -r source_url; do
    source_url=$(trim "$source_url")
    [ -n "$source_url" ] || continue
    if [ "$fetched_sources" -ge "$source_cap" ]; then
      break
    fi
    excerpt=$(fetch_url_text_excerpt "$source_url" 2200)
    [ -n "$excerpt" ] || continue
    fetched_sources=$((fetched_sources + 1))
    printf 'Source: %s\n%s\n\n' "$source_url" "$excerpt" >> "$context_file"
  done < "$unique_urls_file"

  printf '%s' "$(cat "$context_file" | cut -c1-24000)"
  rm -f "$search_urls_file" "$unique_urls_file" "$context_file"
}

fetch_web_context_from_prompt() {
  prompt_text=$1
  run_mode=${2:-auto}

  if [ "$ALLOW_NETWORK" != "1" ] || [ "$ALLOW_WEB" != "1" ]; then
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  direct_context=$(fetch_direct_url_context_from_prompt "$prompt_text")
  if [ "$run_mode" = "text-perfecter" ]; then
    perfecter_context=$(fetch_text_perfecter_web_context "$prompt_text")
    combined_context=$(cat <<EOF
$direct_context
$perfecter_context
EOF
)
    printf '%s' "$(printf '%s' "$combined_context" | awk '!seen[$0]++' | cut -c1-26000)"
    return 0
  fi
  printf '%s' "$direct_context"
}

models_from_api_tags() {
  tags_json=$1

  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$tags_json" | perl -MJSON::PP -e '
      use strict;
      use warnings;
      local $/;
      my $raw = <STDIN>;
      my $data = eval { decode_json($raw) };
      exit 1 if $@ || ref($data) ne "HASH";
      my $models = $data->{models};
      exit 1 if ref($models) ne "ARRAY";
      for my $item (@{$models}) {
        next if ref($item) ne "HASH";
        my $name = $item->{name};
        next if !defined($name) || $name eq "";
        print "$name\n";
      }
    ' 2>/dev/null && return 0
  fi

  printf '%s' "$tags_json" \
    | awk 'BEGIN{RS="\"name\":\"";FS="\""} NR>1 {print $1}' \
    | sed '/^$/d'
}

list_models_raw() {
  host_candidates=$(ollama_host_candidates)

  if command -v curl >/dev/null 2>&1; then
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      tags_json=$(curl -fsS --connect-timeout 3 --max-time 6 "$host/api/tags" 2>/dev/null || true)
      [ -n "$(trim "$tags_json")" ] || continue

      api_models=$(models_from_api_tags "$tags_json" 2>/dev/null || true)
      if [ -n "$(trim "$api_models")" ]; then
        printf '%s\n' "$api_models" | awk '!seen[$0]++'
        return 0
      fi
    done <<EOF
$host_candidates
EOF

  fi

  ollama_bin=$(resolve_ollama_bin || true)
  [ -n "$ollama_bin" ] || return 0

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    OLLAMA_HOST=$host
    export OLLAMA_HOST

    cli_models=$("$ollama_bin" list 2>/dev/null | awk 'NR > 1 { print $1 }' | sed '/^$/d' || true)
    if [ -n "$(trim "$cli_models")" ]; then
      printf '%s\n' "$cli_models" | awk '!seen[$0]++'
      return 0
    fi
  done <<EOF
$host_candidates
EOF

  list_script="$WIZARDRY_DIR/spells/.arcana/ai-dev/list-installed-llms"
  if [ -x "$list_script" ]; then
    fallback_models=$("$list_script" 2>/dev/null || true)
    if [ -n "$(trim "$fallback_models")" ]; then
      printf '%s\n' "$fallback_models" | awk '!seen[$0]++'
      return 0
    fi
  fi
}

list_models_from_workspace_data() {
  for ws_dir in "$workspaces_dir"/*; do
    [ -d "$ws_dir" ] || continue
    conv_parent="$ws_dir/conversations"
    [ -d "$conv_parent" ] || continue
    for conv_dir in "$conv_parent"/*; do
      [ -d "$conv_dir" ] || continue
      model_name=$(read_file_line "$conv_dir/model" "")
      model_name=$(trim "$model_name")
      [ -n "$model_name" ] || continue
      printf '%s\n' "$model_name"
    done
  done | awk '!seen[$0]++'
}

