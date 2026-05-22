# action: mode_runtime_update
    if command -v mr_mode_update_json >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_mode_update_json
      printf '\n'
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
