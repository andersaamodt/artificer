# action: improvement_proposal_create
    if command -v mr_improvement_proposal_create_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_improvement_proposal_create_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
