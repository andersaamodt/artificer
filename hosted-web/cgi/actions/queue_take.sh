# action: queue_take
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
    pending_dir=$(queue_pending_dir_for "$conv_dir")
    running_file="$queue_dir/running.txt"
    running_id_file="$queue_dir/running.id"
    running_started_file="$queue_dir/running.started"
    running_meta_file=$(queue_running_meta_file_for "$conv_dir")

    if [ -f "$running_file" ]; then
      running_pid=$(read_file_line "$queue_dir/running.pid" "")
      running_started=$(read_file_line "$running_started_file" "0")
      running_compute_budget=$(queue_meta_compute_budget_from_file "$running_meta_file")
      running_compute_budget=$(normalize_compute_budget "$running_compute_budget")
      run_budget_hint=${ARTIFICER_RUN_TIME_BUDGET_SEC:-900}
      case "$run_budget_hint" in
        ""|*[!0-9]*)
          run_budget_hint=900
          ;;
      esac
      running_stale_timeout_sec=$(compute_budget_stale_timeout_sec "$running_compute_budget" "$run_budget_hint")
      running_stale=0
      if [ -n "$running_pid" ] && ! kill -0 "$running_pid" 2>/dev/null; then
        running_stale=1
      fi
      case "$running_started" in
        ""|*[!0-9]*)
          running_started=0
          ;;
      esac
      if [ -z "$running_pid" ] && [ "$running_stale" -ne 1 ]; then
        missing_pid_grace=$(queue_missing_pid_grace_sec)
        if [ "$running_started" -le 0 ]; then
          running_stale=1
        else
          running_now=$(date +%s)
          running_age=$((running_now - running_started))
          if [ "$running_age" -gt "$missing_pid_grace" ]; then
            running_stale=1
          fi
        fi
      fi
      if [ "$running_started" -gt 0 ]; then
        running_now=$(date +%s)
        running_age=$((running_now - running_started))
        if [ "$running_age" -gt "$running_stale_timeout_sec" ]; then
          running_stale=1
        fi
      fi
      if [ "$running_stale" -eq 1 ]; then
        requeued_running=$(queue_requeue_running_state "$conv_dir")
        if [ "$requeued_running" = "1" ]; then
          printf '%s\n' "queued" > "$queue_dir/last_status"
          printf '%s\n' "stale run was requeued for retry" > "$queue_dir/last_error"
        else
          printf '%s\n' "error" > "$queue_dir/last_status"
          printf '%s\n' "run state became stale and was recovered" > "$queue_dir/last_error"
        fi
        date +%s > "$queue_dir/last_done"
      else
      running_id=$(read_file_line "$running_id_file" "")
      queue_info=$(queue_state_for_conversation "$conv_dir")
      queue_pending=$(kv_get "pending" "$queue_info")
      queue_first_id=$(kv_get "first_id" "$queue_info")
      queue_last_status=$(kv_get "last_status" "$queue_info")
      [ -n "$queue_pending" ] || queue_pending=0
      running_id_json=$(json_escape "$running_id")
      queue_first_id_json=$(json_escape "$queue_first_id")
      queue_last_status_json=$(json_escape "$queue_last_status")
      printf '{"success":true,"busy":true,"has_item":false,"running_item_id":"%s","queue_pending":%s,"queue_running":1,"queue_done":0,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
        "$running_id_json" "$queue_pending" "$queue_first_id_json" "$queue_last_status_json"
      exit 0
      fi
    fi

    first_pending_path=$(queue_first_pending_path "$pending_dir")
    if [ -z "$first_pending_path" ] || [ ! -f "$first_pending_path" ]; then
      queue_info=$(queue_state_for_conversation "$conv_dir")
      queue_pending=$(kv_get "pending" "$queue_info")
      queue_done=$(kv_get "done" "$queue_info")
      queue_first_id=$(kv_get "first_id" "$queue_info")
      queue_last_status=$(kv_get "last_status" "$queue_info")
      [ -n "$queue_pending" ] || queue_pending=0
      [ -n "$queue_done" ] || queue_done=0
      queue_first_id_json=$(json_escape "$queue_first_id")
      queue_last_status_json=$(json_escape "$queue_last_status")
      printf '{"success":true,"busy":false,"has_item":false,"queue_pending":%s,"queue_running":0,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
        "$queue_pending" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
      exit 0
    fi

    item_id=$(queue_item_id_from_path "$first_pending_path")
    prompt_text=$(cat "$first_pending_path")
    pending_meta_file=$(queue_item_meta_for_path "$first_pending_path")

    mv "$first_pending_path" "$running_file"
    if [ -f "$pending_meta_file" ]; then
      mv "$pending_meta_file" "$running_meta_file"
    else
      rm -f "$running_meta_file"
    fi
    printf '%s\n' "$item_id" > "$running_id_file"
    date +%s > "$running_started_file"

    queue_info=$(queue_state_for_conversation "$conv_dir")
    queue_pending=$(kv_get "pending" "$queue_info")
    queue_first_id=$(kv_get "first_id" "$queue_info")
    [ -n "$queue_pending" ] || queue_pending=0

    item_id_json=$(json_escape "$item_id")
    prompt_json=$(json_escape "$prompt_text")
    queue_first_id_json=$(json_escape "$queue_first_id")
    running_attachments_file=$(mktemp)
    running_skills_file=$(mktemp)
    queue_meta_attachment_ids_to_file "$running_meta_file" "$running_attachments_file"
    queue_meta_explicit_skills_to_file "$running_meta_file" "$running_skills_file"
    attachments_json=$(attachment_json_array_from_ids_file "$conv_dir" "$running_attachments_file")
    explicit_skills_json=$(string_json_array_from_ids_file "$running_skills_file")
    rm -f "$running_attachments_file" "$running_skills_file"
    item_run_mode=$(queue_meta_run_mode_from_file "$running_meta_file")
    item_assistant_mode=$(queue_meta_assistant_mode_from_file "$running_meta_file")
    item_compute_budget=$(queue_meta_compute_budget_from_file "$running_meta_file")
    item_command_exec_mode=$(queue_meta_command_exec_mode_from_file "$running_meta_file")
    item_permission_mode=$(queue_meta_permission_mode_from_file "$running_meta_file")
    item_reflexive_knowledge=$(queue_meta_reflexive_knowledge_from_file "$running_meta_file")
    item_self_actuation=$(queue_meta_self_actuation_from_file "$running_meta_file")
    item_programmer_review=$(queue_meta_programmer_review_from_file "$running_meta_file")
    item_programmer_review_rounds=$(queue_meta_programmer_review_rounds_from_file "$running_meta_file")
    item_run_mode_json=$(json_escape "$item_run_mode")
    item_assistant_mode_json=$(json_escape "$item_assistant_mode")
    item_compute_budget_json=$(json_escape "$item_compute_budget")
    item_command_exec_mode_json=$(json_escape "$item_command_exec_mode")
    item_permission_mode_json=$(json_escape "$item_permission_mode")
    item_reflexive_knowledge_json=$(json_escape "$item_reflexive_knowledge")
    item_self_actuation_json=$(json_escape "$item_self_actuation")
    item_programmer_review_json=$(json_escape "$item_programmer_review")
    item_programmer_review_rounds_json=$(json_escape "$item_programmer_review_rounds")

    printf '{"success":true,"busy":false,"has_item":true,"item":{"id":"%s","prompt":"%s","attachments":%s,"run_mode":"%s","assistant_mode_id":"%s","compute_budget":"%s","command_exec_mode":"%s","permission_mode":"%s","reflexive_knowledge":"%s","self_actuation":"%s","programmer_review":"%s","programmer_review_rounds":"%s","explicit_skill_ids":%s},"queue_pending":%s,"queue_running":1,"queue_done":0,"queue_first_id":"%s","queue_last_status":"running"}\n' \
      "$item_id_json" "$prompt_json" "$attachments_json" "$item_run_mode_json" "$item_assistant_mode_json" "$item_compute_budget_json" "$item_command_exec_mode_json" "$item_permission_mode_json" "$item_reflexive_knowledge_json" "$item_self_actuation_json" "$item_programmer_review_json" "$item_programmer_review_rounds_json" "$explicit_skills_json" "$queue_pending" "$queue_first_id_json"
    exit 0
