# action: dictate_levels
    requested_session_id=$(trim "$(param "session_id")")
    if ! dictation_live_has_active_capture; then
      printf '{"success":true,"level":"0","levels":[]}\n'
      exit 0
    fi
    session_id=$(dictation_live_session_value "id")
    if [ -n "$requested_session_id" ] && [ "$requested_session_id" != "$session_id" ]; then
      printf '{"success":true,"level":"0","levels":[]}\n'
      exit 0
    fi
    level=$(dictation_live_level_for_session)
    levels_json=$(dictation_live_levels_json_for_session)
    [ -n "$levels_json" ] || levels_json="[]"
    printf '{"success":true,"level":"%s","session_id":"%s","levels":%s}\n' \
      "$(json_escape "$level")" \
      "$(json_escape "$session_id")" \
      "$levels_json"
    exit 0
