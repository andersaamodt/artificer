# action: dictate_transcribe_file
    audio_path=$(trim "$(param "audio_path")")
    language=$(trim "$(param "language")")
    model=$(trim "$(param "model")")

    case "$audio_path" in
      ""|*"$nl"*|*"$cr"*)
        emit_error "invalid audio file"
        exit 0
        ;;
    esac
    if [ ! -s "$audio_path" ]; then
      emit_error "No audio was captured."
      exit 0
    fi
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

    model_name=$model
    if [ -z "$model_name" ]; then
      model_name=$(voice_component_model "$backend" || true)
    fi
    if [ -z "$model_name" ]; then
      emit_error "Selected dictation backend model is unavailable."
      exit 0
    fi

    transcribe_out_file=$(mktemp)
    transcribe_err_file=$(mktemp)

    set +e
    transcribe_dictation_audio "$backend" "$model_name" "$language" "$audio_path" "$python_bin" >"$transcribe_out_file" 2>"$transcribe_err_file"
    transcribe_rc=$?
    set -e

    used_backend=$backend
    if [ "$transcribe_rc" -ne 0 ] && [ "$backend" = "mlx-whisper" ] && voice_component_installed "ctranslate2-whisper"; then
      fallback_python=$(voice_component_python_bin "ctranslate2-whisper")
      fallback_model=$(voice_component_model "ctranslate2-whisper" || true)
      if [ -x "$fallback_python" ] && [ -n "$fallback_model" ]; then
        set +e
        transcribe_dictation_audio "ctranslate2-whisper" "$fallback_model" "$language" "$audio_path" "$fallback_python" >"$transcribe_out_file" 2>"$transcribe_err_file"
        transcribe_rc=$?
        set -e
        if [ "$transcribe_rc" -eq 0 ]; then
          used_backend="ctranslate2-whisper"
        fi
      fi
    fi

    transcribe_stdout=$(trim "$(cat "$transcribe_out_file" 2>/dev/null || true)")
    transcribe_stderr=$(strip_terminal_noise "$(cat "$transcribe_err_file" 2>/dev/null || true)")
    rm -f "$transcribe_out_file" "$transcribe_err_file"

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

    printf '{"success":true,"text":"%s","backend":"%s","backend_label":"%s"}\n' \
      "$(json_escape "$transcribe_stdout")" \
      "$(json_escape "$used_backend")" \
      "$(json_escape "$(voice_component_label "$used_backend")")"
    exit 0
