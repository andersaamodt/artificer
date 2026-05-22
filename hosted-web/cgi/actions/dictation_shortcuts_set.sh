# action: dictation_shortcuts_set
    hold_value=$(param "hold")
    toggle_value=$(param "toggle")
    dictation_shortcuts_set_values "$hold_value" "$toggle_value"
    dictation_shortcuts_get_json
    exit 0
