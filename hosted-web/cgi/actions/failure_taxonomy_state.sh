# action: failure_taxonomy_state
    if command -v mr_failure_taxonomy_state_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_failure_taxonomy_state_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
