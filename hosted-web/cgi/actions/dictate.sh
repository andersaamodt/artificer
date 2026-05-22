# action: dictate
    dictate_bin=$(resolve_dictate_bin || true)
    if [ -z "$dictate_bin" ]; then
      emit_error "Voice recognition is unavailable because the dictate spell was not found."
      exit 0
    fi

    duration=$(trim "$(param "duration")")
    language=$(trim "$(param "language")")
    model=$(trim "$(param "model")")
    timeout_sec=$(trim "$(param "timeout_sec")")
    active_backend=$(installed_voice_backend_for_host || true)
    if [ -z "$active_backend" ]; then
      active_backend=$(preferred_voice_component_for_host || true)
    fi

    if [ -n "$duration" ]; then
      case "$duration" in
        *[!0-9]*)
          emit_error "invalid duration"
          exit 0
          ;;
      esac
      if [ "$duration" -lt 1 ] || [ "$duration" -gt 600 ]; then
        emit_error "duration must be between 1 and 600 seconds"
        exit 0
      fi
    fi

    normalized_language=$(normalize_dictation_language_value "$language")
    if [ -z "$normalized_language" ]; then
      emit_error "invalid language"
      exit 0
    fi
    if ! dictation_language_allowed_for_backend "$active_backend" "$normalized_language"; then
      emit_error "invalid language"
      exit 0
    fi
    if [ "$normalized_language" = "auto" ]; then
      language=""
    else
      language=$normalized_language
    fi

    if [ -n "$model" ] && ! safe_model_name "$model"; then
      emit_error "invalid model"
      exit 0
    fi

    if [ -z "$timeout_sec" ]; then
      timeout_sec=180
    fi

    set -- "$dictate_bin"
    if [ -n "$duration" ]; then
      set -- "$@" "--duration" "$duration"
    fi
    if [ -n "$language" ]; then
      set -- "$@" "--language" "$language"
    fi
    if [ -n "$model" ]; then
      set -- "$@" "--model" "$model"
    fi

    dictate_output_file=$(mktemp)
    dictate_error_file=$(mktemp)

    set +e
    if [ "$active_backend" = "mlx-whisper" ] && voice_needs_macos_arm64_uname_override; then
      if voice_can_run_arch_arm64; then
        run_with_timeout "$timeout_sec" arch -arm64 "$@" > "$dictate_output_file" 2> "$dictate_error_file"
        dictate_rc=$?
      else
        printf '%s\n' "voice-recognition: native arm64 execution is unavailable" > "$dictate_error_file"
        dictate_rc=126
      fi
    else
      run_with_timeout "$timeout_sec" "$@" > "$dictate_output_file" 2> "$dictate_error_file"
      dictate_rc=$?
    fi
    set -e

    dictate_stdout=$(cat "$dictate_output_file" 2>/dev/null || true)
    dictate_stderr=$(strip_terminal_noise "$(cat "$dictate_error_file" 2>/dev/null || true)")
    rm -f "$dictate_output_file" "$dictate_error_file"

    if [ "$dictate_rc" -ne 0 ]; then
      if [ "$dictate_rc" -eq 124 ]; then
        emit_error "Dictation timed out."
      elif [ -n "$dictate_stderr" ]; then
        emit_error "$dictate_stderr"
      else
        emit_error "Dictation failed."
      fi
      exit 0
    fi

    dictated_text=$(trim "$dictate_stdout")
    printf '{"success":true,"text":"%s"}\n' "$(json_escape "$dictated_text")"
    exit 0
