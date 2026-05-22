# action: failure_taxonomy_query
    if command -v mr_failure_taxonomy_query_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_failure_taxonomy_query_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
