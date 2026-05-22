# action: mode_runtime_skill_invoke
    if command -v mr_mode_runtime_skill_invoke_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_mode_runtime_skill_invoke_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
