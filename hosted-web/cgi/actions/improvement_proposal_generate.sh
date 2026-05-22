# action: improvement_proposal_generate
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")

    if [ -z "$workspace_id" ] || ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if [ -z "$conversation_id" ] || ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi
    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    if command -v mr_improvement_proposal_generate_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_improvement_proposal_generate_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
