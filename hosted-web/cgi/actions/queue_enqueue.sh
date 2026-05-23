# action: queue_enqueue
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    prompt_text=$(param "prompt")
    position=$(trim "$(param "position")")
    attachments_raw=$(param "attachments")
    run_mode_raw=$(trim "$(param "run_mode")")
    assistant_mode_raw=$(trim "$(param "assistant_mode_id")")
    compute_budget_raw=$(trim "$(param "compute_budget")")
    reasoning_effort_raw=$(trim "$(param "reasoning_effort")")
    command_exec_mode_raw=$(trim "$(param "command_exec_mode")")
    permission_mode_raw=$(trim "$(param "permission_mode")")
    reflexive_knowledge_raw=$(trim "$(param "reflexive_knowledge")")
    self_actuation_raw=$(trim "$(param "self_actuation")")
    programmer_review_raw=$(trim "$(param "programmer_review")")
    programmer_review_rounds_raw=$(trim "$(param "programmer_review_rounds")")
    assay_task_id_raw=$(trim "$(param "assay_task_id")")
    explicit_skill_ids_raw=$(param "explicit_skill_ids")

    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -z "$(trim "$prompt_text")" ]; then
      emit_error "prompt is required"
      exit 0
    fi

    conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ ! -d "$conv_dir" ]; then
      emit_error "conversation not found"
      exit 0
    fi

    mode="tail"
    case "$position" in
      head|front|next|steer)
        mode="head"
        ;;
    esac

    ensure_queue_layout "$conv_dir"
    item_id=$(new_id)
    order=$(queue_allocate_order "$conv_dir" "$mode")
    queue_item_file=$(queue_item_file_for "$conv_dir" "$order" "$item_id")
    queue_item_meta=$(queue_item_meta_for_path "$queue_item_file")
    queue_item_mode=$(normalize_run_mode_name "$run_mode_raw")
    queue_item_assistant_mode=$(normalize_assistant_mode_id "$assistant_mode_raw")
    queue_item_compute_budget=$(normalize_compute_budget "$compute_budget_raw")
    queue_item_command_exec_mode=$(normalize_command_exec_mode_value "$command_exec_mode_raw")
    queue_item_permission_mode=$(normalize_permission_mode_value "$permission_mode_raw")
    queue_item_reflexive_knowledge=$(normalize_reflexive_knowledge_value "$reflexive_knowledge_raw")
    queue_item_self_actuation=$(normalize_self_actuation_value "$self_actuation_raw")
    queue_item_programmer_review=$(normalize_programmer_review_enabled_value "$programmer_review_raw")
    queue_item_programmer_review_rounds=$(normalize_programmer_review_rounds_value "$programmer_review_rounds_raw" 2)
    queue_item_assay_task_id=$(normalize_assay_task_id_value "$assay_task_id_raw")
    if [ "$queue_item_mode" != "assistant" ]; then
      queue_item_assistant_mode=""
    fi
    printf '%s' "$prompt_text" > "$queue_item_file"

    incoming_ids_file=$(mktemp)
    validated_ids_file=$(mktemp)
    incoming_skill_ids_file=$(mktemp)
    validated_skill_ids_file=$(mktemp)
    attachment_ids_to_file "$attachments_raw" "$incoming_ids_file"
    skill_ids_to_file "$explicit_skill_ids_raw" "$incoming_skill_ids_file"
    : > "$validated_ids_file"
    : > "$validated_skill_ids_file"
    while IFS= read -r attachment_id; do
      [ -n "$attachment_id" ] || continue
      if attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
        printf '%s\n' "$attachment_id" >> "$validated_ids_file"
      fi
    done < "$incoming_ids_file"
    while IFS= read -r skill_id; do
      skill_id=$(trim "$skill_id")
      [ -n "$skill_id" ] || continue
      if valid_id "$skill_id"; then
        printf '%s\n' "$skill_id" >> "$validated_skill_ids_file"
      fi
    done < "$incoming_skill_ids_file"
    queue_meta_write "$queue_item_meta" "$queue_item_mode" "$queue_item_assistant_mode" "$queue_item_compute_budget" "$queue_item_command_exec_mode" "$queue_item_permission_mode" "$queue_item_programmer_review" "$queue_item_programmer_review_rounds" "$validated_skill_ids_file" "$validated_ids_file" "$queue_item_assay_task_id" "" "$queue_item_reflexive_knowledge" "$queue_item_self_actuation" "$reasoning_effort_raw"

    # Persist user intent at enqueue time so threads are never blank even if queue execution is interrupted.
    user_message_prompt=$prompt_text
    inline_guard=0
    while [ "$inline_guard" -lt 3 ]; do
      leading_tag=$(leading_prompt_slash_tag "$user_message_prompt")
      [ -n "$leading_tag" ] || break
      mapped_inline_mode=$(run_mode_from_slash_tag "$leading_tag")
      [ -n "$mapped_inline_mode" ] || break
      user_message_prompt=$(strip_leading_prompt_slash_tag "$user_message_prompt")
      inline_guard=$((inline_guard + 1))
    done
    user_message_prompt=$(trim "$user_message_prompt")
    [ -n "$user_message_prompt" ] || user_message_prompt=$prompt_text
    queued_attachment_names=""
    while IFS= read -r attachment_id; do
      [ -n "$attachment_id" ] || continue
      attachment_name=$(attachment_meta_get "$conv_dir" "$attachment_id" "name")
      [ -n "$attachment_name" ] || continue
      if [ -z "$queued_attachment_names" ]; then
        queued_attachment_names="- $attachment_name"
      else
        queued_attachment_names="${queued_attachment_names}
- $attachment_name"
      fi
    done < "$validated_ids_file"
    queued_user_message_text=$user_message_prompt
    if [ -n "$(trim "$queued_attachment_names")" ]; then
      queued_user_message_text=$(cat <<EOF
$user_message_prompt

Attached files:
$queued_attachment_names
EOF
)
    fi
    append_message "$conv_dir" "user" "$queued_user_message_text"

    rm -f "$incoming_ids_file" "$validated_ids_file" "$incoming_skill_ids_file" "$validated_skill_ids_file"

    queue_info=$(queue_state_for_conversation "$conv_dir")
    queue_pending=$(kv_get "pending" "$queue_info")
    queue_running=$(kv_get "running" "$queue_info")
    queue_done=$(kv_get "done" "$queue_info")
    queue_first_id=$(kv_get "first_id" "$queue_info")

    [ -n "$queue_pending" ] || queue_pending=0
    [ -n "$queue_running" ] || queue_running=0
    [ -n "$queue_done" ] || queue_done=0

    item_id_json=$(json_escape "$item_id")
    queue_first_id_json=$(json_escape "$queue_first_id")

    printf '{"success":true,"item_id":"%s","queue_pending":%s,"queue_running":%s,"queue_done":%s,"queue_first_id":"%s"}\n' \
      "$item_id_json" "$queue_pending" "$queue_running" "$queue_done" "$queue_first_id_json"
    exit 0
