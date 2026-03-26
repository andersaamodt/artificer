# action: queue_list
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    limit_raw=$(trim "$(param "limit")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    limit=20
    case "$limit_raw" in
      ""|*[!0-9]*)
        ;;
      *)
        limit=$limit_raw
        ;;
    esac
    if [ "$limit" -lt 1 ]; then
      limit=1
    fi
    if [ "$limit" -gt 80 ]; then
      limit=80
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    ensure_queue_layout "$conv_dir"
    pending_dir=$(queue_pending_dir_for "$conv_dir")
    queue_paths_file=$(mktemp)
    queue_pending_paths_sorted "$pending_dir" > "$queue_paths_file"

    queue_items_json=""
    queue_items_count=0
    while IFS= read -r pending_path || [ -n "$pending_path" ]; do
      [ -n "$pending_path" ] || continue
      [ -f "$pending_path" ] || continue
      if [ "$queue_items_count" -ge "$limit" ]; then
        break
      fi

      queued_item_id=$(queue_item_id_from_path "$pending_path")
      queued_item_order=$(queue_item_order_from_path "$pending_path")
      queued_prompt=$(cat "$pending_path")
      queued_prompt_json=$(json_escape "$queued_prompt")
      queued_order_json=$(json_escape "$queued_item_order")
      queued_item_id_json=$(json_escape "$queued_item_id")

      queued_meta=$(queue_item_meta_for_path "$pending_path")
      queued_mode=$(queue_meta_run_mode_from_file "$queued_meta")
      queued_assistant_mode=$(queue_meta_assistant_mode_from_file "$queued_meta")
      queued_compute_budget=$(queue_meta_compute_budget_from_file "$queued_meta")
      queued_command_exec_mode=$(queue_meta_command_exec_mode_from_file "$queued_meta")
      queued_permission_mode=$(queue_meta_permission_mode_from_file "$queued_meta")
      queued_programmer_review=$(queue_meta_programmer_review_from_file "$queued_meta")
      queued_programmer_review_rounds=$(queue_meta_programmer_review_rounds_from_file "$queued_meta")
      queued_mode_json=$(json_escape "$queued_mode")
      queued_assistant_mode_json=$(json_escape "$queued_assistant_mode")
      queued_compute_budget_json=$(json_escape "$queued_compute_budget")
      queued_command_exec_mode_json=$(json_escape "$queued_command_exec_mode")
      queued_permission_mode_json=$(json_escape "$queued_permission_mode")
      queued_programmer_review_json=$(json_escape "$queued_programmer_review")
      queued_programmer_review_rounds_json=$(json_escape "$queued_programmer_review_rounds")

      queued_skills_file=$(mktemp)
      queue_meta_explicit_skills_to_file "$queued_meta" "$queued_skills_file"
      queued_skills_json=$(string_json_array_from_ids_file "$queued_skills_file")
      rm -f "$queued_skills_file"

      if [ "$queue_items_count" -gt 0 ]; then
        queue_items_json="$queue_items_json,"
      fi
      queue_items_json="$queue_items_json{\"id\":\"$queued_item_id_json\",\"order\":\"$queued_order_json\",\"prompt\":\"$queued_prompt_json\",\"run_mode\":\"$queued_mode_json\",\"assistant_mode_id\":\"$queued_assistant_mode_json\",\"compute_budget\":\"$queued_compute_budget_json\",\"command_exec_mode\":\"$queued_command_exec_mode_json\",\"permission_mode\":\"$queued_permission_mode_json\",\"programmer_review\":\"$queued_programmer_review_json\",\"programmer_review_rounds\":\"$queued_programmer_review_rounds_json\",\"explicit_skill_ids\":$queued_skills_json}"
      queue_items_count=$((queue_items_count + 1))
    done < "$queue_paths_file"
    rm -f "$queue_paths_file"

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
    printf '{"success":true,"items":[%s],"queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s"}\n' \
      "$queue_items_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json"
    exit 0
