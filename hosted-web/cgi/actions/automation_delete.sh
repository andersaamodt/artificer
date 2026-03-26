# action: automation_delete
    automation_id=$(trim "$(param "automation_id")")
    if ! valid_id "$automation_id"; then
      emit_error "invalid automation_id"
      exit 0
    fi
    automation_dir=$(automation_dir_for "$automation_id")
    if [ ! -d "$automation_dir" ]; then
      emit_error "automation not found"
      exit 0
    fi
    rm -rf "$automation_dir" "$(automation_runtime_dir_for "$automation_id")"
    printf '{"success":true,"automations":%s}\n' "$(automations_state_json)"
    exit 0
