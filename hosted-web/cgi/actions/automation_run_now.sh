# action: automation_run_now
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
    enqueue_result=$(automation_enqueue_prompt_for_run "$automation_id" "1")
    if [ "$(kv_get "success" "$enqueue_result")" != "1" ]; then
      emit_error "$(kv_get "error" "$enqueue_result")"
      exit 0
    fi
    printf '{"success":true,"automation_id":"%s","workspace_id":"%s","conversation_id":"%s","item_id":"%s","automation":%s,"automations":%s}\n' \
      "$(json_escape "$automation_id")" \
      "$(json_escape "$(kv_get "workspace_id" "$enqueue_result")")" \
      "$(json_escape "$(kv_get "conversation_id" "$enqueue_result")")" \
      "$(json_escape "$(kv_get "item_id" "$enqueue_result")")" \
      "$(automation_json_for_id "$automation_id")" \
      "$(automations_state_json)"
    exit 0
