# action: improvement_proposal_decide
    if command -v mr_improvement_proposal_decide_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_improvement_proposal_decide_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
