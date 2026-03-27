# action: ui_state_get
    key_raw=$(trim "$(param "key")")
    key=$(ui_state_key_canonical "$key_raw" || true)
    if [ -z "$key" ]; then
      emit_error "invalid key"
      exit 0
    fi
    value=$(ui_state_read_value_for_key "$key")
    printf '{"success":true,"key":"%s","value":"%s"}\n' "$(json_escape "$key")" "$(json_escape "$value")"
    exit 0
