# action: approval_answer
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    decision=$(trim "$(param "decision")")
    scope=$(trim "$(param "scope")")
    match_mode=$(trim "$(param "match_mode")")
    pattern=$(normalize_rule_field "$(param "pattern")")
    command_text=$(normalize_rule_field "$(param "command")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi
    case "$decision" in
      allow|deny) ;;
      *) emit_error "invalid decision"; exit 0 ;;
    esac
    case "$scope" in
      once|remember) ;;
      *) scope="once" ;;
    esac
    case "$match_mode" in
      exact|regex) ;;
      *) match_mode="exact" ;;
    esac

    if [ -z "$command_text" ]; then
      command_text=$(trim "$(read_file_line "$(approval_request_command_file_for "$conv_dir")" "")")
    fi
    if [ -n "$command_text" ]; then
      if [ "$match_mode" = "exact" ]; then
        pattern=$command_text
      fi
      if [ "$match_mode" = "regex" ] && [ -z "$pattern" ]; then
        pattern=$(command_text_to_rule_pattern_default "$command_text")
      fi
      append_command_rule "$workspace_id" "$scope" "$decision" "$match_mode" "$pattern"
    else
      if [ "$scope" = "remember" ]; then
        emit_error "no pending command approval"
        exit 0
      fi
    fi

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    clear_approval_request "$conv_dir"

    if [ "$decision" = "deny" ]; then
      printf '%s\n' "cancelled" > "$queue_dir/last_status"
      rm -f "$queue_dir/last_error"
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
      printf '{"success":true,"item_id":"","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s","approval_request":null}\n' \
        "$queue_pending" "$queue_running" "$queue_done" "$(json_escape "$queue_first_id")" "$(json_escape "$queue_last_status")"
      exit 0
    fi

    retry_prompt=$(latest_user_message_for_conversation "$conv_dir")
    retry_prompt=$(trim "$retry_prompt")
    if [ -z "$retry_prompt" ]; then
      emit_error "no user prompt available to retry"
      exit 0
    fi

    item_id=$(new_id)
    order=$(queue_allocate_order "$conv_dir" "head")
    queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
    printf '%s' "$retry_prompt" > "$queue_item_file"
    rm -f "$(queue_item_meta_for_path "$queue_item_file")"
    printf '%s\n' "queued" > "$queue_dir/last_status"
    rm -f "$queue_dir/last_error"
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

    printf '{"success":true,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s","approval_request":null}\n' \
      "$(json_escape "$item_id")" "$queue_pending" "$queue_running" "$queue_done" "$(json_escape "$queue_first_id")" "$(json_escape "$queue_last_status")"
    exit 0
