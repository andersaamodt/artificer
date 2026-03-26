# action: dictation_install_start
    if ! acquire_dictation_job_lock "2000"; then
      emit_error "Dictation install is busy. Try again."
      exit 0
    fi
    preferred_component=$(preferred_voice_component_for_host)
    fallback_component="ctranslate2-whisper"
    install_component=$preferred_component
    primary_bin=$(resolve_voice_recognition_install_bin "$install_component" || true)
    if [ -z "$primary_bin" ]; then
      install_component=$fallback_component
      primary_bin=$(resolve_voice_recognition_install_bin "$install_component" || true)
    fi
    if [ -z "$primary_bin" ]; then
      release_dictation_job_lock
      emit_error "Voice recognition installer is unavailable."
      exit 0
    fi

    fallback_bin=""
    if [ "$install_component" != "$fallback_component" ]; then
      fallback_bin=$(resolve_voice_recognition_install_bin "$fallback_component" || true)
    fi
    force_macos_arm64_uname=0
    if [ "$install_component" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
      force_macos_arm64_uname=1
    fi

    for existing_job in "$dictation_installs_dir"/*; do
      [ -d "$existing_job" ] || continue
      running_status=$(read_file_line "$existing_job/status" "")
      running_pid=$(read_file_line "$existing_job/pid" "")
      if [ "$running_status" = "running" ] && [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
        running_phase=$(read_file_line "$existing_job/phase_last" "downloading")
        release_dictation_job_lock
        printf '{"success":true,"job":{"id":"%s","status":"running","action":"install","phase":"%s","component":"%s","fallback_component":"%s","download_size_bytes":"%s"}}\n' \
          "$(json_escape "$(basename "$existing_job")")" \
          "$(json_escape "$running_phase")" \
          "$(json_escape "$(read_file_line "$existing_job/component" "$install_component")")" \
          "$(json_escape "$(read_file_line "$existing_job/fallback_component" "$fallback_component")")" \
          "$(json_escape "$(read_file_line "$existing_job/download_size_bytes" "")")"
        exit 0
      fi
    done

    if ! remove_voice_component_artifacts "$install_component"; then
      release_dictation_job_lock
      emit_error "Could not clear previous dictation data before install."
      exit 0
    fi
    if ! remove_voice_download_cache; then
      release_dictation_job_lock
      emit_error "Could not clear previous dictation download cache before install."
      exit 0
    fi

    job_id=$(new_id)
    job_dir="$dictation_installs_dir/$job_id"
    mkdir -p "$job_dir"
    log_file="$job_dir/log"
    download_size_bytes=$(voice_component_download_size_bytes "$install_component")
    live_download_size_bytes=$(voice_component_download_size_bytes_from_web "$install_component")
    case "$live_download_size_bytes" in
      *[!0-9]*|"")
        :
        ;;
      *)
        if [ "$live_download_size_bytes" -gt 0 ] 2>/dev/null; then
          download_size_bytes=$live_download_size_bytes
        fi
        ;;
    esac

    printf '%s\n' "$install_component" > "$job_dir/component"
    printf '%s\n' "$fallback_component" > "$job_dir/fallback_component"
    printf '%s\n' "$download_size_bytes" > "$job_dir/download_size_bytes"
    printf '%s\n' "$(voice_component_download_usage_bytes "$install_component")" > "$job_dir/download_bytes_start"
    printf '%s\n' "running" > "$job_dir/status"
    date +%s > "$job_dir/started"

    runner_script="$job_dir/run-install.sh"
    cat >"$runner_script" <<'EOF_RUNNER'
#!/bin/sh
set -eu
job_dir=$1
log_file=$2
component=$3
component_bin=$4
fallback_component=$5
fallback_bin=$6
timeout_sec=$7
force_macos_arm64_uname=$8
voice_root_dir=$9

run_with_timeout_compat() {
  duration=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$duration" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$duration" "$@"
    return $?
  fi
  "$@"
}

component_install_state_ok() {
  root_dir=$1
  component_name=$2
  if [ -z "$root_dir" ] || [ -z "$component_name" ]; then
    return 1
  fi
  state_file="$root_dir/$component_name/installed"
  python_bin="$root_dir/$component_name/venv/bin/python"
  [ -f "$state_file" ] && [ -x "$python_bin" ]
}

install_rc=1
installed_component=$component
fallback_used=0

printf '%s\n' "voice-recognition: starting $component install" >"$log_file"
set +e
if [ "$force_macos_arm64_uname" = "1" ] && [ "$component" = "mlx-whisper" ]; then
  if command -v arch >/dev/null 2>&1 && arch -arm64 /usr/bin/true >/dev/null 2>&1; then
    run_with_timeout_compat "$timeout_sec" arch -arm64 "$component_bin" >>"$log_file" 2>&1
  else
    printf '%s\n' "voice-recognition: native arm64 execution is unavailable" >>"$log_file"
    install_rc=126
  fi
else
  run_with_timeout_compat "$timeout_sec" "$component_bin" >>"$log_file" 2>&1
fi
if [ "${install_rc-}" != "126" ]; then
  install_rc=$?
fi

if [ "$install_rc" -ne 0 ] && [ "$component" != "$fallback_component" ] && [ -n "$fallback_bin" ] && [ -x "$fallback_bin" ]; then
  printf '%s\n' "voice-recognition: falling back to $fallback_component" >>"$log_file"
  run_with_timeout_compat "$timeout_sec" "$fallback_bin" >>"$log_file" 2>&1
  fallback_rc=$?
  if [ "$fallback_rc" -eq 0 ]; then
    install_rc=0
    installed_component=$fallback_component
    fallback_used=1
  else
    install_rc=$fallback_rc
  fi
fi
set -e

if [ "$install_rc" -eq 0 ]; then
  if ! component_install_state_ok "$voice_root_dir" "$installed_component"; then
    printf '%s\n' "voice-recognition: install verification failed for $installed_component" >>"$log_file"
    install_rc=1
  fi
fi

current_status=$(cat "$job_dir/status" 2>/dev/null || printf '')
if [ "$current_status" = "cancelled" ]; then
  [ -f "$job_dir/finished" ] || date +%s > "$job_dir/finished"
  exit 0
fi

printf '%s\n' "$install_rc" > "$job_dir/exit_code"
printf '%s\n' "$installed_component" > "$job_dir/installed_component"
printf '%s\n' "$fallback_used" > "$job_dir/fallback_used"

selected_backend=$installed_component
printf '%s\n' "$selected_backend" > "$job_dir/backend"

if [ "$install_rc" -eq 0 ]; then
  printf '%s\n' "done" > "$job_dir/status"
else
  printf '%s\n' "failed" > "$job_dir/status"
fi
date +%s > "$job_dir/finished"
EOF_RUNNER
    chmod +x "$runner_script"

    install_pid=$(spawn_detached_job "$runner_script" "$job_dir" "$log_file" "$install_component" "$primary_bin" "$fallback_component" "$fallback_bin" "1800" "$force_macos_arm64_uname" "$VOICE_RECOGNITION_ROOT_DIR")
    printf '%s\n' "$install_pid" > "$job_dir/pid"

    printf '{"success":true,"job":{"id":"%s","status":"running","action":"install","phase":"downloading","component":"%s","fallback_component":"%s","download_size_bytes":"%s"}}\n' \
      "$(json_escape "$job_id")" \
      "$(json_escape "$install_component")" \
      "$(json_escape "$fallback_component")" \
      "$(json_escape "$download_size_bytes")"
    release_dictation_job_lock
    exit 0
