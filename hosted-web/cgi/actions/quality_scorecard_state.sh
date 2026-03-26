# action: quality_scorecard_state
    if command -v mr_quality_scorecard_state_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_quality_scorecard_state_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
