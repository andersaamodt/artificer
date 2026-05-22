# action: assay_inject_decision_request
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    question_text=$(trim "$(param "question")")
    options_text=$(param "options")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -z "$question_text" ]; then
      emit_error "question is required"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    options_file=$(mktemp)
    if [ -n "$(trim "$options_text")" ]; then
      printf '%s' "$options_text" | tr '|\r' '\n\n' > "$options_file"
    else
      {
        printf '%s\n' "Proceed now"
        printf '%s\n' "Proceed with safeguards first"
        printf '%s\n' "Pause and gather more evidence"
      } > "$options_file"
    fi
    if ! save_decision_request "$conv_dir" "$question_text" "$options_file"; then
      rm -f "$options_file"
      emit_error "could not save decision request"
      exit 0
    fi
    rm -f "$options_file"

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    printf '%s\n' "awaiting_decision" > "$queue_dir/last_status"
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

    decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
    printf '{"success":true,"queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s","decision_request":%s}\n' \
      "$queue_pending" "$queue_running" "$queue_done" "$(json_escape "$queue_first_id")" "$(json_escape "$queue_last_status")" "$decision_request_json"
    exit 0
