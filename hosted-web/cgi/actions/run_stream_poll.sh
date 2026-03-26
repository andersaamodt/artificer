# action: run_stream_poll
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    stream_session=$(trim "$(param "stream_session")")
    offset_raw=$(trim "$(param "offset")")
    offset=0

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if ! valid_id "$stream_session"; then
      emit_error "invalid stream_session"
      exit 0
    fi

    case "$offset_raw" in
      ""|*[!0-9]*)
        offset=0
        ;;
      *)
        offset=$offset_raw
        ;;
    esac

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi
    poll_task_status_json=$(task_status_json_from_tasks_dir "$(tasks_dir_for_conversation "$conv_dir")" "running" "$(sed -n '1,60p' "$conv_dir/agent/.state" 2>/dev/null || true)")

    stream_file=$(stream_tokens_file_for "$conv_dir" "$stream_session")
    if [ ! -f "$stream_file" ]; then
      printf '{"success":true,"delta":"","offset":0,"task_status":%s}\n' "$poll_task_status_json"
      exit 0
    fi

    total_bytes=$(wc -c < "$stream_file" | tr -d ' ')
    case "$total_bytes" in
      ""|*[!0-9]*)
        total_bytes=0
        ;;
    esac

    if [ "$offset" -lt 0 ]; then
      offset=0
    fi
    if [ "$offset" -gt "$total_bytes" ]; then
      offset=$total_bytes
    fi

    if [ "$offset" -ge "$total_bytes" ]; then
      printf '{"success":true,"delta":"","offset":%s,"task_status":%s}\n' "$total_bytes" "$poll_task_status_json"
      exit 0
    fi

    start_byte=$((offset + 1))
    delta_text=$(tail -c +"$start_byte" "$stream_file" 2>/dev/null || true)
    delta_json=$(json_escape "$delta_text")
    printf '{"success":true,"delta":"%s","offset":%s,"task_status":%s}\n' "$delta_json" "$total_bytes" "$poll_task_status_json"
    exit 0
