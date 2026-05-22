# action: controller_variant_rollback
    if command -v mr_controller_variant_rollback_response >/dev/null 2>&1; then
      ensure_mode_runtime_bootstrap
      mr_controller_variant_rollback_response
    else
      emit_error "mode runtime is unavailable"
    fi
    exit 0
