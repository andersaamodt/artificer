# action: mode_runtime_skill_create
    if command -v mr_mode_runtime_skill_create_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_mode_runtime_skill_create_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
