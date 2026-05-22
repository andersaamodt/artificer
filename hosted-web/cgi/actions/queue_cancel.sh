# action: queue_cancel
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    item_id=$(trim "$(param "item_id")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -n "$item_id" ] && ! valid_id "$item_id"; then
      emit_error "invalid item_id"
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

    target_path=""
    if [ -n "$item_id" ]; then
      target_path=$(queue_find_pending_path_by_id "$pending_dir" "$item_id")
    else
      target_path=$(queue_first_pending_path "$pending_dir")
      if [ -n "$target_path" ]; then
        item_id=$(queue_item_id_from_path "$target_path")
      fi
    fi

    cancelled=0
    if [ -n "$target_path" ] && [ -f "$target_path" ]; then
      target_meta=$(queue_item_meta_for_path "$target_path")
      rm -f "$target_path"
      rm -f "$target_meta"
      cancelled=1
      printf '%s\n' "cancelled" > "$queue_dir/last_status"
      date +%s > "$queue_dir/last_done"
    fi

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

    if [ "$cancelled" -eq 1 ]; then
      cancelled_json=true
    else
      cancelled_json=false
    fi

    printf '{"success":true,"cancelled":%s,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$cancelled_json" "$item_id_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
    exit 0
