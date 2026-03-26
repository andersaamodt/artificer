# action: queue_update
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    item_id=$(trim "$(param "item_id")")
    prompt_text=$(param "prompt")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if ! valid_id "$item_id"; then
      emit_error "invalid item_id"
      exit 0
    fi
    if [ -z "$(trim "$prompt_text")" ]; then
      emit_error "prompt is required"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    pending_dir=$(queue_pending_dir_for "$conv_dir")
    target_path=$(queue_find_pending_path_by_id "$pending_dir" "$item_id")
    if [ -z "$target_path" ] || [ ! -f "$target_path" ]; then
      emit_error "queued item not found"
      exit 0
    fi

    temp_prompt_file=$(mktemp)
    printf '%s' "$prompt_text" > "$temp_prompt_file"
    mv "$temp_prompt_file" "$target_path"
    printf '%s\n' "queued" > "$queue_dir/last_status"
    date +%s > "$queue_dir/last_done"

    queue_info=$(queue_state_for_conversation "$conv_dir")
    queue_pending=$(kv_get "pending" "$queue_info")
    queue_running=$(kv_get "running" "$queue_info")
    queue_done=$(kv_get "done" "$queue_info")
    queue_first_id=$(kv_get "first_id" "$queue_info")
    queue_last_status=$(kv_get "last_status" "$queue_info")

    [ -n "$queue_pending" ] || queue_pending=0
    [ -n "$queue_running" ] || queue_running=0
    [ -n "$queue_done" ] || queue_done=0

    queue_first_id_json=$(json_escape "$queue_first_id")
    queue_last_status_json=$(json_escape "$queue_last_status")
    item_id_json=$(json_escape "$item_id")
    printf '{"success":true,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$item_id_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
    exit 0
