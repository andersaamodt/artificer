# action: archive_conversation
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

    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
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
    running_pid=$(read_file_line "$running_pid_file" "")

    if [ -f "$running_file" ]; then
      printf '%s\n' "$(date +%s)" > "$running_stop_file"
      if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
        kill -TERM "$running_pid" 2>/dev/null || true
        waited=0
        while [ "$waited" -lt 30 ]; do
          if ! kill -0 "$running_pid" 2>/dev/null; then
            break
          fi
          sleep 0.1
          waited=$((waited + 1))
        done
        if kill -0 "$running_pid" 2>/dev/null; then
          kill -KILL "$running_pid" 2>/dev/null || true
        fi
      fi
      queue_clear_running_state "$conv_dir"
      printf '%s\n' "cancelled" > "$queue_dir/last_status"
      rm -f "$queue_dir/last_error"
      date +%s > "$queue_dir/last_done"
    fi

    archived_dir="$ws_dir/archived"
    mkdir -p "$archived_dir"

    archive_suffix=$(date +%s 2>/dev/null || printf '0')
    archive_target="$archived_dir/${conversation_id}-${archive_suffix}"
    mv "$conv_dir" "$archive_target"

    emit_ok_message "conversation archived"
    exit 0
