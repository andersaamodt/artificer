# action: dictation_uninstall
    removed_any=0
    removed_json=""
    backend_after=""
    for component in mlx-whisper parakeet ctranslate2-whisper; do
      if ! voice_component_installed "$component"; then
        continue
      fi

      uninstall_bin=$(resolve_voice_recognition_uninstall_bin "$component" || true)
      if [ -z "$uninstall_bin" ]; then
        emit_error "Voice recognition uninstall tool is unavailable."
        exit 0
      fi

      set +e
      if [ "$component" = "mlx-whisper" ]; then
        uninstall_output=$(run_with_macos_arm64_context "$uninstall_bin" 2>&1)
      else
        uninstall_output=$("$uninstall_bin" 2>&1)
      fi
      uninstall_rc=$?
      set -e

      if [ "$uninstall_rc" -ne 0 ]; then
        uninstall_output=$(strip_terminal_noise "$uninstall_output")
        if [ -n "$uninstall_output" ]; then
          emit_error "$uninstall_output"
        else
          emit_error "Dictation uninstall failed."
        fi
        exit 0
      fi

      if [ "$removed_any" -eq 1 ]; then
        removed_json="$removed_json,"
      fi
      removed_any=1
      removed_json="$removed_json\"$(json_escape "$component")\""
    done

    if ! remove_voice_runtime_root; then
      emit_error "Dictation uninstall could not remove local voice-recognition data."
      exit 0
    fi
    if ! remove_voice_download_cache; then
      emit_error "Dictation uninstall could not remove voice download cache."
      exit 0
    fi

    backend_after=$(installed_voice_backend_for_host || true)

    printf '{"success":true,"removed":[%s],"backend":"%s"}\n' \
      "$removed_json" \
      "$(json_escape "$backend_after")"
    exit 0
