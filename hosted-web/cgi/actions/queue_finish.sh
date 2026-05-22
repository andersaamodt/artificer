# action: queue_finish
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    item_id=$(trim "$(param "item_id")")
    finish_status=$(trim "$(param "status")")
    finish_error=$(param "error")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    case "$finish_status" in
      done|error|cancelled|awaiting_decision|awaiting_approval) ;;
      *)
        finish_status="done"
        ;;
    esac

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    running_meta_file=$(queue_running_meta_file_for "$conv_dir")
    running_automation_id=$(queue_meta_automation_id_from_file "$running_meta_file")
    automation_finish_dir=""
    if valid_id "$running_automation_id"; then
      automation_finish_dir=$(automation_dir_for "$running_automation_id")
    fi

    queue_clear_running_state "$conv_dir"
    printf '%s\n' "$finish_status" > "$queue_dir/last_status"
    if [ "$finish_status" != "awaiting_approval" ]; then
      clear_approval_request "$conv_dir"
    fi
    if [ "$finish_status" = "error" ]; then
      printf '%s\n' "$finish_error" > "$queue_dir/last_error"
    else
      rm -f "$queue_dir/last_error"
    fi
    date +%s > "$queue_dir/last_done"

    if [ -n "$automation_finish_dir" ] && [ -d "$automation_finish_dir" ]; then
      automation_finish_epoch=$(automation_now_epoch)
      printf '%s\n' "$finish_status" > "$(automation_field_file_for "$automation_finish_dir" "last_status")"
      if [ "$finish_status" = "error" ]; then
        printf '%s\n' "$finish_error" > "$(automation_field_file_for "$automation_finish_dir" "last_error")"
      else
        printf '%s\n' "" > "$(automation_field_file_for "$automation_finish_dir" "last_error")"
      fi
      printf '%s\n' "$automation_finish_epoch" > "$(automation_field_file_for "$automation_finish_dir" "updated")"
      if [ "$finish_status" = "done" ]; then
        automation_apply_self_reschedule_for_conversation "$running_automation_id" "$conv_dir"
      fi
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

    printf '{"success":true,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$item_id_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
    exit 0
