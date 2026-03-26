# action: dictate_prepare
    language=$(trim "$(param "language")")
    model=$(trim "$(param "model")")

    if [ -n "$model" ] && ! safe_model_name "$model"; then
      emit_error "invalid model"
      exit 0
    fi

    backend=$(installed_voice_backend_for_host || true)
    if [ -z "$backend" ]; then
      emit_error "No dictation backend is installed."
      exit 0
    fi

    python_bin=$(voice_component_python_bin "$backend")
    if [ ! -x "$python_bin" ]; then
      emit_error "Selected dictation backend runtime is unavailable."
      exit 0
    fi

    normalized_language=$(normalize_dictation_language_value "$language")
    if [ -z "$normalized_language" ]; then
      emit_error "invalid language"
      exit 0
    fi
    if ! dictation_language_allowed_for_backend "$backend" "$normalized_language"; then
      emit_error "invalid language"
      exit 0
    fi
    if [ "$normalized_language" = "auto" ]; then
      language=""
    else
      language=$normalized_language
    fi

    session_dir=$(dictation_live_session_dir)
    if dictation_live_has_active_capture; then
      existing_id=$(dictation_live_session_value "id")
      existing_status=$(dictation_live_status)
      [ -n "$existing_status" ] || existing_status="prepared"
      if [ "$existing_status" != "prepared" ] && [ "$existing_status" != "recording" ]; then
        existing_status="prepared"
      fi
      if [ -z "$existing_id" ]; then
        existing_id=$(new_id)
        printf '%s\n' "$existing_id" > "$session_dir/id"
      fi
      existing_backend=$(dictation_live_session_value "backend")
      [ -n "$existing_backend" ] || existing_backend="$backend"
      printf '%s\n' "$language" > "$session_dir/language"
      if [ -n "$model" ]; then
        printf '%s\n' "$model" > "$session_dir/model"
      fi
      printf '{"success":true,"session":{"id":"%s","status":"%s","backend":"%s"}}\n' \
        "$(json_escape "$existing_id")" \
        "$(json_escape "$existing_status")" \
        "$(json_escape "$existing_backend")"
      exit 0
    fi

    clear_dictation_live_session
    mkdir -p "$session_dir"

    session_id=$(new_id)
    audio_file="$session_dir/audio.wav"
    levels_file="$session_dir/levels.log"
    log_file="$session_dir/capture.log"
    runner_script="$session_dir/capture.sh"
    model_name=$model
    if [ -z "$model_name" ]; then
      model_name=$(voice_component_model "$backend" || true)
    fi
    if [ -z "$model_name" ]; then
      clear_dictation_live_session
      emit_error "Selected dictation backend model is unavailable."
      exit 0
    fi

    cat > "$runner_script" <<'EOF'
#!/bin/sh
set -eu
audio_file=$1
log_file=$2
levels_file=$3
os_name=$(uname -s 2>/dev/null || printf 'unknown')

case "$os_name" in
  Darwin)
    exec ffmpeg -nostdin -hide_banner -loglevel error \
      -probesize 32 -analyzeduration 0 -fflags nobuffer -flags low_delay \
      -f avfoundation -i ":0" -t "${DICTATION_MAX_RECORDING_SECONDS:-600}" \
      -af "astats=metadata=1:reset=1,ametadata=mode=print:file=$levels_file" \
      -ac 1 -ar 16000 -f wav -y "$audio_file" >>"$log_file" 2>&1
    ;;
  Linux)
    if ffmpeg -nostdin -hide_banner -loglevel error \
      -probesize 32 -analyzeduration 0 -fflags nobuffer -flags low_delay \
      -f pulse -i default -t "${DICTATION_MAX_RECORDING_SECONDS:-600}" \
      -af "astats=metadata=1:reset=1,ametadata=mode=print:file=$levels_file" \
      -ac 1 -ar 16000 -f wav -y "$audio_file" >>"$log_file" 2>&1; then
      :
    else
      ffmpeg -nostdin -hide_banner -loglevel error \
      -probesize 32 -analyzeduration 0 -fflags nobuffer -flags low_delay \
        -f alsa -i default -t "${DICTATION_MAX_RECORDING_SECONDS:-600}" \
        -af "astats=metadata=1:reset=1,ametadata=mode=print:file=$levels_file" \
        -ac 1 -ar 16000 -f wav -y "$audio_file" >>"$log_file" 2>&1
    fi
    ;;
  *)
    printf '%s\n' "Unsupported platform for dictation capture: $os_name" >>"$log_file"
    exit 1
    ;;
esac
EOF
    chmod +x "$runner_script"

    capture_pid=$(spawn_detached_job "$runner_script" "$audio_file" "$log_file" "$levels_file")
    sleep 0.005
    if ! kill -0 "$capture_pid" 2>/dev/null; then
      capture_error=$(strip_terminal_noise "$(cat "$log_file" 2>/dev/null || true)")
      clear_dictation_live_session
      [ -n "$capture_error" ] || capture_error="Microphone capture failed to start."
      emit_error "$capture_error"
      exit 0
    fi

    capture_started_ms=$(current_time_millis)
    printf '%s\n' "$session_id" > "$session_dir/id"
    printf '%s\n' "$capture_pid" > "$session_dir/pid"
    printf '%s\n' "$audio_file" > "$session_dir/audio_file"
    printf '%s\n' "$levels_file" > "$session_dir/levels_file"
    printf '%s\n' "$backend" > "$session_dir/backend"
    printf '%s\n' "$model_name" > "$session_dir/model"
    printf '%s\n' "$language" > "$session_dir/language"
    printf '%s\n' "$python_bin" > "$session_dir/python_bin"
    printf '%s\n' "$capture_started_ms" > "$session_dir/capture_started_ms"
    printf '%s\n' "0" > "$session_dir/started_ms"
    printf '%s\n' "prepared" > "$session_dir/status"
    arm_dictation_prepare_guard "$session_dir" "$capture_pid"

    printf '{"success":true,"session":{"id":"%s","status":"prepared","backend":"%s","backend_label":"%s"}}\n' \
      "$(json_escape "$session_id")" \
      "$(json_escape "$backend")" \
      "$(json_escape "$(voice_component_label "$backend")")"
    exit 0
