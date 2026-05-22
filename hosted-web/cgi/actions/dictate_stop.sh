# action: dictate_stop
    requested_session_id=$(trim "$(param "session_id")")
    session_dir=$(dictation_live_session_dir)
    if [ ! -d "$session_dir" ]; then
      emit_error "No active dictation session."
      exit 0
    fi

    session_id=$(dictation_live_session_value "id")
    capture_pid=$(dictation_live_session_value "pid")
    audio_file=$(dictation_live_session_value "audio_file")
    backend=$(dictation_live_session_value "backend")
    model_name=$(dictation_live_session_value "model")
    language=$(dictation_live_session_value "language")
    python_bin=$(dictation_live_session_value "python_bin")
    session_status=$(dictation_live_status)
    started_ms=$(dictation_live_session_value "started_ms")
    capture_started_ms=$(dictation_live_session_value "capture_started_ms")

    if [ -n "$requested_session_id" ] && [ -n "$session_id" ] && [ "$requested_session_id" != "$session_id" ]; then
      emit_error "Dictation session changed. Start dictation again."
      exit 0
    fi
    if [ "$session_status" != "recording" ]; then
      emit_error "No active dictation session."
      exit 0
    fi

    stop_capture_pid_gracefully "$capture_pid" >/dev/null 2>&1 || true
    sleep 0.1

    wait_for_audio_capture_file "$audio_file" "1400" || true
    if [ -z "$audio_file" ] || [ ! -s "$audio_file" ]; then
      capture_log=$(strip_terminal_noise "$(cat "$session_dir/capture.log" 2>/dev/null || true)")
      clear_dictation_live_session
      if [ -n "$capture_log" ]; then
        emit_error "$capture_log"
      else
        emit_error "No audio was captured."
      fi
      exit 0
    fi

    if [ -z "$backend" ] || [ -z "$model_name" ] || [ -z "$python_bin" ]; then
      clear_dictation_live_session
      emit_error "Dictation session metadata is incomplete."
      exit 0
    fi

    transcribe_out_file=$(mktemp)
    transcribe_err_file=$(mktemp)
    transcribe_audio_file="$audio_file"
    trimmed_audio_file=""
    case "$started_ms" in
      *[!0-9]*|"") started_ms=0 ;;
    esac
    case "$capture_started_ms" in
      *[!0-9]*|"") capture_started_ms=0 ;;
    esac
    if [ "$started_ms" -gt "$capture_started_ms" ] && [ "$capture_started_ms" -gt 0 ]; then
      offset_ms=$((started_ms - capture_started_ms))
      if [ "$offset_ms" -gt 20 ]; then
        offset_sec=$(awk -v ms="$offset_ms" 'BEGIN { printf "%.3f", (ms / 1000.0) }')
        trimmed_audio_file=$(mktemp "/tmp/artificer-dictation-trim.XXXXXX.wav")
        if ffmpeg -nostdin -hide_banner -loglevel error -ss "$offset_sec" -i "$audio_file" -ac 1 -ar 16000 -f wav -y "$trimmed_audio_file" >/dev/null 2>&1; then
          if [ -s "$trimmed_audio_file" ]; then
            transcribe_audio_file="$trimmed_audio_file"
          fi
        fi
      fi
    fi

    set +e
    transcribe_dictation_audio "$backend" "$model_name" "$language" "$transcribe_audio_file" "$python_bin" >"$transcribe_out_file" 2>"$transcribe_err_file"
    transcribe_rc=$?
    set -e

    used_backend=$backend
    if [ "$transcribe_rc" -ne 0 ] && [ "$backend" = "mlx-whisper" ] && voice_component_installed "ctranslate2-whisper"; then
      fallback_python=$(voice_component_python_bin "ctranslate2-whisper")
      fallback_model=$(voice_component_model "ctranslate2-whisper" || true)
      if [ -x "$fallback_python" ] && [ -n "$fallback_model" ]; then
        set +e
        transcribe_dictation_audio "ctranslate2-whisper" "$fallback_model" "$language" "$transcribe_audio_file" "$fallback_python" >"$transcribe_out_file" 2>"$transcribe_err_file"
        transcribe_rc=$?
        set -e
        if [ "$transcribe_rc" -eq 0 ]; then
          used_backend="ctranslate2-whisper"
        fi
      fi
    fi

    transcribe_stdout=$(trim "$(cat "$transcribe_out_file" 2>/dev/null || true)")
    transcribe_stderr=$(strip_terminal_noise "$(cat "$transcribe_err_file" 2>/dev/null || true)")
    rm -f "$trimmed_audio_file" 2>/dev/null || true
    rm -f "$transcribe_out_file" "$transcribe_err_file"
    clear_dictation_live_session

    if [ "$transcribe_rc" -ne 0 ]; then
      transcribe_error_lower=$(printf '%s' "$transcribe_stderr" | tr '[:upper:]' '[:lower:]')
      if [ "$used_backend" = "mlx-whisper" ] && printf '%s' "$transcribe_error_lower" | grep -Fq "load_npz"; then
        remove_voice_component_artifacts "mlx-whisper" >/dev/null 2>&1 || true
        emit_error "Dictation model files were corrupted and have been cleared. Reinstall dictation and try again."
        exit 0
      fi
      if [ -n "$transcribe_stderr" ]; then
        emit_error "$transcribe_stderr"
      else
        emit_error "Dictation transcription failed."
      fi
      exit 0
    fi

    if [ -z "$transcribe_stdout" ]; then
      emit_error "No speech detected"
      exit 0
    fi

    printf '{"success":true,"session_id":"%s","text":"%s","backend":"%s","backend_label":"%s"}\n' \
      "$(json_escape "$session_id")" \
      "$(json_escape "$transcribe_stdout")" \
      "$(json_escape "$used_backend")" \
      "$(json_escape "$(voice_component_label "$used_backend")")"
    exit 0
