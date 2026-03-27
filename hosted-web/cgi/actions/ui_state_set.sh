# action: ui_state_set
    key_raw=$(trim "$(param "key")")
    value_raw=$(param "value")
    key=$(ui_state_key_canonical "$key_raw" || true)
    if [ -z "$key" ]; then
      emit_error "invalid key"
      exit 0
    fi
    if ! ui_state_write_value_for_key "$key" "$value_raw"; then
      emit_error "failed to persist value"
      exit 0
    fi
    printf '{"success":true,"key":"%s"}\n' "$(json_escape "$key")"
    exit 0
