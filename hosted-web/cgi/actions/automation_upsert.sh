# action: automation_upsert
    automation_id=$(trim "$(param "automation_id")")
    automation_name=$(trim "$(param "name")")
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    prompt_text=$(param "prompt")
    schedule_kind_raw=$(trim "$(param "schedule_kind")")
    schedule_value_raw=$(trim "$(param "schedule_value")")
    enabled_raw=$(trim "$(param "enabled")")
    allow_self_reschedule_raw=$(trim "$(param "allow_self_reschedule")")
    run_mode_raw=$(trim "$(param "run_mode")")
    assistant_mode_raw=$(trim "$(param "assistant_mode_id")")
    compute_budget_raw=$(trim "$(param "compute_budget")")
    command_exec_mode_raw=$(trim "$(param "command_exec_mode")")
    permission_mode_raw=$(trim "$(param "permission_mode")")
    programmer_review_raw=$(trim "$(param "programmer_review")")
    programmer_review_rounds_raw=$(trim "$(param "programmer_review_rounds")")
    assay_task_id_raw=$(trim "$(param "assay_task_id")")
    explicit_skill_ids_raw=$(param "explicit_skill_ids")
    next_run_override_raw=$(trim "$(param "next_run")")

    creating=0
    if [ -z "$automation_id" ]; then
      creating=1
      automation_id=$(new_id)
    fi
    if ! valid_id "$automation_id"; then
      emit_error "invalid automation_id"
      exit 0
    fi

    automation_dir=$(automation_dir_for "$automation_id")
    if [ "$creating" = "0" ] && [ ! -d "$automation_dir" ]; then
      emit_error "automation not found"
      exit 0
    fi

    if [ -z "$automation_name" ]; then
      automation_name=$(read_file_line "$(automation_field_file_for "$automation_dir" "name")" "")
    fi
    if [ -z "$automation_name" ]; then
      automation_name="Automation"
    fi

    if [ -z "$workspace_id" ]; then
      workspace_id=$(read_file_line "$(automation_field_file_for "$automation_dir" "workspace_id")" "")
    fi
    if ! valid_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    ws_dir=$(workspace_dir_for "$workspace_id")
    if [ ! -d "$ws_dir" ]; then
      emit_error "workspace not found"
      exit 0
    fi

    if [ -z "$conversation_id" ]; then
      conversation_id=$(read_file_line "$(automation_field_file_for "$automation_dir" "conversation_id")" "")
    fi
    if [ -n "$conversation_id" ] && ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi
    if [ -n "$conversation_id" ]; then
      conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
      if [ ! -d "$conv_dir" ]; then
        emit_error "conversation not found"
        exit 0
      fi
    fi

    if [ -z "$(trim "$prompt_text")" ]; then
      prompt_text=$(cat "$(automation_field_file_for "$automation_dir" "prompt")" 2>/dev/null || true)
    fi
    if [ -z "$(trim "$prompt_text")" ]; then
      emit_error "prompt is required"
      exit 0
    fi

    if [ -z "$schedule_kind_raw" ]; then
      schedule_kind_raw=$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_kind")" "")
    fi
    if [ -z "$schedule_value_raw" ]; then
      schedule_value_raw=$(read_file_line "$(automation_field_file_for "$automation_dir" "schedule_value")" "")
    fi
    schedule_kind=$(automation_schedule_kind_value "$schedule_kind_raw")
    if [ -z "$schedule_kind" ]; then
      emit_error "invalid schedule_kind"
      exit 0
    fi
    now_epoch=$(automation_now_epoch)
    schedule_info=$(automation_schedule_normalize_and_next "$schedule_kind" "$schedule_value_raw" "$now_epoch")
    if [ "$(kv_get "status" "$schedule_info")" != "ok" ]; then
      emit_error "$(kv_get "error" "$schedule_info")"
      exit 0
    fi
    schedule_kind=$(automation_schedule_kind_value "$(kv_get "kind" "$schedule_info")")
    schedule_value=$(trim "$(kv_get "value" "$schedule_info")")
    schedule_text=$(trim "$(kv_get "text" "$schedule_info")")
    next_run_epoch=$(automation_epoch_or_zero "$(kv_get "next" "$schedule_info")")

    existing_enabled=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "enabled")" "1")")
    if [ -n "$enabled_raw" ]; then
      case "$(printf '%s' "$enabled_raw" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on|enabled|0|false|no|off|disabled)
          ;;
        *)
          emit_error "invalid enabled value"
          exit 0
          ;;
      esac
      enabled_value=$(automation_enabled_value "$enabled_raw")
    else
      enabled_value=$existing_enabled
    fi
    if [ "$enabled_value" != "1" ]; then
      next_run_epoch=0
    fi
    case "$next_run_override_raw" in
      ""|*[!0-9]*)
        ;;
      *)
        if [ "$next_run_override_raw" -gt "$now_epoch" ] && [ "$enabled_value" = "1" ]; then
          next_run_epoch=$next_run_override_raw
        fi
        ;;
    esac

    existing_allow_self=$(automation_enabled_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "allow_self_reschedule")" "0")")
    if [ -n "$allow_self_reschedule_raw" ]; then
      case "$(printf '%s' "$allow_self_reschedule_raw" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on|enabled|0|false|no|off|disabled)
          ;;
        *)
          emit_error "invalid allow_self_reschedule value"
          exit 0
          ;;
      esac
      allow_self_reschedule_value=$(automation_enabled_value "$allow_self_reschedule_raw")
    else
      allow_self_reschedule_value=$existing_allow_self
    fi

    run_mode_value=$(normalize_run_mode_name "$run_mode_raw")
    if [ -z "$run_mode_value" ]; then
      run_mode_value=$(normalize_run_mode_name "$(read_file_line "$(automation_field_file_for "$automation_dir" "run_mode")" "assistant")")
    fi
    [ -n "$run_mode_value" ] || run_mode_value="assistant"

    assistant_mode_value=$(normalize_assistant_mode_id "$assistant_mode_raw")
    if [ -z "$assistant_mode_value" ]; then
      assistant_mode_value=$(normalize_assistant_mode_id "$(read_file_line "$(automation_field_file_for "$automation_dir" "assistant_mode_id")" "")")
    fi
    if [ "$run_mode_value" != "assistant" ]; then
      assistant_mode_value=""
    fi

    compute_budget_value=$(normalize_compute_budget "$compute_budget_raw")
    if [ -z "$compute_budget_value" ]; then
      compute_budget_value=$(normalize_compute_budget "$(read_file_line "$(automation_field_file_for "$automation_dir" "compute_budget")" "auto")")
    fi
    [ -n "$compute_budget_value" ] || compute_budget_value="auto"

    command_exec_mode_value=""
    if [ -n "$command_exec_mode_raw" ]; then
      command_exec_mode_value=$(normalize_command_exec_mode_value "$command_exec_mode_raw")
      if [ -z "$command_exec_mode_value" ]; then
        emit_error "invalid command_exec_mode"
        exit 0
      fi
    else
      command_exec_mode_value=$(normalize_command_exec_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "command_exec_mode")" "")")
    fi

    permission_mode_value=""
    if [ -n "$permission_mode_raw" ]; then
      permission_mode_value=$(normalize_permission_mode_value "$permission_mode_raw")
      if [ -z "$permission_mode_value" ]; then
        emit_error "invalid permission_mode"
        exit 0
      fi
    else
      permission_mode_value=$(normalize_permission_mode_value "$(read_file_line "$(automation_field_file_for "$automation_dir" "permission_mode")" "")")
    fi

    if [ -z "$programmer_review_raw" ]; then
      programmer_review_raw=$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review")" "1")
    fi
    programmer_review_value=$(normalize_programmer_review_enabled_value "$programmer_review_raw")

    if [ -z "$programmer_review_rounds_raw" ]; then
      programmer_review_rounds_raw=$(read_file_line "$(automation_field_file_for "$automation_dir" "programmer_review_rounds")" "2")
    fi
    programmer_review_rounds_value=$(normalize_programmer_review_rounds_value "$programmer_review_rounds_raw" 2)

    if [ -z "$assay_task_id_raw" ]; then
      assay_task_id_raw=$(read_file_line "$(automation_field_file_for "$automation_dir" "assay_task_id")" "")
    fi
    assay_task_id_value=$(normalize_assay_task_id_value "$assay_task_id_raw")

    mkdir -p "$automation_dir"
    mkdir -p "$(automation_runtime_dir_for "$automation_id")"
    automation_write_common_fields "$automation_dir" "$automation_name" "$workspace_id" "$conversation_id" "$prompt_text" "$schedule_kind" "$schedule_value" "$schedule_text" "$enabled_value" "$allow_self_reschedule_value" "$run_mode_value" "$assistant_mode_value" "$compute_budget_value" "$command_exec_mode_value" "$permission_mode_value" "$programmer_review_value" "$programmer_review_rounds_value" "$assay_task_id_value"

    explicit_skills_file=$(automation_explicit_skills_file_for "$automation_dir")
    skill_ids_to_file "$explicit_skill_ids_raw" "$explicit_skills_file"

    created_epoch=$(automation_epoch_or_zero "$(read_file_line "$(automation_field_file_for "$automation_dir" "created")" "0")")
    if [ "$created_epoch" -le 0 ]; then
      created_epoch=$now_epoch
    fi
    printf '%s\n' "$created_epoch" > "$(automation_field_file_for "$automation_dir" "created")"
    printf '%s\n' "$now_epoch" > "$(automation_field_file_for "$automation_dir" "updated")"
    printf '%s\n' "$next_run_epoch" > "$(automation_field_file_for "$automation_dir" "next_run")"
    if [ ! -f "$(automation_field_file_for "$automation_dir" "last_run")" ]; then
      printf '%s\n' "0" > "$(automation_field_file_for "$automation_dir" "last_run")"
    fi
    if [ ! -f "$(automation_field_file_for "$automation_dir" "last_status")" ]; then
      printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_status")"
    fi
    if [ ! -f "$(automation_field_file_for "$automation_dir" "last_error")" ]; then
      printf '%s\n' "" > "$(automation_field_file_for "$automation_dir" "last_error")"
    fi

    printf '{"success":true,"automation":%s,"automations":%s}\n' "$(automation_json_for_id "$automation_id")" "$(automations_state_json)"
    exit 0
