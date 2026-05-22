# action: queue_stop
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")

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

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    running_pid_file="$queue_dir/running.pid"
    running_stop_file="$queue_dir/running.stop"
    running_file="$queue_dir/running.txt"

    stopped=0
    forced=0
    running_pid=$(read_file_line "$running_pid_file" "")
    running_active=0
    if [ -f "$running_file" ]; then
      running_active=1
    elif [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
      running_active=1
    fi

    if [ "$running_active" -eq 1 ]; then
      printf '%s\n' "$(date +%s)" > "$running_stop_file"
      if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
        kill -TERM "$running_pid" 2>/dev/null || true
        waited=0
        while [ "$waited" -lt 30 ]; do
          if ! kill -0 "$running_pid" 2>/dev/null; then
            stopped=1
            break
          fi
          sleep 0.1
          waited=$((waited + 1))
        done
        if [ "$stopped" -ne 1 ] && kill -0 "$running_pid" 2>/dev/null; then
          kill -KILL "$running_pid" 2>/dev/null || true
          forced=1
          stopped=1
        fi
      fi
      append_cancelled_run_event_for_stop "$conv_dir" "Run stopped via queue_stop."
      queue_clear_running_state "$conv_dir"
      printf '%s\n' "cancelled" > "$queue_dir/last_status"
      clear_approval_request "$conv_dir"
      rm -f "$queue_dir/last_error"
      date +%s > "$queue_dir/last_done"
      if [ "$stopped" -ne 1 ]; then
        stopped=1
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

    if [ "$stopped" -eq 1 ]; then
      stopped_json=true
    else
      stopped_json=false
    fi
    if [ "$forced" -eq 1 ]; then
      forced_json=true
    else
      forced_json=false
    fi

    queue_first_id_json=$(json_escape "$queue_first_id")
    queue_last_status_json=$(json_escape "$queue_last_status")

    printf '{"success":true,"stopped":%s,"forced":%s,"queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$stopped_json" "$forced_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
    exit 0
