# action: decision_answer
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    answer_text=$(trim "$(param "answer")")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -z "$answer_text" ]; then
      emit_error "answer is required"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    question_file=$(decision_question_file_for "$conv_dir")
    options_file=$(decision_options_file_for "$conv_dir")
    if [ ! -f "$question_file" ] || [ ! -f "$options_file" ]; then
      emit_error "no pending decision"
      exit 0
    fi

    decision_question=$(trim "$(read_file_line "$question_file" "")")
    if [ -z "$decision_question" ]; then
      emit_error "pending decision is invalid"
      exit 0
    fi

    clear_decision_request "$conv_dir"

    decision_message=$(cat <<EOF
Decision selected:
Question: $decision_question
Answer: $answer_text
EOF
)
    append_message "$conv_dir" "user" "$decision_message"

    ensure_queue_layout "$conv_dir"
    queue_dir=$(conversation_queue_dir_for "$conv_dir")
    item_id=$(new_id)
    order=$(queue_allocate_order "$conv_dir" "head")
    queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
    queue_item_meta=$(queue_item_meta_for_path "$queue_item_file")
    queue_last_mode_file=$(queue_last_mode_file_for "$conv_dir")
    queue_last_assistant_mode_file=$(queue_last_assistant_mode_file_for "$conv_dir")
    queue_last_compute_budget_file=$(queue_last_compute_budget_file_for "$conv_dir")
    queue_last_command_exec_mode_file=$(queue_last_command_exec_mode_file_for "$conv_dir")
    queue_last_permission_mode_file=$(queue_last_permission_mode_file_for "$conv_dir")
    queue_last_programmer_review_file=$(queue_last_programmer_review_file_for "$conv_dir")
    queue_last_programmer_review_rounds_file=$(queue_last_programmer_review_rounds_file_for "$conv_dir")
    queue_last_assay_task_id_file=$(queue_last_assay_task_id_file_for "$conv_dir")
    decision_run_mode=$(normalize_run_mode_name "$(read_file_line "$queue_last_mode_file" "auto")")
    decision_compute_budget=$(normalize_compute_budget "$(read_file_line "$queue_last_compute_budget_file" "auto")")
    decision_command_exec_mode=$(normalize_command_exec_mode_value "$(read_file_line "$queue_last_command_exec_mode_file" "ask-some")")
    decision_permission_mode=$(normalize_permission_mode_value "$(read_file_line "$queue_last_permission_mode_file" "default")")
    decision_programmer_review=$(normalize_programmer_review_enabled_value "$(read_file_line "$queue_last_programmer_review_file" "1")")
    decision_programmer_review_rounds=$(normalize_programmer_review_rounds_value "$(read_file_line "$queue_last_programmer_review_rounds_file" "2")" 2)
    decision_assay_task_id=$(normalize_assay_task_id_value "$(read_file_line "$queue_last_assay_task_id_file" "")")
    decision_assistant_mode=""
    if [ "$decision_run_mode" = "assistant" ]; then
      decision_assistant_mode=$(normalize_assistant_mode_id "$(read_file_line "$queue_last_assistant_mode_file" "")")
    fi
    decision_prompt=$(cat <<EOF
Continue the current task using this user decision.

Question:
$decision_question

Selected answer:
$answer_text
EOF
)
    printf '%s' "$decision_prompt" > "$queue_item_file"
    empty_attachment_ids=$(mktemp)
    empty_skill_ids=$(mktemp)
    : > "$empty_attachment_ids"
    : > "$empty_skill_ids"
    queue_meta_write "$queue_item_meta" "$decision_run_mode" "$decision_assistant_mode" "$decision_compute_budget" "$decision_command_exec_mode" "$decision_permission_mode" "$decision_programmer_review" "$decision_programmer_review_rounds" "$empty_skill_ids" "$empty_attachment_ids" "$decision_assay_task_id" ""
    rm -f "$empty_attachment_ids" "$empty_skill_ids"
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

    item_id_json=$(json_escape "$item_id")
    queue_first_id_json=$(json_escape "$queue_first_id")
    queue_last_status_json=$(json_escape "$queue_last_status")
    decision_request_json=$(decision_request_json_for_conversation "$conv_dir")

    printf '{"success":true,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s","queue_last_status":"%s","decision_request":%s}\n' \
      "$item_id_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json" "$queue_last_status_json" "$decision_request_json"
    exit 0
