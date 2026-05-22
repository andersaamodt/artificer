# action: model_uninstall
    model_name=$(trim "$(param "model")")
    if ! safe_model_name "$model_name"; then
      emit_error "invalid model name"
      exit 0
    fi

    uninstall_output=""
    uninstall_rc=1

    run_ai_dev_uninstall_script="$AI_DEV_DIR/uninstall-llm"
    if [ -x "$run_ai_dev_uninstall_script" ]; then
      set +e
      uninstall_output=$(run_ai_dev_script uninstall-llm "$model_name" 2>&1)
      uninstall_rc=$?
      set -e
    fi

    if [ "$uninstall_rc" -ne 0 ]; then
      ollama_bin=$(resolve_ollama_bin || true)
      if [ -z "$ollama_bin" ]; then
        emit_error "Ollama is not available for uninstall"
        exit 0
      fi
      set +e
      uninstall_output=$("$ollama_bin" rm "$model_name" 2>&1)
      uninstall_rc=$?
      set -e
    fi

    if [ "$uninstall_rc" -ne 0 ]; then
      error_message=$(trim "$(strip_terminal_noise "$uninstall_output")")
      [ -n "$error_message" ] || error_message="Failed to uninstall model"
      emit_error "$error_message"
      exit 0
    fi

    printf '{"success":true,"model":"%s","output":"%s"}\n' \
      "$(json_escape "$model_name")" \
      "$(json_escape "$uninstall_output")"
    exit 0
