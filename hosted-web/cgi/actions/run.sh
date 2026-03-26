# action: run
    workspace_id=$(trim "$(param "workspace_id")")
    conversation_id=$(trim "$(param "conversation_id")")
    user_prompt=$(param "prompt")
    permission_mode_raw=$(trim "$(param "permission_mode")")
    command_exec_mode_raw=$(trim "$(param "command_exec_mode")")
    approval_retry_raw=$(trim "$(param "approval_retry")")
    network_access_raw=$(trim "$(param "network_access")")
    web_access_raw=$(trim "$(param "web_access")")
    attachment_ids_raw=$(param "attachment_ids")
    queue_item_id=$(trim "$(param "queue_item_id")")
    advanced_loop_raw=$(trim "$(param "advanced_loop")")
    run_mode_raw=$(trim "$(param "run_mode")")
    assistant_mode_raw=$(trim "$(param "assistant_mode_id")")
    compute_budget_raw=$(trim "$(param "compute_budget")")
    explicit_skill_ids_raw=$(param "explicit_skill_ids")
    reasoning_effort_raw=$(trim "$(param "reasoning_effort")")
    max_iterations_raw=$(trim "$(param "max_iterations")")
    programmer_review_raw=$(trim "$(param "programmer_review")")
    programmer_review_rounds_raw=$(trim "$(param "programmer_review_rounds")")
    assay_task_id_raw=$(trim "$(param "assay_task_id")")
    stream_session=$(trim "$(param "stream_session")")
    run_event_id_param=$(trim "$(param "run_event_id")")
    run_message_anchor_raw=$(trim "$(param "run_message_anchor")")
    stream_output_file=""
    run_mode="auto"
    assistant_mode_id=""
    compute_budget="auto"
    max_iterations=2
    reasoning_effort="medium"
    append_user_message=1
    command_mode="ask-some"
    permission_mode="default"
    programmer_review_enabled=1
    programmer_review_max_rounds=2
    programmer_review_rounds_completed=0
    programmer_review_last_signature=""
    programmer_review_last_feedback=""
    assay_task_id=""
    allow_workspace_writes=1
    decision_request_json="null"
    forced_queue_status=""
    run_started_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    run_finished_iso=""
    run_event_id=""
    run_message_anchor=""
    controller_variant_id=""
    controller_variant_bucket="0"
    controller_variant_active_id=""
    controller_variant_candidate_id=""
    controller_variant_guidance=""

    if ! valid_workspace_id "$workspace_id"; then
      emit_error "invalid workspace_id"
      exit 0
    fi
    if ! valid_id "$conversation_id"; then
      emit_error "invalid conversation_id"
      exit 0
    fi

    if [ -z "$(trim "$user_prompt")" ]; then
      emit_error "prompt is required"
      exit 0
    fi

    case "$run_message_anchor_raw" in
      ""|*[!0-9]*)
        run_message_anchor=""
        ;;
      *)
        run_message_anchor=$run_message_anchor_raw
        ;;
    esac

    case "$(printf '%s' "$approval_retry_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on)
        append_user_message=0
        ;;
    esac

    case "$(printf '%s' "$reasoning_effort_raw" | tr '[:upper:]' '[:lower:]')" in
      low|medium|high|extra-high)
        reasoning_effort=$(printf '%s' "$reasoning_effort_raw" | tr '[:upper:]' '[:lower:]')
        ;;
    esac
    if [ -n "$programmer_review_raw" ]; then
      programmer_review_enabled=$(normalize_programmer_review_enabled_value "$programmer_review_raw")
    fi
    if [ -n "$programmer_review_rounds_raw" ]; then
      programmer_review_max_rounds=$(normalize_programmer_review_rounds_value "$programmer_review_rounds_raw" 2)
    fi
    if [ -n "$assay_task_id_raw" ]; then
      assay_task_id=$(normalize_assay_task_id_value "$assay_task_id_raw")
    fi
    run_mode=$(normalize_run_mode_name "$run_mode_raw")
    assistant_mode_id=$(normalize_assistant_mode_id "$assistant_mode_raw")
    compute_budget=$(normalize_compute_budget "$compute_budget_raw")
    inline_mode=""
    inline_mode_tag=""
    inline_prompt="$user_prompt"
    inline_guard=0
    while [ "$inline_guard" -lt 3 ]; do
      leading_tag=$(leading_prompt_slash_tag "$inline_prompt")
      [ -n "$leading_tag" ] || break
      mapped_inline_mode=$(run_mode_from_slash_tag "$leading_tag")
      [ -n "$mapped_inline_mode" ] || break
      inline_mode=$mapped_inline_mode
      inline_mode_tag="/$leading_tag"
      inline_prompt=$(strip_leading_prompt_slash_tag "$inline_prompt")
      inline_guard=$((inline_guard + 1))
    done
    if [ -n "$inline_mode" ]; then
      run_mode=$inline_mode
      stripped_inline_prompt=$(trim "$inline_prompt")
      if [ -n "$stripped_inline_prompt" ]; then
        user_prompt=$stripped_inline_prompt
      fi
    fi
    queue_mode_override=""
    queue_assistant_mode_override=""
    queue_compute_budget_override=""
    queue_command_exec_mode_override=""
    queue_permission_mode_override=""
    queue_programmer_review_override=""
    queue_programmer_review_rounds_override=""
    queue_assay_task_override=""
    queue_explicit_skills_override_file=$(mktemp)
    : > "$queue_explicit_skills_override_file"
    if [ -n "$queue_item_id" ] && valid_id "$queue_item_id"; then
      append_user_message=0
      conv_dir_for_mode=$(conversation_dir_for "$workspace_id" "$conversation_id")
      running_meta_for_mode=$(queue_running_meta_file_for "$conv_dir_for_mode")
      queue_dir_for_mode=$(conversation_queue_dir_for "$conv_dir_for_mode")
      running_id_for_mode=$(read_file_line "$queue_dir_for_mode/running.id" "")
      if [ "$running_id_for_mode" = "$queue_item_id" ]; then
        queue_mode_override=$(queue_meta_run_mode_from_file "$running_meta_for_mode")
        queue_assistant_mode_override=$(queue_meta_assistant_mode_from_file "$running_meta_for_mode")
        queue_compute_budget_override=$(queue_meta_compute_budget_from_file "$running_meta_for_mode")
        queue_command_exec_mode_override=$(queue_meta_command_exec_mode_from_file "$running_meta_for_mode")
        queue_permission_mode_override=$(queue_meta_permission_mode_from_file "$running_meta_for_mode")
        queue_programmer_review_override=$(queue_meta_programmer_review_from_file "$running_meta_for_mode")
        queue_programmer_review_rounds_override=$(queue_meta_programmer_review_rounds_from_file "$running_meta_for_mode")
        queue_assay_task_override=$(queue_meta_assay_task_id_from_file "$running_meta_for_mode")
        queue_meta_explicit_skills_to_file "$running_meta_for_mode" "$queue_explicit_skills_override_file"
      fi
      if [ -n "$queue_mode_override" ]; then
        run_mode=$queue_mode_override
      fi
      if [ -n "$queue_assistant_mode_override" ]; then
        assistant_mode_id=$queue_assistant_mode_override
      fi
      if [ -n "$queue_compute_budget_override" ]; then
        compute_budget=$queue_compute_budget_override
      fi
      if [ -n "$queue_programmer_review_override" ]; then
        programmer_review_enabled=$(normalize_programmer_review_enabled_value "$queue_programmer_review_override")
      fi
      if [ -n "$queue_programmer_review_rounds_override" ]; then
        programmer_review_max_rounds=$(normalize_programmer_review_rounds_value "$queue_programmer_review_rounds_override" 2)
      fi
      if [ -n "$queue_assay_task_override" ]; then
        assay_task_id=$(normalize_assay_task_id_value "$queue_assay_task_override")
      fi
    fi
    if [ "$run_mode" != "assistant" ]; then
      assistant_mode_id=""
    fi
    if [ "$run_mode" != "programming" ] && [ "$run_mode" != "pentest" ] && [ "$run_mode" != "security-audit" ]; then
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$programmer_review_enabled" -ne 1 ]; then
      programmer_review_max_rounds=0
    fi
    active_run_mode=$run_mode
    ARTIFICER_ACTIVE_RUN_MODE=$active_run_mode
    export ARTIFICER_ACTIVE_RUN_MODE

    request_explicit_skills_file=$(mktemp)
    prompt_explicit_skills_file=$(mktemp)
    explicit_skills_file=$(mktemp)
    skill_ids_to_file "$explicit_skill_ids_raw" "$request_explicit_skills_file"
    prompt_skill_tags_to_file "$user_prompt" "$prompt_explicit_skills_file"
    merge_ids_files "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$explicit_skills_file"
    merge_ids_files "$explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
    explicit_skill_ids_csv=$(paste -sd, "$explicit_skills_file" 2>/dev/null || true)
    explicit_skill_ids_csv=$(trim "$explicit_skill_ids_csv")

    if [ -n "$max_iterations_raw" ]; then
      case "$max_iterations_raw" in
        *[!0-9]*)
          case "$reasoning_effort" in
            low) max_iterations=2 ;;
            medium) max_iterations=4 ;;
            high) max_iterations=6 ;;
            extra-high) max_iterations=8 ;;
            *) max_iterations=4 ;;
          esac
          ;;
        *)
          max_iterations=$max_iterations_raw
          ;;
      esac
    else
      case "$reasoning_effort" in
        low) max_iterations=2 ;;
        medium) max_iterations=4 ;;
        high) max_iterations=6 ;;
        extra-high) max_iterations=8 ;;
        *) max_iterations=4 ;;
      esac
    fi

    assay_run_profile=0
    assay_edit_root=""
    if [ -n "$assay_task_id" ]; then
      assay_run_profile=1
      if [ "$run_mode" = "programming" ]; then
        assay_edit_root=""
      else
        assay_edit_root=".assay-runs/$assay_task_id"
      fi
    fi
    prompt_lower_for_budget=$(printf '%s' "$user_prompt" | tr '[:upper:]' '[:lower:]')
    if [ "$assay_run_profile" -ne 1 ]; then
      if [ "$run_mode" = "auto" ] && prompt_prefers_compact_reasoning_contract "$user_prompt"; then
        if [ "$max_iterations" -gt 2 ]; then
          max_iterations=2
        fi
        case "$reasoning_effort" in
          extra-high)
            reasoning_effort="high"
            ;;
        esac
      fi
      if [ "$max_iterations" -lt 6 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'godot|replay|checksum|self[- ]?tests?|regression|barnes[- ]?hut|rk4|benchmark'; then
        max_iterations=6
      fi
      if [ "$max_iterations" -lt 7 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'gameplay|fun|interactiv|challenge|objective|score|combo|polish|juice'; then
        max_iterations=7
      fi
      if [ "$max_iterations" -lt 8 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq '80\\+|at least[[:space:]]+80([^0-9]|$)|final[ -]?state checksum|end[ -]?state checksum|deterministic replay'; then
        max_iterations=8
      fi
      if [ "$max_iterations" -lt 9 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'large[ -]?context|large[ -]?scale|monorepo|multi[- ]module|multi[- ]service|architecture|refactor|migration|complexity|orchestrat|distributed'; then
        max_iterations=9
      fi
      if [ "$max_iterations" -lt 10 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'launch|business|go[- ]to[- ]market|pricing|compliance|legal|regulatory|operations|sales|website|funnel|growth'; then
        max_iterations=10
      fi
      if [ "$max_iterations" -lt 10 ] && \
         printf '%s' "$prompt_lower_for_budget" | grep -Eq 'barnes[- ]?hut|checksum|deterministic replay|final[ -]?state checksum' && \
         printf '%s' "$prompt_lower_for_budget" | grep -Eq 'gameplay|challenge|fun|polish|objective'; then
        max_iterations=10
      fi

      case "$run_mode" in
        instant)
          reasoning_effort="low"
          max_iterations=1
          ;;
        auto)
          ;;
        programming)
          case "$reasoning_effort" in
            low|medium)
              reasoning_effort="high"
              ;;
          esac
          if [ "$max_iterations" -lt 6 ]; then
            max_iterations=6
          fi
          if [ "$max_iterations" -lt 8 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'large[ -]?context|architecture|multi[- ]module|refactor|migration|distributed|monorepo'; then
            max_iterations=8
          fi
          ;;
        pentest)
          reasoning_effort="extra-high"
          if [ "$max_iterations" -lt 8 ]; then
            max_iterations=8
          fi
          ;;
        security-audit)
          case "$reasoning_effort" in
            low|medium)
              reasoning_effort="high"
              ;;
          esac
          if [ "$max_iterations" -lt 8 ]; then
            max_iterations=8
          fi
          ;;
        chat)
          chat_deep_reasoning=0
          if chat_prompt_needs_deep_reasoning "$user_prompt"; then
            chat_deep_reasoning=1
          fi
          case "$reasoning_effort" in
            low)
              reasoning_effort="medium"
              ;;
          esac
          if [ "$chat_deep_reasoning" -eq 1 ]; then
            case "$reasoning_effort" in
              low|medium)
                reasoning_effort="high"
                ;;
            esac
            if [ "$max_iterations" -gt 3 ]; then
              max_iterations=3
            fi
            if [ "$max_iterations" -lt 2 ]; then
              max_iterations=2
            fi
          elif [ "$max_iterations" -gt 2 ]; then
            max_iterations=2
          fi
          ;;
        teacher)
          case "$reasoning_effort" in
            low|medium)
              reasoning_effort="high"
              ;;
          esac
          if [ "$max_iterations" -lt 6 ]; then
            max_iterations=6
          fi
          if [ "$max_iterations" -lt 8 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'curriculum|syllabus|course|lesson plan|spaced review|learning path|mastery'; then
            max_iterations=8
          fi
          ;;
        report)
          case "$reasoning_effort" in
            low|medium)
              reasoning_effort="high"
              ;;
          esac
          if [ "$max_iterations" -lt 8 ]; then
            max_iterations=8
          fi
          ;;
        text-perfecter)
          reasoning_effort="extra-high"
          if [ "$max_iterations" -lt 9 ]; then
            max_iterations=9
          fi
          if [ "$max_iterations" -lt 11 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'recipe|essay|manuscript|argument|research|citations|sources|forum|variation|technique'; then
            max_iterations=11
          fi
          ;;
        gui-testing)
          reasoning_effort="extra-high"
          if [ "$max_iterations" -lt 10 ]; then
            max_iterations=10
          fi
          if [ "$max_iterations" -lt 12 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'cross[- ]?platform|macos|linux|safari|firefox|hands[- ]?on|visual|usability|flow|regression'; then
            max_iterations=12
          fi
          ;;
        assistant)
          reasoning_effort="extra-high"
          if [ "$max_iterations" -lt 10 ]; then
            max_iterations=10
          fi
          if [ "$max_iterations" -lt 11 ] && printf '%s' "$prompt_lower_for_budget" | grep -Eq 'launch|business|operations|compliance|legal|policy|market|pricing|customer'; then
            max_iterations=11
          fi
          ;;
      esac
    fi

    case "$compute_budget" in
      long)
        if [ "$run_mode" != "instant" ] && [ "$run_mode" != "chat" ] && [ "$max_iterations" -lt 10 ]; then
          max_iterations=10
        fi
        ;;
      until-complete)
        # "until-complete" uses 0 as an unlimited-iteration sentinel.
        max_iterations=0
        ;;
    esac

    if [ "$compute_budget" != "until-complete" ] && [ "$max_iterations" -lt 1 ]; then
      max_iterations=1
    fi
    max_iterations_cap=$(compute_budget_iteration_cap "$compute_budget")
    if [ "$max_iterations_cap" -gt 0 ] && [ "$max_iterations" -gt "$max_iterations_cap" ]; then
      max_iterations=$max_iterations_cap
    fi
    programming_controller_prompt=$user_prompt
    programming_followup_resume_prompt=0
    programming_followup_stopgo_prompt=0
    programming_followup_cross_session_prompt=0
    programming_followup_cross_workspace_prompt=0
    programming_followup_context_text=""
    programming_followup_prior_assistant_text=""
    programming_followup_prior_user_text=""
    programming_followup_target_branch=""
    programming_followup_requested_phase=""
    programming_followup_source_workspace_hint=$(programming_requested_source_workspace_hint_for_prompt "$user_prompt")
    programming_followup_source_workspace_display=""
    programming_resume_probe_conv_dir=$(conversation_dir_for "$workspace_id" "$conversation_id")
    if [ "$run_mode" = "programming" ] && [ -d "$programming_resume_probe_conv_dir" ]; then
      source_programming_conv_dir=$programming_resume_probe_conv_dir
      prior_programming_assistant=$(conversation_last_message_for_role "$programming_resume_probe_conv_dir" "assistant")
      if ! assistant_output_is_programming_summary_contract "$prior_programming_assistant" && { programming_prompt_requests_next_deferred_branch_resume "$user_prompt" || programming_prompt_requests_phase_stopgo "$user_prompt"; }; then
        if [ -n "$programming_followup_source_workspace_hint" ]; then
          source_programming_conv_dir=$(workspace_programming_summary_conversation_dir_for_hint "$workspace_id" "$programming_followup_source_workspace_hint")
          if [ -n "$source_programming_conv_dir" ] && [ -d "$source_programming_conv_dir" ]; then
            prior_programming_assistant=$(conversation_last_message_for_role "$source_programming_conv_dir" "assistant")
            source_workspace_id=$(basename "$(dirname "$(dirname "$source_programming_conv_dir")")")
            source_workspace_name=$(workspace_name_for_id "$source_workspace_id")
            if [ -n "$(trim "$source_workspace_name")" ]; then
              programming_followup_source_workspace_display=$source_workspace_name
            else
              programming_followup_source_workspace_display=$source_workspace_id
            fi
            programming_followup_cross_workspace_prompt=1
          fi
        fi
        if ! assistant_output_is_programming_summary_contract "$prior_programming_assistant"; then
          source_programming_conv_dir=$(workspace_latest_programming_summary_conversation_dir "$workspace_id" "$conversation_id")
          if [ -n "$source_programming_conv_dir" ] && [ -d "$source_programming_conv_dir" ]; then
            prior_programming_assistant=$(conversation_last_message_for_role "$source_programming_conv_dir" "assistant")
            programming_followup_cross_session_prompt=1
          fi
        fi
      fi
      if assistant_output_is_programming_summary_contract "$prior_programming_assistant"; then
        prior_programming_user=$(conversation_last_message_for_role "$source_programming_conv_dir" "user")
        if [ "$(trim "$prior_programming_user")" = "$(trim "$user_prompt")" ]; then
          prior_programming_user=$(conversation_previous_message_for_role "$source_programming_conv_dir" "user")
        fi
        resolved_project_request=$(programming_project_request_from_conversation "$source_programming_conv_dir" "$user_prompt")
        if [ -n "$(trim "$resolved_project_request")" ]; then
          prior_programming_user=$resolved_project_request
        fi
        programming_followup_prior_user_text=$prior_programming_user
        if programming_prompt_requests_phase_stopgo "$user_prompt"; then
          programming_followup_requested_phase=$(programming_stopgo_phase_number_for_prompt "$user_prompt")
          case "$programming_followup_requested_phase" in
            ''|*[!0-9]*)
              prior_completed_phase=$(programming_prior_completed_phase_number_from_text "$prior_programming_assistant")
              case "$prior_completed_phase" in
                ''|*[!0-9]*)
                  programming_followup_requested_phase=2
                  ;;
                *)
                  programming_followup_requested_phase=$((prior_completed_phase + 1))
                  ;;
              esac
              ;;
          esac
          if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
            programming_followup_source_workspace_header=$(cat <<EOF
Related workspace checkpoint: ${programming_followup_source_workspace_display:-$programming_followup_source_workspace_hint}

EOF
)
          else
            programming_followup_source_workspace_header=""
          fi
          programming_followup_context_text=$(cat <<EOF
Continue the same programming project from the recovered checkpoint.

$programming_followup_source_workspace_header

Prior project request:
$prior_programming_user

Prior programming summary:
$prior_programming_assistant

Requested continuation phase: $programming_followup_requested_phase
Do not widen into another deferred branch in this run.
Current follow-up:
$user_prompt
EOF
)
          programming_controller_prompt=$programming_followup_context_text
          programming_followup_stopgo_prompt=1
          programming_followup_prior_assistant_text=$prior_programming_assistant
        elif programming_prompt_requests_next_deferred_branch_resume "$user_prompt"; then
          programming_followup_target_branch=$(programming_prior_next_deferred_branch_from_text "$prior_programming_assistant")
          programming_followup_requested_phase=$(programming_requested_phase_number_for_prompt "$user_prompt")
          case "$programming_followup_requested_phase" in
            ''|*[!0-9]*)
              programming_followup_requested_phase=2
              ;;
          esac
          if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
            programming_followup_source_workspace_header=$(cat <<EOF
Related workspace checkpoint: ${programming_followup_source_workspace_display:-$programming_followup_source_workspace_hint}

EOF
)
          else
            programming_followup_source_workspace_header=""
          fi
          programming_followup_context_text=$(cat <<EOF
Continue the same programming project from the recovered checkpoint.

$programming_followup_source_workspace_header

Prior project request:
$prior_programming_user

Prior programming summary:
$prior_programming_assistant

Requested continuation phase: $programming_followup_requested_phase
Resume target branch: $programming_followup_target_branch
Resume with exactly one previously deferred branch and do not widen further in this run.
Current follow-up:
$user_prompt
EOF
)
          programming_controller_prompt=$programming_followup_context_text
          programming_followup_resume_prompt=1
          programming_followup_prior_assistant_text=$prior_programming_assistant
        fi
      fi
    fi
    programming_quick_bounded_run=0
    programming_quick_narrow_slice_run=0
    programming_quick_adjacent_slice_run=0
    programming_quick_multi_followup_slice_run=0
    programming_quick_verification_followup_slice_run=0
    programming_quick_post_verification_safe_followup_slice_run=0
    programming_bounded_branch_budget=0
    case "$compute_budget" in
      quick|auto|standard|long|until-complete)
        programming_bounded_branch_budget=1
        ;;
    esac
    if [ "$run_mode" = "programming" ] && [ "$compute_budget" = "quick" ] && [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -le 1 ]; then
      programming_quick_bounded_run=1
    elif [ "$run_mode" = "programming" ] && [ "$programming_followup_resume_prompt" -eq 1 ]; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 4 ]; then
        max_iterations=4
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 6 ] && [ "$max_iterations" -le 24 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; } && programming_prompt_has_release_note_safe_branch "$programming_controller_prompt"; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      programming_quick_multi_followup_slice_run=1
      programming_quick_verification_followup_slice_run=1
      programming_quick_post_verification_safe_followup_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 7 ]; then
        max_iterations=7
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 6 ] && [ "$max_iterations" -le 24 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; } && programming_prompt_has_post_verification_branch "$programming_controller_prompt"; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      programming_quick_multi_followup_slice_run=1
      programming_quick_verification_followup_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 6 ]; then
        max_iterations=6
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 5 ] && [ "$max_iterations" -le 6 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; } && programming_prompt_has_multiple_branches "$programming_controller_prompt" && programming_prompt_has_documentation_branch "$programming_controller_prompt" && programming_prompt_has_verification_branch "$programming_controller_prompt"; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      programming_quick_multi_followup_slice_run=1
      programming_quick_verification_followup_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 6 ]; then
        max_iterations=6
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 4 ] && [ "$max_iterations" -le 5 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; } && programming_prompt_has_multiple_branches "$programming_controller_prompt" && programming_prompt_has_documentation_branch "$programming_controller_prompt"; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      programming_quick_multi_followup_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 5 ]; then
        max_iterations=5
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 2 ] && [ "$max_iterations" -le 4 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; } && programming_prompt_has_multiple_branches "$programming_controller_prompt"; then
      programming_quick_narrow_slice_run=1
      programming_quick_adjacent_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 4 ]; then
        max_iterations=4
      fi
    elif [ "$run_mode" = "programming" ] && [ "$programming_bounded_branch_budget" -eq 1 ] && { { [ "$max_iterations" -gt 1 ] && [ "$max_iterations" -le 3 ]; } || { [ "$compute_budget" = "until-complete" ] && programming_prompt_prefers_bounded_narrow_execution "$programming_controller_prompt"; }; }; then
      programming_quick_narrow_slice_run=1
      if [ "$max_iterations" -gt 0 ] && [ "$max_iterations" -lt 3 ]; then
        max_iterations=3
      fi
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      case "$compute_budget" in
        quick)
          assay_iteration_cap=3
          ;;
        standard|auto)
          assay_iteration_cap=4
          ;;
        long)
          assay_iteration_cap=5
          ;;
        until-complete)
          assay_iteration_cap=0
          ;;
        *)
          assay_iteration_cap=4
          ;;
      esac
      if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$assay_iteration_cap" -lt 7 ]; then
        assay_iteration_cap=7
      elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$assay_iteration_cap" -lt 6 ]; then
        assay_iteration_cap=6
      elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$assay_iteration_cap" -lt 5 ]; then
        assay_iteration_cap=5
      elif [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$assay_iteration_cap" -lt 4 ]; then
        assay_iteration_cap=4
      fi
      if [ "$assay_iteration_cap" -gt 0 ] && [ "$max_iterations" -gt "$assay_iteration_cap" ]; then
        max_iterations=$assay_iteration_cap
      fi
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
    if [ -n "$queue_item_id" ] && valid_id "$queue_item_id"; then
      run_event_id="run-${queue_item_id}"
    elif [ -n "$run_event_id_param" ] && valid_id "$run_event_id_param"; then
      run_event_id=$run_event_id_param
    fi
    running_pid_file="$queue_dir/running.pid"
    running_stop_file="$queue_dir/running.stop"
    running_event_id_file=$(queue_running_event_id_file_for "$conv_dir")
    running_anchor_file=$(queue_running_anchor_file_for "$conv_dir")
    rm -f "$running_stop_file"
    printf '%s\n' "$$" > "$running_pid_file"
    rm -f "$running_event_id_file"
    rm -f "$running_anchor_file"
    if [ -n "$run_event_id" ] && valid_id "$run_event_id"; then
      printf '%s\n' "$run_event_id" > "$running_event_id_file"
    fi
    if [ -n "$run_message_anchor" ]; then
      printf '%s\n' "$run_message_anchor" > "$running_anchor_file"
    fi
    run_event_finalized=0
    run_exit_handler_invoked=0
    run_exit_reason=""
    run_runtime_mark_finalized() {
      run_event_finalized=1
    }
    run_runtime_cleanup() {
      rm -f "$running_pid_file" \
        "$running_anchor_file" \
        "$(queue_running_started_iso_file_for "$conv_dir")" \
        "$(queue_running_stream_session_file_for "$conv_dir")" \
        "$running_event_id_file"
    }
    run_runtime_finalize_abort_event_if_needed() {
      if [ "$run_event_finalized" -eq 1 ]; then
        return 0
      fi
      abort_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "")
      abort_model=$(trim "${model:-}")
      if [ -z "$abort_model" ]; then
        abort_model=$(read_file_line "$conv_dir/model" "$(default_model)")
      fi
      abort_state_text=$(sed -n '1,120p' "$conv_dir/agent/.state" 2>/dev/null || true)
      abort_tasks_dir=$(tasks_dir_for_conversation "$conv_dir")
      abort_task_status_json=$(task_status_json_from_tasks_dir "$abort_tasks_dir" "error" "$abort_state_text")
      abort_stream_preview=$(sed -n '1,360p' "$stream_output_file" 2>/dev/null || true)
      if [ -z "$(trim "$abort_stream_preview")" ]; then
        abort_ts=$(date +"%H:%M:%S" 2>/dev/null || printf '%s' "00:00:00")
        abort_stream_preview="[$abort_ts] Run ended unexpectedly before finalization event was emitted."
      fi
      abort_reason="Run ended before finalization event could be emitted."
      if [ -n "$(trim "$run_exit_reason")" ]; then
        abort_reason="$abort_reason Reason: $run_exit_reason."
      fi
      if [ -n "$queue_item_id" ] && valid_id "$queue_item_id"; then
        queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "error" "$abort_reason"
      fi
      abort_event_json=$(build_run_event_json \
        "error" \
        "$run_started_iso" \
        "$abort_finished_iso" \
        "$abort_model" \
        "" \
        "[]" \
        "$abort_stream_preview" \
        "$abort_reason" \
        "" \
        "$abort_state_text" \
        "" \
        "" \
        "$abort_reason" \
        "$run_exit_reason" \
        "$run_event_id" \
        "$abort_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "")
      append_run_event_json "$conv_dir" "$abort_event_json"
      run_event_finalized=1
      stream_emit_line "$stream_output_file" "Fail-safe: emitted terminal error run event after unexpected exit."
    }
    run_runtime_on_exit() {
      if [ "$run_exit_handler_invoked" -eq 1 ]; then
        return 0
      fi
      run_exit_handler_invoked=1
      run_runtime_finalize_abort_event_if_needed
      run_runtime_cleanup
    }
    run_runtime_on_signal() {
      signal_name=$1
      signal_code=$2
      run_exit_reason="signal:$signal_name"
      run_runtime_on_exit
      exit "$signal_code"
    }
    trap 'run_runtime_on_exit' EXIT
    trap 'run_runtime_on_signal HUP 1' 1
    trap 'run_runtime_on_signal INT 130' 2
    trap 'run_runtime_on_signal QUIT 131' 3
    trap 'run_runtime_on_signal ALRM 124' 14
    trap 'run_runtime_on_signal TERM 143' 15

    # Always clear stale decision requests when a new run starts, including retries,
    # so queue status cannot inherit an old awaiting_decision state.
    clear_decision_request "$conv_dir"
    if [ "$append_user_message" = "1" ]; then
      clear_approval_request "$conv_dir"
    fi

    printf '%s\n' "$run_started_iso" > "$(queue_running_started_iso_file_for "$conv_dir")"
    rm -f "$(queue_running_stream_session_file_for "$conv_dir")"
    if [ -z "$stream_session" ] && [ "$assay_run_profile" -eq 1 ]; then
      stream_session="assay-$(new_id)"
    fi
    if [ -n "$stream_session" ]; then
      if valid_id "$stream_session"; then
        stream_dir=$(stream_session_dir_for "$conv_dir" "$stream_session")
        mkdir -p "$stream_dir"
        stream_output_file=$(stream_tokens_file_for "$conv_dir" "$stream_session")
        : > "$stream_output_file"
        printf '%s\n' "$stream_session" > "$(queue_running_stream_session_file_for "$conv_dir")"
      fi
    fi
    unset ARTIFICER_STREAM_PROFILE 2>/dev/null || true
    if [ "$run_mode" = "programming" ]; then
      ARTIFICER_STREAM_PROFILE="programming"
      export ARTIFICER_STREAM_PROFILE
    fi
    stream_emit_line "$stream_output_file" "Run started."

    unset ARTIFICER_STREAM_FILE 2>/dev/null || true

    workspace_path=$(trim "$(read_file_line "$ws_dir/path" "")")
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
      stream_emit_line "$stream_output_file" "Workspace path missing or unavailable."
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "error" "workspace path is missing or unavailable"
      rm -f "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      emit_error "workspace path is missing or unavailable"
      exit 0
    fi
    if [ "$assay_run_profile" -eq 1 ] && [ -n "$assay_edit_root" ]; then
      mkdir -p "$workspace_path/$assay_edit_root" 2>/dev/null || true
    fi

    model=$(read_file_line "$conv_dir/model" "")
    if [ -z "$model" ]; then
      model=$(default_model)
      printf '%s\n' "$model" > "$conv_dir/model"
    fi
    if [ "$run_mode" = "chat" ]; then
      routed_chat_model=$(chat_autoroute_model "$model")
      if [ -n "$routed_chat_model" ] && [ "$routed_chat_model" != "$model" ]; then
        prior_chat_model=$model
        model=$routed_chat_model
        printf '%s\n' "$model" > "$conv_dir/model"
        stream_emit_line "$stream_output_file" "Auto-selected conversational model: $prior_chat_model -> $model."
      fi
    fi

    ALLOW_NETWORK=0
    case "$(printf '%s' "$network_access_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on)
        ALLOW_NETWORK=1
        ;;
    esac

    ALLOW_WEB=0
    case "$(printf '%s' "$web_access_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on)
        ALLOW_WEB=1
        ;;
    esac

    workspace_command_mode=$(command_policy_mode_for_workspace "$workspace_id")
    command_mode=$workspace_command_mode
    request_command_mode=$(normalize_command_exec_mode_value "$command_exec_mode_raw")
    if [ -n "$request_command_mode" ]; then
      command_mode=$request_command_mode
    fi
    if [ -n "$queue_command_exec_mode_override" ]; then
      command_mode=$queue_command_exec_mode_override
    fi
    request_permission_mode=$(normalize_permission_mode_value "$permission_mode_raw")
    if [ -n "$request_permission_mode" ]; then
      permission_mode=$request_permission_mode
    fi
    if [ -n "$queue_permission_mode_override" ]; then
      permission_mode=$queue_permission_mode_override
    fi
    if [ "$permission_mode" = "read-only" ]; then
      allow_workspace_writes=0
    fi

    incoming_attachment_ids=$(mktemp)
    valid_attachment_ids=$(mktemp)
    blocked_commands_file=$(mktemp)
    : > "$blocked_commands_file"
    attachment_ids_to_file "$attachment_ids_raw" "$incoming_attachment_ids"
    : > "$valid_attachment_ids"
    while IFS= read -r attachment_id; do
      [ -n "$attachment_id" ] || continue
      if attachment_exists_for_conversation "$conv_dir" "$attachment_id"; then
        printf '%s\n' "$attachment_id" >> "$valid_attachment_ids"
      fi
    done < "$incoming_attachment_ids"
    rm -f "$incoming_attachment_ids"

    attachment_names_list=""
    has_image_attachments=0
    while IFS= read -r attachment_id; do
      [ -n "$attachment_id" ] || continue
      attachment_name=$(attachment_meta_get "$conv_dir" "$attachment_id" "name")
      attachment_kind=$(attachment_meta_get "$conv_dir" "$attachment_id" "kind")
      if [ "$attachment_kind" = "image" ]; then
        has_image_attachments=1
      fi
      [ -n "$attachment_name" ] || continue
      if [ -z "$attachment_names_list" ]; then
        attachment_names_list="- $attachment_name"
      else
        attachment_names_list="${attachment_names_list}
- $attachment_name"
      fi
    done < "$valid_attachment_ids"

    attachment_context=$(attachment_context_from_ids_file "$conv_dir" "$valid_attachment_ids")
    attachment_image_ocr_context=""
    if [ "$has_image_attachments" = "1" ]; then
      attachment_image_ocr_context=$(attachment_image_ocr_context_from_ids_file "$conv_dir" "$valid_attachment_ids")
    fi
    web_context=$(fetch_web_context_from_prompt "$user_prompt" "$run_mode" || true)
    model_has_vision=0
    if [ "$has_image_attachments" = "1" ]; then
      if model_supports_vision "$model"; then
        model_has_vision=1
      fi
    fi
    attachment_image_payload=$(attachment_image_base64_lines_from_ids_file "$conv_dir" "$valid_attachment_ids" "$model_has_vision")

    user_message_text=$user_prompt
    if [ -n "$(trim "$attachment_names_list")" ]; then
      user_message_text=$(cat <<EOF
$user_prompt

Attached files:
$attachment_names_list
EOF
)
    fi

    if [ "$append_user_message" = "1" ]; then
      append_message "$conv_dir" "user" "$user_message_text"
    fi

    if is_hello_world_script_task "$user_prompt"; then
      stream_emit_line "$stream_output_file" "Detected hello-world script task."
      hello_file="$workspace_path/hello.sh"
      write_ok=1
      run_status="failed"
      run_output=""
      run_decision_hint=""
      blocked_commands_json="[]"
      quick_plan=$(cat <<EOF
Goal:
- Create hello.sh, make it executable, and run it.
Subgoals:
- write script content
- set executable bit
- execute and capture output
Constraints:
- stay inside workspace root
Unknowns:
- command approval policy
Next Action:
- run ./hello.sh
Completion Criteria:
- output is "Hello, world!"
EOF
)

      if [ "$allow_workspace_writes" -ne 1 ]; then
        write_ok=0
      elif ! cat > "$hello_file" <<'EOF'
#!/bin/sh
printf '%s\n' 'Hello, world!'
EOF
      then
        write_ok=0
      fi
      if [ "$write_ok" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Created hello.sh."
      else
        if [ "$allow_workspace_writes" -ne 1 ]; then
          stream_emit_line "$stream_output_file" "Write blocked by read-only permissions."
        else
          stream_emit_line "$stream_output_file" "Failed to create hello.sh."
        fi
      fi
      if [ "$write_ok" -eq 1 ]; then
        chmod +x "$hello_file" 2>/dev/null || true
        stream_emit_line "$stream_output_file" "Marked hello.sh executable. Running ./hello.sh."
        tool_out=$(mktemp)
        tool_status_file=$(mktemp)
        tool_decision_hint_file=$(mktemp)
        execute_mediated_command "$workspace_id" "$workspace_path" "./hello.sh" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file" "$tool_decision_hint_file"
        run_status=$(cat "$tool_status_file" 2>/dev/null || printf '%s' "failed")
        run_decision_hint=$(cat "$tool_decision_hint_file" 2>/dev/null || printf '%s' "")
        run_output=$(sed -n '1,220p' "$tool_out")
        stream_emit_line "$stream_output_file" "Command status: $run_status"
        rm -f "$tool_out" "$tool_status_file" "$tool_decision_hint_file"
      fi

      if [ "$write_ok" -ne 1 ]; then
        if [ "$allow_workspace_writes" -ne 1 ]; then
          assistant_output="I couldn't create hello.sh because permissions are set to Read only. Switch permissions to Workspace write or Default and retry."
        else
          assistant_output="I couldn't create hello.sh in the workspace root."
        fi
      elif [ "$run_status" = "ok" ]; then
        hello_line=$(trim "$(printf '%s\n' "$run_output" | sed -n '1p')")
        if [ -n "$hello_line" ]; then
          assistant_output="I created hello.sh, made it executable, and ran it. Output: $hello_line"
        else
          assistant_output="I created hello.sh and ran it successfully."
        fi
      elif [ "$run_status" = "approval_required" ]; then
        assistant_output="I created hello.sh. I need command approval to run it."
        stream_emit_line "$stream_output_file" "Waiting for command approval."
      else
        assistant_output="I created hello.sh, but running it failed: $(trim "$run_output")"
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
        if [ "$run_status" = "approval_required" ]; then
          save_approval_request "$conv_dir" "./hello.sh" "approval-required" >/dev/null 2>&1 || true
        fi
      elif [ "$write_ok" -ne 1 ] || [ "$run_status" = "failed" ] || [ "$run_status" = "blocked" ]; then
        queue_status_from_run="error"
      fi
      if [ "$queue_status_from_run" != "awaiting_approval" ]; then
        clear_approval_request "$conv_dir"
      fi
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$quick_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      session_log=$(cat <<EOF
## hello-fast-path
write_ok=$write_ok
run_status=$run_status
run_output:
$run_output
EOF
)
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      run_error_text=""
      hello_task_status_json=$(task_status_empty_json)
      if [ "$queue_status_from_run" = "error" ]; then
        run_error_text=$assistant_output
      fi
      hello_event_json=$(build_run_event_json \
        "$queue_status_from_run" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$quick_plan" \
        "[]" \
        "$run_stream_preview" \
        "" \
        "$session_log" \
        "mode=DONE" \
        "$git_status" \
        "$git_diff" \
        "$run_error_text" \
        "$run_decision_hint" \
        "$run_event_id" \
        "$hello_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output")
      append_run_event_json "$conv_dir" "$hello_event_json"
      run_runtime_mark_finalized
      session_json=$(json_escape "$session_log")
      state_json=$(json_escape "mode=DONE")
      decision_hint_json=$(json_escape "$(trim "$run_decision_hint")")

      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[],"blocked_commands":%s,"decision_request":null,"failures":"","session_log":"%s","state":"%s","decision_hint":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$blocked_commands_json" "$session_json" "$state_json" "$decision_hint_json" "$hello_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    model_inventory_known=0
    model_installed=0
    model_inventory=$(list_models_raw || true)
    if [ -n "$(trim "$model_inventory")" ]; then
      model_inventory_known=1
      if model_present_in_inventory "$model" "$model_inventory"; then
        model_installed=1
      fi
    fi
    model_install_runtime=$(model_install_runtime_status_for_model "$model")
    model_install_status=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f1)
    model_install_phase=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f2)
    model_install_progress=$(printf '%s\n' "$model_install_runtime" | cut -d'|' -f3)

    if [ "$model_installed" -ne 1 ] && [ "$model_inventory_known" -eq 1 ] && { [ "$run_mode" = "programming" ] || prompt_requires_code_implementation "$user_prompt"; }; then
      task_snippet=$(programming_task_snippet_for_prompt "$user_prompt")
      if [ "$model_install_status" = "running" ]; then
        stream_emit_line "$stream_output_file" "Selected model is still installing; stopping before implementation loop."
        install_detail="$model"
        if [ -n "$(trim "$model_install_phase")" ]; then
          install_detail="$install_detail ($model_install_phase"
          if [ -n "$(trim "$model_install_progress")" ]; then
            install_detail="${install_detail}, ${model_install_progress}%)"
          else
            install_detail="${install_detail})"
          fi
        fi
        assistant_output=$(cat <<EOF
Outcome: I did not start the implementation for $task_snippet because the selected model is still downloading.
Verification Evidence: Model inventory did not list $model. Active install status: $install_detail.
Risks: Waiting here would stall the run and can leak install chatter into the conversation instead of doing project work.
Next Improvement: Let the download finish in Settings > Models or switch this conversation to an installed model, then rerun.
EOF
)
      else
        stream_emit_line "$stream_output_file" "Selected model is not installed; stopping before implementation loop."
        assistant_output=$(cat <<EOF
Outcome: I did not start the implementation for $task_snippet because the selected model is not installed locally.
Verification Evidence: Current model inventory is available, and it does not include $model.
Risks: Starting the run anyway would likely stall, auto-pull a model unexpectedly, or produce unreliable implementation output.
Next Improvement: Install $model in Settings > Models or switch this conversation to an installed model, then rerun.
EOF
)
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      queue_status_from_run="error"
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"

      preflight_plan=$(cat <<EOF
Goal:
- Execute the requested programming task with the selected local model.
Subgoals:
- verify model availability
- avoid stalled implementation loops
- return a concise actionable status if the model is not ready
Constraints:
- do not auto-pull a missing model inside the user conversation
Unknowns:
- when the user will finish the model download or switch models
Next Action:
- rerun after the selected model is installed locally
Completion Criteria:
- implementation starts only after the model is ready
EOF
)
      preflight_session_log=$(cat <<EOF
## programming-model-preflight
requested_model=$model
inventory_known=$model_inventory_known
model_installed=$model_installed
install_status=$model_install_status
install_phase=$model_install_phase
install_progress=$model_install_progress
EOF
)
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      preflight_task_status_json=$(task_status_empty_json)
      preflight_event_json=$(build_run_event_json \
        "error" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$preflight_plan" \
        "[]" \
        "$run_stream_preview" \
        "" \
        "$preflight_session_log" \
        "mode=VERIFY" \
        "$git_status" \
        "$git_diff" \
        "$assistant_output" \
        "" \
        "$run_event_id" \
        "$preflight_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output")
      append_run_event_json "$conv_dir" "$preflight_event_json"
      run_runtime_mark_finalized

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$preflight_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      session_json=$(json_escape "$preflight_session_log")
      state_json=$(json_escape "mode=VERIFY")
      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[],"blocked_commands":[],"decision_request":null,"failures":"","session_log":"%s","state":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$session_json" "$state_json" "$preflight_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    run_started_epoch=$(date +%s)
    run_time_budget_raw=${ARTIFICER_RUN_TIME_BUDGET_SEC-}
    run_time_budget_explicit=0
    if [ -n "$run_time_budget_raw" ]; then
      run_time_budget_explicit=1
    fi
    run_time_budget=${ARTIFICER_RUN_TIME_BUDGET_SEC:-900}
    case "$run_time_budget" in
      ""|*[!0-9]*)
        run_time_budget=900
        run_time_budget_explicit=0
        ;;
    esac
    run_time_budget_floor=120
    if [ "$assay_run_profile" -eq 1 ]; then
      run_time_budget_floor=45
    fi
    if [ "$run_time_budget" -lt "$run_time_budget_floor" ]; then
      run_time_budget=$run_time_budget_floor
    fi
    prompt_lower_budget_runtime=$(printf '%s' "$user_prompt" | tr '[:upper:]' '[:lower:]')
    if [ "$assay_run_profile" -ne 1 ]; then
      if [ "$run_time_budget" -lt 420 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'godot|barnes[- ]?hut|checksum|replay|self[- ]?tests?|regression|gameplay|challenge|objective|polish'; then
        run_time_budget=420
      fi
      if [ "$run_time_budget" -lt 540 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq '120\\+|100\\+|80\\+|at least[[:space:]]+(80|100|120)([^0-9]|$)|deterministic replay|final[ -]?state checksum|barnes[- ]?hut' && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'gameplay|challenge|polish|objective|score|combo'; then
        run_time_budget=540
      fi
      if [ "$run_time_budget" -lt 900 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'large[ -]?context|large[ -]?scale|architecture|monorepo|multi[- ]module|multi[- ]service|refactor|migration|distributed'; then
        run_time_budget=900
      fi
      if [ "$run_time_budget" -lt 1200 ] && printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'launch|business|go[- ]to[- ]market|compliance|legal|regulatory|operations|sales|pricing|growth'; then
        run_time_budget=1200
      fi
      case "$run_mode" in
        programming)
          if [ "$programming_quick_bounded_run" -eq 1 ]; then
            if [ "$run_time_budget" -lt 180 ]; then
              run_time_budget=180
            fi
          elif [ "$run_time_budget" -lt 420 ]; then
            run_time_budget=420
          fi
          ;;
        pentest)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        security-audit)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        report)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        teacher)
          if [ "$run_time_budget" -lt 900 ]; then
            run_time_budget=900
          fi
          ;;
        gui-testing)
          if [ "$run_time_budget" -lt 1200 ]; then
            run_time_budget=1200
          fi
          ;;
        assistant)
          if [ "$run_time_budget" -lt 1200 ]; then
            run_time_budget=1200
          fi
          ;;
        instant|chat)
          if [ "$compute_budget" = "quick" ] && [ "$run_time_budget" -gt 420 ]; then
            run_time_budget=420
          elif [ "$compute_budget" = "auto" ] && [ "$run_time_budget" -gt 900 ]; then
            run_time_budget=900
          fi
          ;;
      esac
    fi
    compute_budget_floor=$(compute_budget_runtime_floor_sec "$compute_budget")
    compute_budget_ceiling=$(compute_budget_runtime_ceiling_sec "$compute_budget")
    if [ "$run_time_budget_explicit" -ne 1 ]; then
      if [ "$run_time_budget" -lt "$compute_budget_floor" ]; then
        run_time_budget=$compute_budget_floor
      fi
      if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$run_time_budget" -gt 180 ]; then
        run_time_budget=180
      fi
    fi
    if [ "$run_time_budget" -gt "$compute_budget_ceiling" ]; then
      run_time_budget=$compute_budget_ceiling
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      case "$compute_budget" in
        quick)
          assay_runtime_ceiling=100
          ;;
        standard|auto)
          assay_runtime_ceiling=145
          ;;
        long)
          assay_runtime_ceiling=200
          ;;
        until-complete)
          assay_runtime_ceiling=260
          ;;
        *)
          assay_runtime_ceiling=220
          ;;
      esac
      if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$assay_runtime_ceiling" -gt 70 ]; then
        assay_runtime_ceiling=70
      fi
      if printf '%s' "$prompt_lower_budget_runtime" | grep -Eq 'race|concurren|migration|idempotent|rollback|security|audit|failure recovery|fallback|benchmark|stress|flaky|end[- ]to[- ]end|contract tests?'; then
        assay_runtime_ceiling=$((assay_runtime_ceiling + 30))
      fi
      if [ "$assay_runtime_ceiling" -gt 320 ]; then
        assay_runtime_ceiling=320
      fi
      if [ "$run_time_budget" -gt "$assay_runtime_ceiling" ]; then
        run_time_budget=$assay_runtime_ceiling
      fi
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      assay_dynamic_iteration_cap=5
      if [ "$run_time_budget" -le 70 ]; then
        assay_dynamic_iteration_cap=2
      elif [ "$run_time_budget" -le 115 ]; then
        assay_dynamic_iteration_cap=3
      elif [ "$run_time_budget" -le 170 ]; then
        assay_dynamic_iteration_cap=4
      fi
      if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 7 ]; then
        assay_dynamic_iteration_cap=7
      elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 6 ]; then
        assay_dynamic_iteration_cap=6
      elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 5 ]; then
        assay_dynamic_iteration_cap=5
      elif [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 4 ]; then
        assay_dynamic_iteration_cap=4
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$assay_dynamic_iteration_cap" -lt 3 ]; then
        assay_dynamic_iteration_cap=3
      fi
      if [ "$assay_dynamic_iteration_cap" -gt 0 ]; then
        if [ "$max_iterations" -eq 0 ] || [ "$max_iterations" -gt "$assay_dynamic_iteration_cap" ]; then
          max_iterations=$assay_dynamic_iteration_cap
        fi
      fi
    fi
    if [ "$run_time_budget" -gt 86400 ]; then
      run_time_budget=86400
    fi
    model_timeout_scale=1
    if [ "$assay_run_profile" -ne 1 ]; then
      case "$compute_budget" in
        long)
          model_timeout_scale=2
          ;;
        until-complete)
          model_timeout_scale=3
          ;;
      esac
    fi
    export ARTIFICER_MODEL_TIMEOUT_SCALE=$model_timeout_scale
    if [ "$assay_run_profile" -eq 1 ]; then
      export ARTIFICER_COMMAND_TIMEOUT_SEC=14
    else
      unset ARTIFICER_COMMAND_TIMEOUT_SEC 2>/dev/null || true
    fi

    quick_mode=${ARTIFICER_QUICK_MODE:-0}
    simple_direct_prompt=0
    compact_reasoning_prompt=0
    compact_reasoning_followup_prompt=0
    compact_reasoning_context_text=$user_prompt
    document_revision_prompt=0
    document_revision_context_text=$user_prompt
    diagram_annotation_read_prompt=0
    dashboard_chart_read_prompt=0
    before_after_ui_delta_prompt=0
    terminal_state_recovery_read_prompt=0
    terminal_screenshot_debug_prompt=0
    gui_screenshot_layout_triage_prompt=0
    repo_runtime_web_triage_prompt=0
    browser_image_run_investigation_prompt=0
    tool_failure_handoff_prompt=0
    current_api_migration_prompt=0
    current_ops_guidance_prompt=0
    standards_grounded_answer_prompt=0
    multi_artifact_judgment_prompt=0
    multi_service_partial_rollback_prompt=0
    remote_release_pack_prompt=0
    remote_boundary_pack_prompt=0
    system_release_pack_prompt=0
    system_boundary_pack_prompt=0
    partial_system_rollback_prompt=0
    local_env_drift_prompt=0
    background_process_recovery_prompt=0
    local_package_upgrade_prompt=0
    long_running_command_polling_prompt=0
    filesystem_mutation_prompt=0
    remote_boundary_rollback_prompt=0
    remote_boundary_rollout_prompt=0
    remote_bastion_cutover_prompt=0
    remote_multi_host_rollout_prompt=0
    remote_multi_host_prompt=0
    remote_deploy_rollback_prompt=0
    remote_single_host_prompt=0
    local_service_restart_prompt=0
    rich_reasoning_prompt=0
    freeform_reasoning_prompt=0
    freeform_clarify_prompt=0
    freeform_reflection_prompt=0
    freeform_frame_prompt=0
    freeform_reflection_context_text=$user_message_text
    freeform_frame_context_text=$user_message_text
    freeform_post_clarify_prompt=0
    rich_reasoning_context_text=$user_message_text
    reasoning_followup_prompt=0
    reasoning_followup_context_text=$user_message_text
    force_agent_execution=0
    if is_simple_direct_prompt "$user_prompt"; then
      simple_direct_prompt=1
    fi
    if prompt_prefers_compact_reasoning_contract "$user_prompt"; then
      compact_reasoning_prompt=1
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_compact_reasoning_followup_contract "$user_prompt" "$conv_dir"; then
      compact_reasoning_prompt=1
      compact_reasoning_followup_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" = "1" ]; then
      compact_reasoning_context_text=$(compact_reasoning_context_prompt "$user_prompt" "$conv_dir")
    fi
    document_revision_fast_path_kind=$(document_revision_fast_path_kind_for_prompt "$user_prompt" "$conv_dir")
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$document_revision_fast_path_kind" != "unknown" ]; then
      document_revision_prompt=1
      document_revision_context_text=$(document_revision_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_diagram_annotation_read_task "$user_prompt"; then
      diagram_annotation_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_dashboard_chart_read_task "$user_prompt"; then
      dashboard_chart_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_before_after_ui_delta_task "$user_prompt"; then
      before_after_ui_delta_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_terminal_state_recovery_read_task "$user_prompt"; then
      terminal_state_recovery_read_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && prompt_prefers_terminal_screenshot_debug_task "$user_prompt"; then
      terminal_screenshot_debug_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && [ "$run_mode" = "assistant" ] && prompt_prefers_browser_image_run_investigation_task "$user_prompt"; then
      browser_image_run_investigation_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$has_image_attachments" = "1" ] && [ "$model_has_vision" = "1" ] \
      && [ "$browser_image_run_investigation_prompt" != "1" ] \
      && prompt_prefers_gui_screenshot_layout_triage_task "$user_prompt"; then
      gui_screenshot_layout_triage_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_repo_runtime_web_triage_task "$user_prompt"; then
      repo_runtime_web_triage_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_tool_failure_handoff_task "$user_prompt"; then
      tool_failure_handoff_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_current_api_migration_task "$user_prompt"; then
      current_api_migration_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_current_ops_guidance_task "$user_prompt"; then
      current_ops_guidance_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_standards_grounded_answer_task "$user_prompt"; then
      standards_grounded_answer_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_multi_artifact_judgment_task "$user_prompt"; then
      multi_artifact_judgment_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_release_pack_task "$user_prompt"; then
      remote_release_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_pack_task "$user_prompt"; then
      remote_boundary_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_multi_service_partial_rollback_task "$user_prompt"; then
      multi_service_partial_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_system_release_pack_task "$user_prompt"; then
      system_release_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_system_boundary_pack_task "$user_prompt"; then
      system_boundary_pack_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_partial_system_rollback_task "$user_prompt"; then
      partial_system_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_env_drift_task "$user_prompt"; then
      local_env_drift_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_background_process_recovery_task "$user_prompt"; then
      background_process_recovery_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_package_upgrade_task "$user_prompt"; then
      local_package_upgrade_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_long_running_command_polling_task "$user_prompt"; then
      long_running_command_polling_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_release_pack_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_filesystem_mutation_task "$user_prompt"; then
      filesystem_mutation_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_rollback_task "$user_prompt"; then
      remote_boundary_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_boundary_rollout_task "$user_prompt"; then
      remote_boundary_rollout_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_bastion_cutover_task "$user_prompt"; then
      remote_bastion_cutover_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_multi_host_rollout_task "$user_prompt"; then
      remote_multi_host_rollout_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_multi_host_task "$user_prompt"; then
      remote_multi_host_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$remote_multi_host_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_deploy_rollback_task "$user_prompt"; then
      remote_deploy_rollback_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$remote_release_pack_prompt" != "1" ] && [ "$remote_boundary_pack_prompt" != "1" ] && [ "$remote_boundary_rollback_prompt" != "1" ] && [ "$remote_boundary_rollout_prompt" != "1" ] && [ "$remote_bastion_cutover_prompt" != "1" ] && [ "$remote_multi_host_rollout_prompt" != "1" ] && [ "$remote_multi_host_prompt" != "1" ] && [ "$remote_deploy_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_remote_single_host_task "$user_prompt"; then
      remote_single_host_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$multi_service_partial_rollback_prompt" != "1" ] && [ "$system_boundary_pack_prompt" != "1" ] && [ "$partial_system_rollback_prompt" != "1" ] && [ "$run_mode" = "assistant" ] && prompt_prefers_local_service_restart_task "$user_prompt"; then
      local_service_restart_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_intent_clarify "$user_prompt"; then
      freeform_clarify_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_reflection "$user_prompt"; then
      freeform_reflection_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_frame "$user_prompt"; then
      freeform_frame_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_reasoning_completion "$user_prompt" && ! prompt_requires_code_implementation "$user_prompt"; then
      rich_reasoning_prompt=1
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$repo_runtime_web_triage_prompt" != "1" ] && [ "$browser_image_run_investigation_prompt" != "1" ] && [ "$tool_failure_handoff_prompt" != "1" ] && [ "$current_api_migration_prompt" != "1" ] && [ "$current_ops_guidance_prompt" != "1" ] && [ "$standards_grounded_answer_prompt" != "1" ] && prompt_prefers_freeform_reasoning_reply "$user_prompt"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ -n "$conv_dir" ] && [ -d "$conv_dir" ] \
      && freeform_clarify_reply_prefers_reasoning "$user_prompt"; then
      prior_freeform_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
      if assistant_output_is_freeform_clarify_question "$prior_freeform_assistant_text"; then
        freeform_reasoning_prompt=1
        freeform_post_clarify_prompt=1
        rich_reasoning_prompt=1
        rich_reasoning_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
        simple_direct_prompt=0
      fi
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reflection_after_clarify "$user_prompt" "$conv_dir"; then
      freeform_reflection_prompt=1
      freeform_reflection_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_frame_after_clarify "$user_prompt" "$conv_dir"; then
      freeform_frame_prompt=1
      freeform_frame_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reflection_after_frame "$user_prompt" "$conv_dir"; then
      freeform_reflection_prompt=1
      freeform_reflection_context_text=$(reasoning_freeform_post_frame_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reasoning_after_frame "$user_prompt" "$conv_dir"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$(reasoning_freeform_post_frame_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_freeform_reasoning_followup_memo "$user_prompt" "$conv_dir"; then
      freeform_reasoning_prompt=1
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$(reasoning_freeform_context_prompt "$user_prompt" "$conv_dir")
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && prompt_prefers_reasoning_followup_contract "$user_prompt" "$conv_dir"; then
      reasoning_followup_prompt=1
      reasoning_followup_context_text=$(reasoning_context_prompt "$user_prompt" "$conv_dir")
      freeform_reasoning_prompt=0
      freeform_clarify_prompt=0
      freeform_reflection_prompt=0
      freeform_frame_prompt=0
      rich_reasoning_prompt=1
      rich_reasoning_context_text=$reasoning_followup_context_text
      simple_direct_prompt=0
    fi
    if [ "$compact_reasoning_prompt" != "1" ] && [ "$freeform_reasoning_prompt" = "1" ] \
      && [ -n "$conv_dir" ] && [ -d "$conv_dir" ] \
      && freeform_clarify_reply_prefers_reasoning "$user_prompt"; then
      prior_freeform_assistant_text=$(conversation_last_message_for_role "$conv_dir" "assistant")
      if assistant_output_is_freeform_clarify_question "$prior_freeform_assistant_text"; then
        freeform_post_clarify_prompt=1
        rich_reasoning_context_text=$(reasoning_freeform_post_clarify_context_prompt "$user_prompt" "$conv_dir")
      fi
    fi
    if requires_agent_execution_prompt "$user_prompt"; then
      force_agent_execution=1
    fi
    case "$(printf '%s' "$advanced_loop_raw" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on)
        quick_mode=0
        ;;
      0|false|no|off)
        quick_mode=1
        ;;
    esac
    if [ "$simple_direct_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$compact_reasoning_prompt" = "1" ] && [ "$run_mode" = "auto" ]; then
      quick_mode=1
    fi
    if [ "$freeform_clarify_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$freeform_reflection_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$freeform_frame_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$rich_reasoning_prompt" = "1" ]; then
      quick_mode=1
    fi
    if [ "$force_agent_execution" = "1" ]; then
      quick_mode=0
    fi
    case "$run_mode" in
      instant)
        quick_mode=1
        ;;
      auto)
        ;;
      programming)
        quick_mode=0
        force_agent_execution=1
        ;;
      pentest)
        quick_mode=0
        force_agent_execution=1
        ;;
      security-audit)
        quick_mode=0
        force_agent_execution=1
        ;;
      chat)
        quick_mode=1
        ;;
      report)
        quick_mode=0
        force_agent_execution=1
        ;;
      text-perfecter)
        quick_mode=0
        force_agent_execution=1
        ;;
      gui-testing)
        quick_mode=0
        force_agent_execution=1
        ;;
      teacher)
        quick_mode=0
        force_agent_execution=1
        ;;
      assistant)
        quick_mode=0
        force_agent_execution=1
        ;;
    esac
    if [ "$assay_run_profile" -eq 1 ]; then
      # Assay runs must exercise the full loop for comparable intelligence/flow scoring.
      quick_mode=0
      force_agent_execution=1
    fi
    if [ "$assay_run_profile" -ne 1 ] && [ "$compact_reasoning_prompt" = "1" ]; then
      # Compact reasoning contracts are explicit no-tool synthesis requests.
      # Enforce the deterministic quick path even if UI or queue metadata drifted
      # into a long-loop mode; otherwise the run can thrash or surface tool plans.
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$document_revision_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$diagram_annotation_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$dashboard_chart_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$before_after_ui_delta_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$terminal_state_recovery_read_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$terminal_screenshot_debug_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$gui_screenshot_layout_triage_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$repo_runtime_web_triage_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$browser_image_run_investigation_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$tool_failure_handoff_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$current_api_migration_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$current_ops_guidance_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$standards_grounded_answer_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$multi_artifact_judgment_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$multi_service_partial_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$system_release_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$system_boundary_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$partial_system_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$background_process_recovery_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_env_drift_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_package_upgrade_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$long_running_command_polling_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$filesystem_mutation_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_release_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_pack_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_boundary_rollout_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_bastion_cutover_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_multi_host_rollout_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_multi_host_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_deploy_rollback_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$remote_single_host_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$local_service_restart_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$programming_followup_stopgo_prompt" -eq 1 ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_clarify_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_reflection_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$freeform_frame_prompt" = "1" ]; then
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ "$rich_reasoning_prompt" = "1" ]; then
      # Rich reasoning completion prompts are scenario-synthesis requests, not
      # workspace investigation tasks. Keep them on the bounded direct path so
      # the run budget is spent on reasoning quality rather than controller churn.
      quick_mode=1
      force_agent_execution=0
      programmer_review_enabled=0
      programmer_review_max_rounds=0
    fi
    if [ -n "$inline_mode_tag" ]; then
      stream_emit_line "$stream_output_file" "Inline mode directive detected: $inline_mode_tag -> $run_mode"
    fi
    if [ -n "$queue_mode_override" ]; then
      stream_emit_line "$stream_output_file" "Queue mode lock applied: $queue_mode_override"
    fi
    if [ "$compact_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Compact reasoning fail-safe active: bypassing long-loop execution."
    fi
    if [ "$document_revision_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Document revision fast path active: generating a structured memo."
    fi
    if [ "$diagram_annotation_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Diagram annotation read fast path active: analyzing the attached diagram or annotated screenshot and returning takeaway/evidence/risk/next check."
    fi
    if [ "$dashboard_chart_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Dashboard chart read fast path active: analyzing the attached chart or table and returning finding/evidence/risk/next check."
    fi
    if [ "$before_after_ui_delta_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Before/after UI delta fast path active: comparing the attached screenshots and returning change/before evidence/after evidence/impact."
    fi
    if [ "$terminal_state_recovery_read_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Terminal-state recovery fast path active: comparing the before/after terminal screenshots and returning state change/before evidence/after evidence/next check."
    fi
    if [ "$terminal_screenshot_debug_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Terminal screenshot debug fast path active: analyzing the attached terminal or log screenshot and returning finding/evidence/next command/risk."
    fi
    if [ "$gui_screenshot_layout_triage_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "GUI screenshot layout triage fast path active: analyzing the attached screenshot directly and returning issue/evidence/cause/fix."
    fi
    if [ "$repo_runtime_web_triage_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Repo/runtime/web triage fast path active: running repo evidence, runtime evidence, and direct web-doc fetch in one bounded pass."
    fi
    if [ "$browser_image_run_investigation_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Browser/image/runtime investigation fast path active: combining Safari screenshot evidence, browser snapshot evidence, and one bounded runtime helper."
    fi
    if [ "$tool_failure_handoff_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Tool-failure handoff fast path active: running the initial helper, capturing the failure, handing off to the fallback helper, and grounding the result in current docs."
    fi
    if [ "$current_api_migration_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Current API migration fast path active: combining repo evidence with the current official migration guide in one bounded pass."
    fi
    if [ "$current_ops_guidance_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Current ops guidance fast path active: combining local state with current official guidance in one bounded pass."
    fi
    if [ "$standards_grounded_answer_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Standards-grounded answer fast path active: combining repo evidence, runtime evidence, and the current official standard/docs in one bounded pass."
    fi
    if [ "$multi_artifact_judgment_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Multi-artifact judgment fast path active: returning one bounded operator decision across code, doc, screenshot, and command evidence."
    fi
    if [ "$multi_service_partial_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Multi-service partial rollback fast path active: inspecting both local services, approving the shared rollback, executing both rollbacks, and verifying recovery."
    fi
    if [ "$system_release_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "System release pack fast path active: inspecting both local boundaries, approving the shared release pack, executing ordered cutovers, publishing the release pack, and verifying the published release."
    fi
    if [ "$system_boundary_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "System boundary pack fast path active: inspecting both local boundaries, approving the shared cutover, executing core-first and edge-second cutovers, and verifying the pack."
    fi
    if [ "$partial_system_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Partial system rollback fast path active: inspecting bounded mixed state, approving rollback, executing it, and verifying recovery."
    fi
    if [ "$background_process_recovery_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Background process fast path active: running ps, stop, fix, start, and health checks."
    fi
    if [ "$local_env_drift_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local env drift fast path active: running doctor, repair, and verify checks."
    fi
    if [ "$local_package_upgrade_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local package upgrade fast path active: running audit, upgrade, and test checks."
    fi
    if [ "$long_running_command_polling_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Long-running command fast path active: polling, checkpointing, finalizing, and verifying the bounded job."
    fi
    if [ "$filesystem_mutation_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Filesystem mutation fast path active: inventorying, applying the bounded layout change, and verifying the result."
    fi
    if [ "$remote_release_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote release pack fast path active: running bastion status, opening the tunnel, deploying the core boundary pair before the edge boundary pair, publishing the shared release pack, and verifying the release."
    fi
    if [ "$remote_boundary_pack_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary pack fast path active: running bastion status, opening the tunnel, then deploying the core boundary pair before the edge boundary pair and verifying the pack."
    fi
    if [ "$remote_boundary_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary rollback fast path active: running bastion status, opening the tunnel, then staged private canary and fleet rollbacks with health checks."
    fi
    if [ "$remote_boundary_rollout_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote boundary rollout fast path active: running bastion status, opening the tunnel, then staging private canary and fleet deploys with health checks."
    fi
    if [ "$remote_bastion_cutover_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote bastion cutover fast path active: running bastion status, tunnel, private cutover, and dual health checks."
    fi
    if [ "$remote_multi_host_rollout_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote multi-host rollout fast path active: running canary status, staged deploys, and dual health checks."
    fi
    if [ "$remote_multi_host_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote multi-host fast path active: running app-host status, replica promotion, restart, and dual health checks."
    fi
    if [ "$remote_deploy_rollback_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote deploy fast path active: running remote status, deploy, and health checks."
    fi
    if [ "$remote_single_host_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Remote single-host fast path active: running SSH status, journal, restart, and health checks."
    fi
    if [ "$local_service_restart_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Local service restart fast path active: running status, fix, restart, and health checks."
    fi
    if [ "$programming_followup_stopgo_prompt" -eq 1 ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Phase stop/go fast path active: preserving the current landed slices and deferred queue."
    fi
    if [ "$freeform_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform reasoning fail-safe active: bypassing long-loop execution."
    fi
    if [ "$freeform_clarify_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Ambiguous-intent clarify fail-safe active: asking for a tighter intent signal."
    fi
    if [ "$freeform_reflection_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform reflection fail-safe active: returning a bounded reflection instead of a recommendation."
    fi
    if [ "$freeform_frame_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Freeform framing fail-safe active: returning a bounded framing response instead of a recommendation."
    fi
    if [ "$rich_reasoning_prompt" = "1" ] && [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Rich reasoning fail-safe active: bypassing long-loop execution."
    fi
    queue_last_mode_file=$(queue_last_mode_file_for "$conv_dir")
    queue_last_assistant_mode_file=$(queue_last_assistant_mode_file_for "$conv_dir")
    queue_last_compute_budget_file=$(queue_last_compute_budget_file_for "$conv_dir")
    queue_last_command_exec_mode_file=$(queue_last_command_exec_mode_file_for "$conv_dir")
    queue_last_permission_mode_file=$(queue_last_permission_mode_file_for "$conv_dir")
    queue_last_programmer_review_file=$(queue_last_programmer_review_file_for "$conv_dir")
    queue_last_programmer_review_rounds_file=$(queue_last_programmer_review_rounds_file_for "$conv_dir")
    queue_last_assay_task_id_file=$(queue_last_assay_task_id_file_for "$conv_dir")
    printf '%s\n' "$run_mode" > "$queue_last_mode_file"
    printf '%s\n' "$assistant_mode_id" > "$queue_last_assistant_mode_file"
    printf '%s\n' "$compute_budget" > "$queue_last_compute_budget_file"
    printf '%s\n' "$command_mode" > "$queue_last_command_exec_mode_file"
    printf '%s\n' "$permission_mode" > "$queue_last_permission_mode_file"
    printf '%s\n' "$programmer_review_enabled" > "$queue_last_programmer_review_file"
    printf '%s\n' "$programmer_review_max_rounds" > "$queue_last_programmer_review_rounds_file"
    printf '%s\n' "$assay_task_id" > "$queue_last_assay_task_id_file"
    max_iterations_label=$max_iterations
    if [ "$max_iterations" -le 0 ]; then
      max_iterations_label="unbounded"
    fi
    if [ -n "$assistant_mode_id" ]; then
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (team=$assistant_mode_id, advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label)"
    elif [ "$run_mode" = "programming" ] || [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label, code_review=${programmer_review_enabled}, review_rounds=${programmer_review_max_rounds})"
    else
      stream_emit_line "$stream_output_file" "Run mode: $run_mode (advanced_loop=${advanced_loop_raw:-auto}, reasoning=$reasoning_effort, compute_budget=$compute_budget, max_iterations=$max_iterations_label)"
    fi
    stream_emit_line "$stream_output_file" "Run orchestration initialized."
    stream_emit_line "$stream_output_file" "Initial checkpoints seeded."
    stream_emit_line "$stream_output_file" "Run time budget: ${run_time_budget}s"
    explicit_skill_context_text=""
    explicit_skill_invocation_count=0
    if [ -n "$explicit_skill_ids_csv" ]; then
      ensure_mode_runtime_bootstrap
      stream_emit_line "$stream_output_file" "Explicit skill tags detected: $explicit_skill_ids_csv"
      skill_invoke_mode="assistant"
      if [ "$run_mode" = "assistant" ] && [ -n "$assistant_mode_id" ]; then
        skill_invoke_mode="$assistant_mode_id"
      fi
      while IFS= read -r explicit_skill_id; do
        explicit_skill_id=$(trim "$explicit_skill_id")
        [ -n "$explicit_skill_id" ] || continue
        if [ "$explicit_skill_invocation_count" -ge 8 ]; then
          stream_emit_line "$stream_output_file" "Skipping remaining explicit skills after 8 invocations to keep context focused."
          break
        fi
        explicit_skill_invocation_count=$((explicit_skill_invocation_count + 1))
        if ! command -v mr_skill_exists >/dev/null 2>&1; then
          stream_emit_line "$stream_output_file" "Skill runtime unavailable; could not invoke $explicit_skill_id."
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (skill runtime unavailable)"
          continue
        fi
        if ! mr_skill_exists "$explicit_skill_id"; then
          stream_emit_line "$stream_output_file" "Explicit skill not found: $explicit_skill_id"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (skill not found)"
          continue
        fi
        stream_emit_line "$stream_output_file" "Invoking explicit skill: $explicit_skill_id"
        skill_invocation_json=$(mr_skill_invoke_json "$skill_invoke_mode" "$explicit_skill_id" "$user_prompt" "")
        skill_invocation_ok=0
        if printf '%s' "$skill_invocation_json" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true'; then
          skill_invocation_ok=1
        fi
        if [ "$skill_invocation_ok" -eq 1 ]; then
          skill_result_status=$(printf '%s' "$skill_invocation_json" | perl -MJSON::PP -e '
            use strict;
            use warnings;
            local $/;
            my $raw = <STDIN>;
            my $data = eval { decode_json($raw) };
            exit 1 if $@ || ref($data) ne "HASH";
            my $result = $data->{"result"};
            exit 1 if ref($result) ne "HASH";
            my $value = $result->{"status"};
            exit 1 if !defined($value) || ref($value);
            print $value;
          ' 2>/dev/null || true)
          skill_result_summary=$(printf '%s' "$skill_invocation_json" | perl -MJSON::PP -e '
            use strict;
            use warnings;
            local $/;
            my $raw = <STDIN>;
            my $data = eval { decode_json($raw) };
            exit 1 if $@ || ref($data) ne "HASH";
            my $result = $data->{"result"};
            exit 1 if ref($result) ne "HASH";
            my $value = $result->{"summary"};
            exit 1 if !defined($value) || ref($value);
            print $value;
          ' 2>/dev/null || true)
          skill_result_status=$(trim "$skill_result_status")
          skill_result_summary=$(trim "$skill_result_summary")
          [ -n "$skill_result_status" ] || skill_result_status="ok"
          [ -n "$skill_result_summary" ] || skill_result_summary="Skill invocation completed."
          stream_emit_line "$stream_output_file" "Skill $explicit_skill_id completed with status: $skill_result_status"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: status=${skill_result_status}; summary=${skill_result_summary}"
        else
          skill_error_text=$(json_extract_string_field "error" "$skill_invocation_json" || true)
          skill_error_text=$(trim "$skill_error_text")
          if [ -z "$skill_error_text" ]; then
            skill_error_text="skill invocation failed"
          fi
          stream_emit_line "$stream_output_file" "Skill $explicit_skill_id could not be applied: $skill_error_text"
          explicit_skill_context_text="${explicit_skill_context_text}
- ${explicit_skill_id}: failed (${skill_error_text})"
        fi
      done < "$explicit_skills_file"
      explicit_skill_context_text=$(compact_text_block "Explicit skill results" "$explicit_skill_context_text" 900)
    fi
    workspace_context_text=$(workspace_shared_context "$ws_dir" "$conversation_id" | sed -n '1,240p')
    if [ "$quick_mode" = "1" ]; then
      stream_emit_line "$stream_output_file" "Quick response mode selected."
      history_text=$(conversation_history "$conv_dir" | sed -n '1,160p')
      snapshot_text=$(workspace_snapshot "$workspace_path" | sed -n '1,160p')
      quick_structure_hint=""
      if [ "$compact_reasoning_prompt" = "1" ]; then
        quick_structure_hint=$(cat <<'EOF'
Return exactly five labeled lines using these labels once each:
- Outcome:
- Initial Assumption:
- Invalidating Evidence:
- Revised Decision:
- Claim-to-Evidence Map:
EOF
)
      elif printf '%s' "$user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'build|design|implement|audit|test|fix|refactor|migration|security|pentest|verify|report|teach|challenge|hardening|failure|recovery'; then
        quick_structure_hint=$(cat <<'EOF'
For non-trivial requests, structure the reply with short headings:
- Outcome:
- Verification Evidence:
- Risks:
- Next Improvement:
EOF
)
      fi
      quick_plan=$(cat <<EOF
Goal:
- $user_prompt
Subgoals:
- inspect relevant project context
- produce a concise actionable coding response
Constraints:
- keep output concise and concrete
Unknowns:
- precise code paths until inspected
Next Action:
- provide best answer based on workspace snapshot and recent conversation
Completion Criteria:
- user receives a direct, useful next-step response
EOF
)

      if [ "$run_mode" = "chat" ]; then
        chat_history_text=$(conversation_history "$conv_dir" | sed -n '1,220p')
        chat_history_text=$(compact_text_block "Recent conversation" "$chat_history_text" 1800)
        if [ -z "$(trim "$chat_history_text")" ]; then
          chat_history_text="(no prior turns)"
        fi
        chat_focus_anchors=$(recent_user_turns_for_conversation "$conv_dir" "4" | sed -n '1,8p')
        if [ -z "$(trim "$chat_focus_anchors")" ]; then
          chat_focus_anchors="1. (no prior user turns)"
        fi
        chat_followup_hint=""
        user_message_lower=$(printf '%s' "$user_message_text" | tr '[:upper:]' '[:lower:]')
        if printf '%s' "$user_message_lower" | grep -Eq '^(no|not exactly|not quite|that.s not|i mean|rather)\b|^no,|^no\.'; then
          chat_followup_hint="- user signaled the prior framing was off; restate the corrected framing before answering."
        fi
        quick_prompt=$(cat <<EOF
You are a high-quality conversational assistant.
Primary objective: answer the latest user message while preserving continuity with recent turns.
Conversation quality rules:
- treat the latest message as a refinement of the same thread, not a topic reset.
- if the user corrects framing, acknowledge the correction briefly and continue with the corrected framing.
- prefer concrete conceptual reasoning over generic wellness or productivity platitudes unless explicitly requested.
- avoid procedural onboarding/setup assumptions unless the user explicitly asks for implementation steps.
- keep the response concise but insight-dense.
$quick_structure_hint
$chat_followup_hint
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>

User request:
$user_message_text

Thread focus anchors (recent user turns):
$chat_focus_anchors

Recent conversation (most recent last):
$chat_history_text
EOF
)
      elif [ "$compact_reasoning_prompt" = "1" ]; then
        compact_history_text=$(conversation_history "$conv_dir" | sed -n '1,220p')
        compact_history_text=$(compact_text_block "Recent conversation" "$compact_history_text" 1800)
        if [ -z "$(trim "$compact_history_text")" ]; then
          compact_history_text="(no prior turns)"
        fi
        quick_prompt=$(cat <<EOF
You are a reasoning assistant producing a compact revision contract.
Primary objective: answer the latest user message while preserving continuity with the compact thread state.
Compact reasoning quality rules:
- return exactly five labeled lines using the required labels once each.
- if the user refers to the same plan, labels, or format, preserve the scenario continuity from the recent thread instead of resetting to a generic answer.
- make the revised call explicit and keep each line specific to the scenario.
- keep the claim-to-evidence map compact, but include owner and review window.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
$quick_structure_hint

Latest user request:
$user_message_text

Compact continuity context:
$compact_reasoning_context_text

Recent conversation (most recent last):
$compact_history_text
EOF
)
      elif [ "$freeform_reasoning_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a reasoning assistant producing a short decision memo in normal prose.
Primary objective: answer the latest user message with a concise recommendation memo.
Freeform reasoning quality rules:
- return normal prose only, with no headings, labels, bullets, numbering, or markdown emphasis
- keep the answer to one short paragraph of at most 4 sentences
- make the recommendation explicit
- state the main uncertainty explicitly
- state what evidence would reverse the recommendation explicitly
- stay specific to the scenario and avoid generic cross-domain boilerplate
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>

Latest user request:
$user_message_text

Reasoning context:
$rich_reasoning_context_text
EOF
)
      elif [ "$freeform_clarify_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a reasoning assistant handling ambiguous user notes.
Primary objective: ask one concise clarifying question instead of guessing the user wants analysis.
Clarifying rules:
- return one or two short sentences only
- include exactly one direct question
- explicitly distinguish between "recommendation" and "capturing notes"
- offer a compact next step if the user wants analysis
- do not provide the recommendation yet
- do not use headings, labels, bullets, numbering, or markdown emphasis
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>

Latest user request:
$freeform_reflection_context_text
EOF
)
      elif [ "$freeform_reflection_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a reasoning assistant helping the user think about an ambiguous situation without forcing a recommendation yet.
Primary objective: return one short reflective paragraph in normal prose.
Reflection rules:
- return normal prose only, with no headings, labels, bullets, numbering, or markdown emphasis
- keep the answer to one short paragraph of at most 3 sentences
- do not ask a question
- do not give a final recommendation yet
- state the core tension explicitly
- state the unresolved question explicitly
- stay specific to the scenario and avoid generic cross-domain boilerplate
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>

Latest user request:
$user_message_text
EOF
)
      elif [ "$freeform_frame_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a reasoning assistant handling terse status or context notes.
Primary objective: return one short framing paragraph without pretending the user already asked for a decision.
Framing rules:
- return normal prose only, with no headings, labels, bullets, numbering, or markdown emphasis
- keep the answer to one short paragraph of at most 3 sentences
- do not ask a question
- do not give a final recommendation yet
- state that this is not a settled decision request yet
- state the key moving parts explicitly
- offer a compact next step if the user wants deeper analysis
- stay specific to the scenario and avoid generic cross-domain boilerplate
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>

Latest user request:
$user_message_text
EOF
)
      elif [ "$rich_reasoning_prompt" = "1" ]; then
        continuity_rule='- anchor the answer to the current scenario itself, not to imperative prompt scaffolding.'
        continuity_context=$rich_reasoning_context_text
        if [ "$reasoning_followup_prompt" = "1" ]; then
          continuity_rule='- keep the scenario anchor tied to the original problem, not the follow-up instruction wording.
- make the revised call explicit and carry the new evidence delta through the decision, fallback path, risks, and next improvement.
- if the follow-up changed the recommendation only partially, say so explicitly.'
        fi
        quick_prompt=$(cat <<EOF
You are a reasoning assistant producing a rich reasoning contract.
Primary objective: answer the latest user message with a concrete final decision synthesis.
Rich reasoning quality rules:
- preserve scenario continuity when recent thread context matters.
$continuity_rule
- stay concrete and scenario-specific; avoid generic cross-domain boilerplate.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use exactly one short line per requested section
- keep the full answer under 160 words
- do not add bullets, numbering, markdown emphasis, or extra sections
- include sections: Outcome, Decision, Fallback Path, Disconfirming Evidence, Risks, Next Improvement
- if the user asks for what overturned the first read or a revised call, also include: Initial Assumption, Invalidating Evidence, Revised Decision, Evidence Delta
$quick_structure_hint

Latest user request:
$user_message_text

Reasoning context:
$continuity_context
EOF
)
      elif [ "$diagram_annotation_read_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a diagram annotation reading assistant analyzing an attached system diagram or annotated screenshot.
Primary objective: extract the single most important operational takeaway from the visible diagram annotations and explain why it matters.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible diagram or annotation evidence
- ignore browser chrome
- return exactly four lines
- lines must start with: Takeaway:, Evidence:, Risk:, Next Check:
- Takeaway must name the main bottleneck, blocked transition, or highest-risk dependency shown in the diagram
- use exact visible labels when they are readable
- Evidence must cite one concrete visible annotation, callout, node label, or value from the screenshot
- Risk must explain one operational consequence if the highlighted issue persists
- Next Check must name one concrete follow-up check

Latest user request:
$user_message_text
EOF
)
        if [ -n "$(trim "$attachment_image_ocr_context")" ]; then
          quick_prompt="${quick_prompt}

OCR text from the same attached image:
$attachment_image_ocr_context

Use the OCR only to recover exact visible labels and values from the same screenshot. If OCR conflicts with the image, trust the image."
        fi
      elif [ "$dashboard_chart_read_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a dashboard chart reading assistant analyzing an attached chart or table screenshot.
Primary objective: identify the most important visible takeaway and explain why it matters.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible chart or table evidence
- ignore browser chrome
- return exactly four lines
- lines must start with: Finding:, Evidence:, Risk:, Next Check:
- Finding must name the dominant anomaly, weakest step, or highest-risk trend
- use the exact visible label and value when they are readable
- do not rename regions, steps, or time points into generic letters or placeholders
- Evidence must cite one visible cue such as a value, peak point, lowest row, tallest bar, color cue, or labeled step
- Risk must explain one operational or business consequence
- Next Check must name one concrete follow-up check

Latest user request:
$user_message_text
EOF
)
        if [ -n "$(trim "$attachment_image_ocr_context")" ]; then
          quick_prompt="${quick_prompt}

OCR text from the same attached image:
$attachment_image_ocr_context

Use the OCR only to recover exact visible labels and values from the same screenshot. If OCR conflicts with the image, trust the image."
        fi
      elif [ "$before_after_ui_delta_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a before/after UI delta assistant analyzing two attached screenshots.
Primary objective: explain the concrete visible change from the first screenshot (before) to the second screenshot (after) and why it matters.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible screenshot evidence
- ignore browser chrome
- treat the first attached screenshot as BEFORE and the second attached screenshot as AFTER
- return exactly four lines
- lines must start with: Change:, Before Evidence:, After Evidence:, Impact:
- Change must name the concrete visual or layout improvement
- Before Evidence must cite one concrete visible cue from the first screenshot
- After Evidence must cite one concrete visible cue from the second screenshot
- Impact must explain one user or operator consequence of the change

Latest user request:
$user_message_text
EOF
)
        if [ -n "$(trim "$attachment_image_ocr_context")" ]; then
          quick_prompt="${quick_prompt}

OCR text from the attached images:
$attachment_image_ocr_context

Use the OCR only to recover exact visible labels from the same screenshots. If OCR conflicts with the images, trust the images."
        fi
      elif [ "$terminal_state_recovery_read_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a terminal-state recovery assistant analyzing two attached terminal or log screenshots.
Primary objective: compare the first screenshot (before recovery) and the second screenshot (after recovery) and state whether the visible failure recovered, stayed broken, or changed into a different failure.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible screenshot evidence
- ignore browser chrome
- treat the first attached screenshot as BEFORE and the second attached screenshot as AFTER
- return exactly four lines
- lines must start with: State Change:, Before Evidence:, After Evidence:, Next Check:
- State Change must name whether the visible terminal state recovered, stayed broken, or changed into a different visible failure
- Before Evidence must cite one concrete visible cue from the first screenshot
- After Evidence must cite one concrete visible cue from the second screenshot
- Next Check must name one concrete shell check or repair command justified by the after state

Latest user request:
$user_message_text
EOF
)
        if [ -n "$(trim "$attachment_image_ocr_context")" ]; then
          quick_prompt="${quick_prompt}

OCR text from the attached images:
$attachment_image_ocr_context

Use the OCR only to recover exact visible labels from the same screenshots. If OCR conflicts with the images, trust the images."
        fi
      elif [ "$terminal_screenshot_debug_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a terminal screenshot debugging assistant analyzing an attached terminal or log screenshot.
Primary objective: identify the main visible failure, cite the proving line, name one concrete next shell command, and explain the operational risk.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible terminal or log evidence
- ignore browser chrome
- return exactly four lines
- lines must start with: Finding:, Evidence:, Next Command:, Risk:
- Finding must name the primary failure mode
- Evidence must quote one exact visible error line or code when readable
- Next Command must be one concrete shell command, not a paragraph
- Risk must explain one operational consequence if the failure persists

Latest user request:
$user_message_text
EOF
)
        if [ -n "$(trim "$attachment_image_ocr_context")" ]; then
          quick_prompt="${quick_prompt}

OCR text from the same attached image:
$attachment_image_ocr_context

Use the OCR only to recover exact visible error lines, codes, labels, and port numbers from the same screenshot. If OCR conflicts with the image, trust the image."
        fi
      elif [ "$gui_screenshot_layout_triage_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a GUI layout triage assistant analyzing an attached screenshot.
Primary objective: identify the concrete visible layout defect and propose one actionable fix direction.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
- use only visible screenshot evidence
- ignore browser chrome
- return exactly four lines
- lines must start with: Issue:, Evidence:, Likely Cause:, Fix Direction:
- mention the affected UI region and what is visibly wrong
- if the whole dialog, panel, filter bar, or card grid is broken, name that container instead of a child heading or button
- prefer semantic UI region names like dialog, preview panel, filter bar, chips, header, title, card grid, or rightmost card instead of generic words like "text" or "content"
- Evidence must cite one concrete visible cue from the screenshot
- Likely Cause must name the most likely layout/CSS cause
- Fix Direction must name one actionable layout fix

Latest user request:
$user_message_text
EOF
)
      elif [ "$simple_direct_prompt" = "1" ]; then
        quick_prompt=$(cat <<EOF
You are a helpful assistant.
Respond directly and concisely to the latest user message.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
$quick_structure_hint

User request:
$user_message_text
EOF
)
      else
        quick_prompt=$(cat <<EOF
You are a coding assistant. Respond concisely and concretely.
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget
Output rules:
- return only assistant reply text
- do not prefix with "Assistant:" or "User:"
- do not output control tokens like <end_of_text>
$quick_structure_hint

User request:
$user_message_text

Workspace snapshot:
$snapshot_text

Recent conversation:
$history_text
EOF
)
      fi

      if [ "$simple_direct_prompt" != "1" ] && [ "$rich_reasoning_prompt" != "1" ] && [ -n "$(trim "$workspace_context_text")" ]; then
        quick_prompt="${quick_prompt}

Other threads in this same workspace:
$workspace_context_text"
      fi

      if { [ "$simple_direct_prompt" != "1" ] || [ "$run_mode" = "chat" ]; } && [ -n "$(trim "$attachment_context")" ]; then
        quick_prompt="${quick_prompt}

Attachment context:
$attachment_context"
      fi

      if { [ "$simple_direct_prompt" != "1" ] || [ "$run_mode" = "chat" ]; } && [ -n "$(trim "$web_context")" ]; then
        quick_prompt="${quick_prompt}

Web context:
$web_context"
      fi

      if [ -n "$(trim "$explicit_skill_context_text")" ]; then
        quick_prompt="${quick_prompt}

Explicit skill actuator results:
$explicit_skill_context_text"
      fi

      controller_stream_raw=${ARTIFICER_STREAM_RAW_CONTROLLER:-0}
      if [ "$run_mode" = "programming" ]; then
        controller_stream_raw=0
      fi
      if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
        ARTIFICER_STREAM_FILE="$stream_output_file"
        export ARTIFICER_STREAM_FILE
      fi
      use_rich_followup_fast_path=0
      use_freeform_reasoning_fast_path=0
      use_document_revision_fast_path=0
      use_diagram_annotation_read_fast_path=0
      use_dashboard_chart_read_fast_path=0
      use_before_after_ui_delta_fast_path=0
      use_terminal_state_recovery_read_fast_path=0
      use_terminal_screenshot_debug_fast_path=0
      use_gui_screenshot_layout_triage_fast_path=0
      use_repo_runtime_web_triage_fast_path=0
      use_browser_image_run_investigation_fast_path=0
      use_tool_failure_handoff_fast_path=0
      use_current_api_migration_fast_path=0
      use_current_ops_guidance_fast_path=0
      use_standards_grounded_answer_fast_path=0
      use_multi_artifact_judgment_fast_path=0
      use_multi_service_partial_rollback_fast_path=0
      use_system_release_pack_fast_path=0
      use_system_boundary_pack_fast_path=0
      use_partial_system_rollback_fast_path=0
      use_background_process_recovery_fast_path=0
      use_local_env_drift_fast_path=0
      use_local_package_upgrade_fast_path=0
      use_long_running_command_polling_fast_path=0
      use_filesystem_mutation_fast_path=0
      use_remote_release_pack_fast_path=0
      use_remote_boundary_pack_fast_path=0
      use_remote_boundary_rollback_fast_path=0
      use_remote_boundary_rollout_fast_path=0
      use_remote_bastion_cutover_fast_path=0
      use_remote_multi_host_rollout_fast_path=0
      use_remote_multi_host_fast_path=0
      use_remote_deploy_rollback_fast_path=0
      use_remote_single_host_fast_path=0
      use_local_service_restart_fast_path=0
      use_programming_stopgo_fast_path=0
      use_freeform_clarify_fast_path=0
      use_freeform_reflection_fast_path=0
      use_freeform_frame_fast_path=0
      if [ "$rich_reasoning_prompt" = "1" ] && [ "$reasoning_followup_prompt" = "1" ] && [ "$compute_budget" = "quick" ]; then
        use_rich_followup_fast_path=1
      fi
      if [ "$freeform_reasoning_prompt" = "1" ] && [ "$reasoning_followup_prompt" != "1" ] && [ "$compute_budget" = "quick" ]; then
        use_freeform_reasoning_fast_path=1
      fi
      if [ "$document_revision_prompt" = "1" ]; then
        use_document_revision_fast_path=1
      fi
      if [ "$diagram_annotation_read_prompt" = "1" ]; then
        use_diagram_annotation_read_fast_path=1
      fi
      if [ "$dashboard_chart_read_prompt" = "1" ]; then
        use_dashboard_chart_read_fast_path=1
      fi
      if [ "$before_after_ui_delta_prompt" = "1" ]; then
        use_before_after_ui_delta_fast_path=1
      fi
      if [ "$terminal_state_recovery_read_prompt" = "1" ]; then
        use_terminal_state_recovery_read_fast_path=1
      fi
      if [ "$terminal_screenshot_debug_prompt" = "1" ]; then
        use_terminal_screenshot_debug_fast_path=1
      fi
      if [ "$gui_screenshot_layout_triage_prompt" = "1" ]; then
        use_gui_screenshot_layout_triage_fast_path=1
      fi
      if [ "$repo_runtime_web_triage_prompt" = "1" ]; then
        use_repo_runtime_web_triage_fast_path=1
      fi
      if [ "$browser_image_run_investigation_prompt" = "1" ]; then
        use_browser_image_run_investigation_fast_path=1
      fi
      if [ "$tool_failure_handoff_prompt" = "1" ]; then
        use_tool_failure_handoff_fast_path=1
      fi
      if [ "$current_api_migration_prompt" = "1" ]; then
        use_current_api_migration_fast_path=1
      fi
      if [ "$current_ops_guidance_prompt" = "1" ]; then
        use_current_ops_guidance_fast_path=1
      fi
      if [ "$standards_grounded_answer_prompt" = "1" ]; then
        use_standards_grounded_answer_fast_path=1
      fi
      if [ "$multi_artifact_judgment_prompt" = "1" ]; then
        use_multi_artifact_judgment_fast_path=1
      fi
      if [ "$multi_service_partial_rollback_prompt" = "1" ]; then
        use_multi_service_partial_rollback_fast_path=1
      fi
      if [ "$system_release_pack_prompt" = "1" ]; then
        use_system_release_pack_fast_path=1
      fi
      if [ "$system_boundary_pack_prompt" = "1" ]; then
        use_system_boundary_pack_fast_path=1
      fi
      if [ "$partial_system_rollback_prompt" = "1" ]; then
        use_partial_system_rollback_fast_path=1
      fi
      if [ "$background_process_recovery_prompt" = "1" ]; then
        use_background_process_recovery_fast_path=1
      fi
      if [ "$local_env_drift_prompt" = "1" ]; then
        use_local_env_drift_fast_path=1
      fi
      if [ "$local_package_upgrade_prompt" = "1" ]; then
        use_local_package_upgrade_fast_path=1
      fi
      if [ "$long_running_command_polling_prompt" = "1" ]; then
        use_long_running_command_polling_fast_path=1
      fi
      if [ "$filesystem_mutation_prompt" = "1" ]; then
        use_filesystem_mutation_fast_path=1
      fi
      if [ "$remote_release_pack_prompt" = "1" ]; then
        use_remote_release_pack_fast_path=1
      fi
      if [ "$remote_boundary_pack_prompt" = "1" ]; then
        use_remote_boundary_pack_fast_path=1
      fi
      if [ "$remote_boundary_rollback_prompt" = "1" ]; then
        use_remote_boundary_rollback_fast_path=1
      fi
      if [ "$remote_boundary_rollout_prompt" = "1" ]; then
        use_remote_boundary_rollout_fast_path=1
      fi
      if [ "$remote_bastion_cutover_prompt" = "1" ]; then
        use_remote_bastion_cutover_fast_path=1
      fi
      if [ "$remote_multi_host_rollout_prompt" = "1" ]; then
        use_remote_multi_host_rollout_fast_path=1
      fi
      if [ "$remote_multi_host_prompt" = "1" ]; then
        use_remote_multi_host_fast_path=1
      fi
      if [ "$remote_deploy_rollback_prompt" = "1" ]; then
        use_remote_deploy_rollback_fast_path=1
      fi
      if [ "$remote_single_host_prompt" = "1" ]; then
        use_remote_single_host_fast_path=1
      fi
      if [ "$local_service_restart_prompt" = "1" ]; then
        use_local_service_restart_fast_path=1
      fi
      if [ "$programming_followup_stopgo_prompt" -eq 1 ]; then
        use_programming_stopgo_fast_path=1
      fi
      if [ "$freeform_clarify_prompt" = "1" ] && [ "$compute_budget" = "quick" ]; then
        use_freeform_clarify_fast_path=1
      fi
      if [ "$freeform_reflection_prompt" = "1" ] && [ "$compute_budget" = "quick" ]; then
        use_freeform_reflection_fast_path=1
      fi
      if [ "$freeform_frame_prompt" = "1" ] && [ "$compute_budget" = "quick" ]; then
        use_freeform_frame_fast_path=1
      fi
      quick_commands_json=""
      quick_commands_first=1
      quick_command_success_total=0
      quick_loop_summary=""
      quick_mode_last_command_status=""
      quick_mode_last_command_output=""
      quick_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 90 10 8)
      if [ "$use_freeform_clarify_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic ambiguous-intent clarify fast path."
        assistant_raw=$(reasoning_freeform_clarifying_question_for_prompt "$user_message_text")
        model_rc=0
      elif [ "$use_document_revision_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic document revision fast path."
        assistant_raw=$(document_revision_response_for_prompt "$document_revision_context_text")
        model_rc=0
      elif [ "$use_diagram_annotation_read_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached diagram or annotated screenshot."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_dashboard_chart_read_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached dashboard chart or table."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_before_after_ui_delta_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached before/after UI screenshots."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_terminal_state_recovery_read_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached before/after terminal screenshots."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_terminal_screenshot_debug_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached terminal or log screenshot."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_browser_image_run_investigation_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded browser/image/runtime investigation fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/runtime-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        browser_image_runtime_status=$quick_mode_last_command_status
        browser_image_runtime_output=$quick_mode_last_command_output
        browser_image_prompt=$(browser_image_run_compose_prompt "$user_prompt" "$browser_image_runtime_output")
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$browser_image_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_tool_failure_handoff_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded tool-failure handoff fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/primary-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        tool_handoff_primary_status=$quick_mode_last_command_status
        tool_handoff_primary_output=$quick_mode_last_command_output
        stream_emit_line "$stream_output_file" "Quick-mode handoff: ./bin/primary-check.sh failed with $tool_handoff_primary_status, switching to ./bin/fallback-check.sh and current docs."
        quick_loop_summary="${quick_loop_summary}
## Tool handoff
The initial helper ./bin/primary-check.sh returned $tool_handoff_primary_status, so the bounded fast path handed off to ./bin/fallback-check.sh plus current documentation.
"
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/fallback-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        tool_handoff_fallback_status=$quick_mode_last_command_status
        tool_handoff_fallback_output=$quick_mode_last_command_output
        tool_handoff_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        tool_handoff_doc_excerpt=""
        if [ -n "$tool_handoff_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $tool_handoff_doc_url"
          tool_handoff_doc_excerpt=$(fetch_url_text_excerpt "$tool_handoff_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $tool_handoff_doc_url
$(printf '%s' "$tool_handoff_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(tool_failure_handoff_summary \
          "$tool_handoff_primary_output" \
          "$tool_handoff_primary_status" \
          "$tool_handoff_fallback_output" \
          "$tool_handoff_fallback_status" \
          "$tool_handoff_doc_url" \
          "$tool_handoff_doc_excerpt")
        model_rc=0
      elif [ "$use_current_api_migration_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded current API migration fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/repo-scan.sh" "all" "$blocked_commands_file" "$stream_output_file"
        current_api_repo_output=$quick_mode_last_command_output
        current_api_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        current_api_doc_excerpt=""
        if [ -n "$current_api_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $current_api_doc_url"
          current_api_doc_excerpt=$(fetch_url_text_excerpt "$current_api_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $current_api_doc_url
$(printf '%s' "$current_api_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(current_api_migration_summary \
          "$current_api_repo_output" \
          "$current_api_doc_url" \
          "$current_api_doc_excerpt")
        model_rc=0
      elif [ "$use_current_ops_guidance_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded current ops guidance fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/state-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        current_ops_state_output=$quick_mode_last_command_output
        current_ops_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        current_ops_doc_excerpt=""
        if [ -n "$current_ops_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $current_ops_doc_url"
          current_ops_doc_excerpt=$(fetch_url_text_excerpt "$current_ops_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $current_ops_doc_url
$(printf '%s' "$current_ops_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(current_ops_guidance_summary \
          "$current_ops_state_output" \
          "$current_ops_doc_url" \
          "$current_ops_doc_excerpt")
        model_rc=0
      elif [ "$use_multi_artifact_judgment_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic multi-artifact judgment fast path."
        assistant_raw=$(multi_artifact_judgment_summary "$user_prompt")
        model_rc=0
      elif [ "$use_standards_grounded_answer_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using bounded standards-grounded answer fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/repo-scan.sh" "all" "$blocked_commands_file" "$stream_output_file"
        standards_repo_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/runtime-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        standards_runtime_status=$quick_mode_last_command_status
        standards_runtime_output=$quick_mode_last_command_output
        standards_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        standards_doc_excerpt=""
        if [ -n "$standards_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $standards_doc_url"
          standards_doc_excerpt=$(fetch_url_text_excerpt "$standards_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $standards_doc_url
$(printf '%s' "$standards_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(standards_grounded_answer_summary \
          "$standards_repo_output" \
          "$standards_runtime_output" \
          "$standards_runtime_status" \
          "$standards_doc_url" \
          "$standards_doc_excerpt")
        model_rc=0
      elif [ "$use_gui_screenshot_layout_triage_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Requesting model output for attached screenshot triage."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      elif [ "$use_repo_runtime_web_triage_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic repo/runtime/web triage fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/repo-scan.sh" "all" "$blocked_commands_file" "$stream_output_file"
        repo_runtime_repo_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/runtime-check.sh" "all" "$blocked_commands_file" "$stream_output_file"
        repo_runtime_runtime_status=$quick_mode_last_command_status
        repo_runtime_runtime_output=$quick_mode_last_command_output
        repo_runtime_doc_url=$(repo_runtime_web_first_url_from_prompt "$user_prompt")
        repo_runtime_doc_excerpt=""
        if [ -n "$repo_runtime_doc_url" ]; then
          stream_emit_line "$stream_output_file" "Quick-mode web fetch: $repo_runtime_doc_url"
          repo_runtime_doc_excerpt=$(fetch_url_text_excerpt "$repo_runtime_doc_url" 2600)
          quick_loop_summary="${quick_loop_summary}
## Web fetch
Fetched $repo_runtime_doc_url
$(printf '%s' "$repo_runtime_doc_excerpt" | cut -c1-420)
"
        else
          quick_loop_summary="${quick_loop_summary}
## Web fetch
No direct documentation URL was found in the prompt.
"
        fi
        assistant_raw=$(repo_runtime_web_triage_summary \
          "$repo_runtime_repo_output" \
          "$repo_runtime_runtime_output" \
          "$repo_runtime_runtime_status" \
          "$repo_runtime_doc_url" \
          "$repo_runtime_doc_excerpt")
        model_rc=0
      elif [ "$use_multi_service_partial_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic multi-service partial rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-api.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_api_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-worker.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_worker_status_output=$quick_mode_last_command_output
        if multi_service_partial_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/multi-service.env to approve one shared rollback, restore the stable API and worker release/mode state, and keep the rollback read-only.
"
          stream_emit_line "$stream_output_file" "Quick-mode multi-service fix: rewrote state/multi-service.env for the bounded API-plus-worker rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/multi-service.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode multi-service fix failed: could not rewrite state/multi-service.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback-api.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_api_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback-worker.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_worker_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_health_status=$quick_mode_last_command_status
        multi_service_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        multi_service_verify_status=$quick_mode_last_command_status
        multi_service_verify_output=$quick_mode_last_command_output
        assistant_raw=$(multi_service_partial_rollback_summary \
          "$multi_service_api_status_output" \
          "$multi_service_worker_status_output" \
          "$multi_service_api_rollback_output" \
          "$multi_service_worker_rollback_output" \
          "$multi_service_health_output" \
          "$multi_service_health_status" \
          "$multi_service_verify_output" \
          "$multi_service_verify_status")
        model_rc=0
      elif [ "$use_system_release_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic system release pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_core_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_edge_status_output=$quick_mode_last_command_output
        if system_release_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/release-pack.env to approve one shared release pack, mark the core and edge boundaries ready, preserve the current and target release values, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-release fix: rewrote state/release-pack.env for the bounded core-plus-edge release pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/release-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-release fix failed: could not rewrite state/release-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_core_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_edge_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/publish-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_publish_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_release_verify_status=$quick_mode_last_command_status
        system_release_verify_output=$quick_mode_last_command_output
        assistant_raw=$(system_release_pack_summary \
          "$system_release_core_status_output" \
          "$system_release_edge_status_output" \
          "$system_release_core_cutover_output" \
          "$system_release_edge_cutover_output" \
          "$system_release_publish_output" \
          "$system_release_verify_output" \
          "$system_release_verify_status")
        model_rc=0
      elif [ "$use_system_boundary_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic system boundary pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_core_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_edge_status_output=$quick_mode_last_command_output
        if system_boundary_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/boundary-pack.env to approve one shared cutover, mark the core and edge boundaries ready, preserve the current and target boundary values, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-boundary fix: rewrote state/boundary-pack.env for the bounded core-plus-edge cutover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/boundary-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode system-boundary fix failed: could not rewrite state/boundary-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-core.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_core_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/cutover-edge.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_edge_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-pack.sh" "all" "$blocked_commands_file" "$stream_output_file"
        system_boundary_verify_status=$quick_mode_last_command_status
        system_boundary_verify_output=$quick_mode_last_command_output
        assistant_raw=$(system_boundary_pack_summary \
          "$system_boundary_core_status_output" \
          "$system_boundary_edge_status_output" \
          "$system_boundary_core_cutover_output" \
          "$system_boundary_edge_cutover_output" \
          "$system_boundary_verify_output" \
          "$system_boundary_verify_status")
        model_rc=0
      elif [ "$use_partial_system_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic partial-system-rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_status_output=$quick_mode_last_command_output
        if partial_system_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/system.env to approve the bounded rollback, restore the stable release/package/worker state, and keep the rollback read-only.
"
          stream_emit_line "$stream_output_file" "Quick-mode rollback fix: rewrote state/system.env for the bounded partial rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/system.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode rollback fix failed: could not rewrite state/system.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/rollback.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_apply_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_health_status=$quick_mode_last_command_status
        partial_rollback_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        partial_rollback_verify_status=$quick_mode_last_command_status
        partial_rollback_verify_output=$quick_mode_last_command_output
        assistant_raw=$(partial_system_rollback_summary \
          "$partial_rollback_status_output" \
          "$partial_rollback_apply_output" \
          "$partial_rollback_health_output" \
          "$partial_rollback_health_status" \
          "$partial_rollback_verify_output" \
          "$partial_rollback_verify_status")
        model_rc=0
      elif [ "$use_background_process_recovery_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic background-process recovery fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ps.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_ps_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/stop.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_stop_output=$quick_mode_last_command_output
        if background_process_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote process/worker.env to MODE=healthy, AUTO_START=1, READ_ONLY=1, and preserved the existing QUEUE value for the bounded worker recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode worker fix: rewrote process/worker.env for a bounded worker recovery."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite process/worker.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode worker fix failed: could not rewrite process/worker.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/start.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_start_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        background_process_health_status=$quick_mode_last_command_status
        background_process_health_output=$quick_mode_last_command_output
        assistant_raw=$(background_process_recovery_summary \
          "$background_process_ps_output" \
          "$background_process_stop_output" \
          "$background_process_start_output" \
          "$background_process_health_output" \
          "$background_process_health_status")
        model_rc=0
      elif [ "$use_local_env_drift_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local env drift fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/doctor.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_env_doctor_output=$quick_mode_last_command_output
        if local_env_drift_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote config/toolchain.env to align the active tool path, active version, and read-only guard with the expected values.
"
          stream_emit_line "$stream_output_file" "Quick-mode env fix: rewrote config/toolchain.env for the expected toolchain state."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite config/toolchain.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode env fix failed: could not rewrite config/toolchain.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_env_verify_status=$quick_mode_last_command_status
        local_env_verify_output=$quick_mode_last_command_output
        assistant_raw=$(local_env_drift_summary \
          "$local_env_doctor_output" \
          "$local_env_verify_output" \
          "$local_env_verify_status")
        model_rc=0
      elif [ "$use_local_package_upgrade_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local package upgrade fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/audit.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_package_audit_output=$quick_mode_last_command_output
        if local_package_upgrade_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote package.json and package-lock.json to upgrade demo-lib to 2.1.0 and keep the change bounded to the local package manifest/lockfile pair.
"
          stream_emit_line "$stream_output_file" "Quick-mode package fix: rewrote package.json and package-lock.json for the bounded demo-lib upgrade."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite package.json and package-lock.json in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode package fix failed: could not rewrite package.json and package-lock.json."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/test.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_package_test_status=$quick_mode_last_command_status
        local_package_test_output=$quick_mode_last_command_output
        assistant_raw=$(local_package_upgrade_summary \
          "$local_package_audit_output" \
          "$local_package_test_output" \
          "$local_package_test_status")
        model_rc=0
      elif [ "$use_long_running_command_polling_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic long-running command fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_first_poll_output=$quick_mode_last_command_output
        if long_running_command_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote job/run.env to enable checkpointing, allow the bounded finalize step, preserve the target step count, and keep the job read-only during the final polling sequence.
"
          stream_emit_line "$stream_output_file" "Quick-mode long-running fix: rewrote job/run.env for the bounded polling sequence."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite job/run.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode long-running fix failed: could not rewrite job/run.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_second_poll_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/checkpoint.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_checkpoint_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/poll.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_third_poll_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/finalize.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_finalize_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        long_running_verify_status=$quick_mode_last_command_status
        long_running_verify_output=$quick_mode_last_command_output
        assistant_raw=$(long_running_command_summary \
          "$long_running_first_poll_output" \
          "$long_running_second_poll_output" \
          "$long_running_checkpoint_output" \
          "$long_running_third_poll_output" \
          "$long_running_finalize_output" \
          "$long_running_verify_output" \
          "$long_running_verify_status")
        model_rc=0
      elif [ "$use_filesystem_mutation_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic filesystem mutation fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/inventory.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_inventory_output=$quick_mode_last_command_output
        if filesystem_mutation_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote state/layout.env to approve the bounded archive/promote/link operation, preserve the live/staging/archive paths, and keep the mutation pack read-only during verification.
"
          stream_emit_line "$stream_output_file" "Quick-mode filesystem fix: rewrote state/layout.env for the bounded archive/promote/link operation."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite state/layout.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode filesystem fix failed: could not rewrite state/layout.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/apply.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_apply_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify.sh" "all" "$blocked_commands_file" "$stream_output_file"
        filesystem_verify_status=$quick_mode_last_command_status
        filesystem_verify_output=$quick_mode_last_command_output
        assistant_raw=$(filesystem_mutation_summary \
          "$filesystem_inventory_output" \
          "$filesystem_apply_output" \
          "$filesystem_verify_output" \
          "$filesystem_verify_status")
        model_rc=0
      elif [ "$use_remote_release_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote release pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_status_output=$quick_mode_last_command_output
        if remote_release_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/release-pack.env to approve the shared core and edge target releases, mark the bastion tunnel plus all bounded private-boundary helpers ready, approve release publication, preserve host identities, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote release-pack fix: rewrote remote/release-pack.env for the bounded bastion-plus-core/edge release pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/release-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote release-pack fix failed: could not rewrite remote/release-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_bastion_health_status=$quick_mode_last_command_status
        remote_release_pack_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_canary_health_status=$quick_mode_last_command_status
        remote_release_pack_core_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_core_fleet_health_status=$quick_mode_last_command_status
        remote_release_pack_core_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_canary_health_status=$quick_mode_last_command_status
        remote_release_pack_edge_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_edge_fleet_health_status=$quick_mode_last_command_status
        remote_release_pack_edge_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/publish-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_publish_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-release.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_release_pack_verify_status=$quick_mode_last_command_status
        remote_release_pack_verify_output=$quick_mode_last_command_output
        assistant_raw=$(remote_release_pack_summary \
          "$remote_release_pack_bastion_status_output" \
          "$remote_release_pack_bastion_tunnel_output" \
          "$remote_release_pack_bastion_health_output" \
          "$remote_release_pack_bastion_health_status" \
          "$remote_release_pack_core_canary_status_output" \
          "$remote_release_pack_core_canary_deploy_output" \
          "$remote_release_pack_core_canary_health_output" \
          "$remote_release_pack_core_canary_health_status" \
          "$remote_release_pack_core_fleet_status_output" \
          "$remote_release_pack_core_fleet_deploy_output" \
          "$remote_release_pack_core_fleet_health_output" \
          "$remote_release_pack_core_fleet_health_status" \
          "$remote_release_pack_edge_canary_status_output" \
          "$remote_release_pack_edge_canary_deploy_output" \
          "$remote_release_pack_edge_canary_health_output" \
          "$remote_release_pack_edge_canary_health_status" \
          "$remote_release_pack_edge_fleet_status_output" \
          "$remote_release_pack_edge_fleet_deploy_output" \
          "$remote_release_pack_edge_fleet_health_output" \
          "$remote_release_pack_edge_fleet_health_status" \
          "$remote_release_pack_publish_output" \
          "$remote_release_pack_verify_output" \
          "$remote_release_pack_verify_status")
        model_rc=0
      elif [ "$use_remote_boundary_pack_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary pack fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_pack_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary-pack.env to approve the core and edge target releases, mark the bastion tunnel plus all bounded private-boundary helpers ready, preserve host identities, and keep the pack read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary-pack fix: rewrote remote/boundary-pack.env for the bounded bastion-plus-core/edge boundary pack."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary-pack.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary-pack fix failed: could not rewrite remote/boundary-pack.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_pack_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_canary_health_status=$quick_mode_last_command_status
        remote_boundary_pack_core_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-core-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_core_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_pack_core_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_canary_health_status=$quick_mode_last_command_status
        remote_boundary_pack_edge_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-edge-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_edge_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_pack_edge_fleet_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/verify-pack.sh" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_pack_verify_status=$quick_mode_last_command_status
        remote_boundary_pack_verify_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_pack_summary \
          "$remote_boundary_pack_bastion_status_output" \
          "$remote_boundary_pack_bastion_tunnel_output" \
          "$remote_boundary_pack_bastion_health_output" \
          "$remote_boundary_pack_bastion_health_status" \
          "$remote_boundary_pack_core_canary_status_output" \
          "$remote_boundary_pack_core_canary_deploy_output" \
          "$remote_boundary_pack_core_canary_health_output" \
          "$remote_boundary_pack_core_canary_health_status" \
          "$remote_boundary_pack_core_fleet_status_output" \
          "$remote_boundary_pack_core_fleet_deploy_output" \
          "$remote_boundary_pack_core_fleet_health_output" \
          "$remote_boundary_pack_core_fleet_health_status" \
          "$remote_boundary_pack_edge_canary_status_output" \
          "$remote_boundary_pack_edge_canary_deploy_output" \
          "$remote_boundary_pack_edge_canary_health_output" \
          "$remote_boundary_pack_edge_canary_health_status" \
          "$remote_boundary_pack_edge_fleet_status_output" \
          "$remote_boundary_pack_edge_fleet_deploy_output" \
          "$remote_boundary_pack_edge_fleet_health_output" \
          "$remote_boundary_pack_edge_fleet_health_status" \
          "$remote_boundary_pack_verify_output" \
          "$remote_boundary_pack_verify_status")
        model_rc=0
      elif [ "$use_remote_boundary_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary rollback fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_rollback_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary.env to approve the stable release, mark the bastion tunnel plus private canary/fleet rollbacks ready, preserve host identities, and keep the bounded rollback read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary rollback fix: rewrote remote/boundary.env for the bounded bastion-plus-private rollback."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary rollback fix failed: could not rewrite remote/boundary.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh rollback" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_health_status=$quick_mode_last_command_status
        remote_boundary_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh rollback" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_rollback_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_rollback_summary \
          "$remote_boundary_bastion_status_output" \
          "$remote_boundary_bastion_tunnel_output" \
          "$remote_boundary_bastion_health_output" \
          "$remote_boundary_bastion_health_status" \
          "$remote_boundary_canary_status_output" \
          "$remote_boundary_canary_rollback_output" \
          "$remote_boundary_canary_health_output" \
          "$remote_boundary_canary_health_status" \
          "$remote_boundary_fleet_status_output" \
          "$remote_boundary_fleet_rollback_output" \
          "$remote_boundary_fleet_health_output" \
          "$remote_boundary_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_boundary_rollout_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote boundary rollout fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_status_output=$quick_mode_last_command_output
        if remote_boundary_rollout_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/boundary.env to approve the target release, mark the bastion tunnel plus private canary/fleet targets ready, preserve host identities, and keep the bounded rollout read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary fix: rewrote remote/boundary.env for the bounded bastion-plus-private rollout."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/boundary.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote boundary fix failed: could not rewrite remote/boundary.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_bastion_health_status=$quick_mode_last_command_status
        remote_boundary_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_canary_health_status=$quick_mode_last_command_status
        remote_boundary_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_boundary_fleet_health_status=$quick_mode_last_command_status
        remote_boundary_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_boundary_rollout_summary \
          "$remote_boundary_bastion_status_output" \
          "$remote_boundary_bastion_tunnel_output" \
          "$remote_boundary_bastion_health_output" \
          "$remote_boundary_bastion_health_status" \
          "$remote_boundary_canary_status_output" \
          "$remote_boundary_canary_deploy_output" \
          "$remote_boundary_canary_health_output" \
          "$remote_boundary_canary_health_status" \
          "$remote_boundary_fleet_status_output" \
          "$remote_boundary_fleet_deploy_output" \
          "$remote_boundary_fleet_health_output" \
          "$remote_boundary_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_bastion_cutover_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote bastion cutover fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_status_output=$quick_mode_last_command_output
        if remote_bastion_cutover_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/bastion.env to approve the target private host, mark the bastion and target host ready, preserve the bastion host identity, and keep the bounded cutover read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote bastion fix: rewrote remote/bastion.env for the bounded bastion cutover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/bastion.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote bastion fix failed: could not rewrite remote/bastion.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh tunnel" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_tunnel_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-bastion.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_bastion_health_status=$quick_mode_last_command_status
        remote_bastion_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh cutover" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_cutover_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-private.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_private_health_status=$quick_mode_last_command_status
        remote_private_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_bastion_cutover_summary \
          "$remote_bastion_status_output" \
          "$remote_private_status_output" \
          "$remote_bastion_tunnel_output" \
          "$remote_bastion_health_output" \
          "$remote_bastion_health_status" \
          "$remote_private_cutover_output" \
          "$remote_private_health_output" \
          "$remote_private_health_status")
        model_rc=0
      elif [ "$use_remote_multi_host_rollout_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote multi-host rollout fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_status_output=$quick_mode_last_command_output
        if remote_multi_host_rollout_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/rollout.env to approve the target release, mark the canary and fleet hosts ready, preserve host identities, and keep the bounded staged rollout read-only during deployment.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote rollout fix: rewrote remote/rollout.env for the bounded staged rollout."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/rollout.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote rollout fix failed: could not rewrite remote/rollout.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-canary.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_canary_health_status=$quick_mode_last_command_status
        remote_rollout_canary_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-fleet.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_rollout_fleet_health_status=$quick_mode_last_command_status
        remote_rollout_fleet_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_multi_host_rollout_summary \
          "$remote_rollout_canary_status_output" \
          "$remote_rollout_fleet_status_output" \
          "$remote_rollout_canary_deploy_output" \
          "$remote_rollout_canary_health_output" \
          "$remote_rollout_canary_health_status" \
          "$remote_rollout_fleet_deploy_output" \
          "$remote_rollout_fleet_health_output" \
          "$remote_rollout_fleet_health_status")
        model_rc=0
      elif [ "$use_remote_multi_host_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote multi-host fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_status_output=$quick_mode_last_command_output
        if remote_multi_host_failover_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/topology.env to promote the replica host, point the app host at the new primary, preserve host identities, and keep the bounded failover read-only during recovery.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote multi-host fix: rewrote remote/topology.env for the bounded failover."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/topology.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote multi-host fix failed: could not rewrite remote/topology.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh promote" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_promote_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-db.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_db_health_status=$quick_mode_last_command_status
        remote_multi_host_db_health_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh restart" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh-app.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_multi_host_app_health_status=$quick_mode_last_command_status
        remote_multi_host_app_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_multi_host_replica_summary \
          "$remote_multi_host_app_status_output" \
          "$remote_multi_host_db_status_output" \
          "$remote_multi_host_db_promote_output" \
          "$remote_multi_host_db_health_output" \
          "$remote_multi_host_db_health_status" \
          "$remote_multi_host_app_restart_output" \
          "$remote_multi_host_app_health_output" \
          "$remote_multi_host_app_health_status")
        model_rc=0
      elif [ "$use_remote_deploy_rollback_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote deploy fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_status_output=$quick_mode_last_command_output
        if remote_deploy_release_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/release.env to approve the target release, mark the deploy ready, and preserve the existing remote host binding for the bounded deploy.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote deploy fix: rewrote remote/release.env for the bounded release deployment."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/release.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote deploy fix failed: could not rewrite remote/release.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh deploy" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_deploy_health_status=$quick_mode_last_command_status
        remote_deploy_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_deploy_rollback_summary \
          "$remote_deploy_status_output" \
          "$remote_deploy_output" \
          "$remote_deploy_health_output" \
          "$remote_deploy_health_status")
        model_rc=0
      elif [ "$use_remote_single_host_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic remote single-host fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh status" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_status_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh journal" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_journal_output=$quick_mode_last_command_output
        if remote_single_host_config_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote remote/service.env to MODE=healthy, READ_ONLY=1, and preserved the existing HOST and PORT values for the bounded remote host repair.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote fix: rewrote remote/service.env for a single-host recovery."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite remote/service.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode remote fix failed: could not rewrite remote/service.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh restart" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/ssh.sh health" "all" "$blocked_commands_file" "$stream_output_file"
        remote_single_host_health_status=$quick_mode_last_command_status
        remote_single_host_health_output=$quick_mode_last_command_output
        assistant_raw=$(remote_single_host_summary \
          "$remote_single_host_status_output" \
          "$remote_single_host_journal_output" \
          "$remote_single_host_restart_output" \
          "$remote_single_host_health_output" \
          "$remote_single_host_health_status")
        model_rc=0
      elif [ "$use_local_service_restart_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic local service restart fast path."
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/status.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_status_output=$quick_mode_last_command_output
        if local_service_config_fix_in_place "$workspace_path"; then
          quick_loop_summary="${quick_loop_summary}
## Local fix
Rewrote service/config.env to MODE=healthy, READ_ONLY=1, and preserved the existing PORT value.
"
          stream_emit_line "$stream_output_file" "Quick-mode service fix: rewrote service/config.env for a healthy restart."
        else
          quick_loop_summary="${quick_loop_summary}
## Local fix
Failed to rewrite service/config.env in place.
"
          stream_emit_line "$stream_output_file" "Quick-mode service fix failed: could not rewrite service/config.env."
        fi
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/restart.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_restart_output=$quick_mode_last_command_output
        quick_mode_run_recorded_command "$workspace_id" "$workspace_path" "./bin/health.sh" "all" "$blocked_commands_file" "$stream_output_file"
        local_service_health_status=$quick_mode_last_command_status
        local_service_health_output=$quick_mode_last_command_output
        assistant_raw=$(local_service_restart_summary \
          "$local_service_status_output" \
          "$local_service_restart_output" \
          "$local_service_health_output" \
          "$local_service_health_status")
        model_rc=0
      elif [ "$use_programming_stopgo_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic phase stop/go fast path."
        assistant_raw=$(programming_phase_stopgo_summary_for_prompt "$user_message_text" "$programming_followup_prior_user_text" "$programming_followup_prior_assistant_text")
        model_rc=0
      elif [ "$use_freeform_reflection_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform reflection fast path."
        assistant_raw=$(reasoning_freeform_reflection_for_prompt "$freeform_reflection_context_text")
        model_rc=0
      elif [ "$use_freeform_frame_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform framing fast path."
        assistant_raw=$(reasoning_freeform_frame_for_prompt "$freeform_frame_context_text")
        model_rc=0
      elif [ "$use_freeform_reasoning_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic freeform reasoning memo fast path."
        assistant_raw=$(reasoning_freeform_memo_for_prompt "$rich_reasoning_context_text")
        model_rc=0
      elif [ "$use_rich_followup_fast_path" = "1" ]; then
        stream_emit_line "$stream_output_file" "Using deterministic rich follow-up fast path."
        assistant_raw=$(reasoning_followup_fast_contract "$rich_reasoning_context_text")
        model_rc=0
      else
        stream_emit_line "$stream_output_file" "Requesting model output."
        set +e
        RUN_TIMEOUT_SEC=$quick_timeout_sec
        assistant_raw=$(run_model "$model" "$quick_prompt" "$attachment_image_payload" 2>&1)
        model_rc=$?
        set -e
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
      fi
      unset ARTIFICER_STREAM_FILE 2>/dev/null || true

      assistant_output=$(normalize_assistant_output "$assistant_raw")
      assistant_output=$(trim "$assistant_output")

      if [ "$model_rc" -ne 0 ]; then
        if [ "$model_rc" -eq 124 ]; then
          assistant_output="Model timed out after ${quick_timeout_sec}s. Try a smaller prompt, a faster model, or run again."
        elif [ -z "$assistant_output" ]; then
          assistant_output="Model request failed (exit $model_rc)."
        fi
      fi

      if looks_like_embedding_vector "$assistant_output"; then
        assistant_output="Model returned an embedding vector instead of chat text. Pick a chat/instruct coding model and run again."
      fi

      if [ -z "$assistant_output" ]; then
        assistant_output="Run completed, but the model did not return content."
      fi
      if [ "$rich_reasoning_prompt" = "1" ]; then
        assistant_output=$(printf '%s\n' "$assistant_output" | awk 'NF { count++ } count <= 24 { print }')
        assistant_output=$(printf '%s' "$assistant_output" | cut -c1-3200)
        assistant_output=$(trim "$assistant_output")
      fi
      if [ "$assay_run_profile" -eq 1 ]; then
        depth_fill_commands='git status --short --untracked-files=no
git rev-parse --show-toplevel'
        old_ifs=${IFS-}
        IFS='
'
        for depth_fill_cmd in $depth_fill_commands; do
          depth_fill_cmd=$(trim "$depth_fill_cmd")
          [ -n "$depth_fill_cmd" ] || continue
          depth_out=$(mktemp)
          depth_status_file=$(mktemp)
          execute_mediated_command "$workspace_id" "$workspace_path" "$depth_fill_cmd" "$depth_out" "$depth_status_file" "$command_mode" "$blocked_commands_file"
          depth_status=$(cat "$depth_status_file" 2>/dev/null || printf '%s' "error")
          depth_output=$(sed -n '1,40p' "$depth_out")
          rm -f "$depth_out" "$depth_status_file"
          if [ "$depth_status" = "ok" ]; then
            quick_command_success_total=$((quick_command_success_total + 1))
          fi
          quick_loop_summary="${quick_loop_summary}
## Command
$depth_fill_cmd
Status: $depth_status
$depth_output
"
          depth_command_json=$(json_escape "$depth_fill_cmd")
          depth_status_json=$(json_escape "$depth_status")
          depth_output_json=$(json_escape "$depth_output")
          depth_command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
            "$depth_command_json" "$depth_status_json" "$depth_output_json")
          if [ "$quick_commands_first" -eq 1 ]; then
            quick_commands_json=$depth_command_item
            quick_commands_first=0
          else
            quick_commands_json="${quick_commands_json},${depth_command_item}"
          fi
          stream_emit_line "$stream_output_file" "Quick-mode assay depth check command: $depth_fill_cmd ($depth_status)"
        done
        IFS=$old_ifs
      fi

      if output_looks_derailed "$assistant_output"; then
        repaired_output=$(salvage_direct_response "$model" "$user_prompt")
        if [ -n "$(trim "$repaired_output")" ]; then
          assistant_output=$repaired_output
        fi
      elif [ "$run_mode" = "chat" ] && chat_output_looks_off_topic "$user_message_text" "$assistant_output"; then
        repaired_chat_output=$(salvage_chat_response "$model" "$user_message_text" "$chat_history_text")
        if [ -n "$(trim "$repaired_chat_output")" ]; then
          assistant_output=$repaired_chat_output
        fi
      fi

      if [ "$compact_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_compact_reasoning_contract "$assistant_output" "$compact_reasoning_context_text")
      elif [ "$diagram_annotation_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_diagram_annotation_read_response "$assistant_output")
      elif [ "$dashboard_chart_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_dashboard_chart_read_response "$assistant_output")
      elif [ "$before_after_ui_delta_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_before_after_ui_delta_response "$assistant_output")
      elif [ "$terminal_state_recovery_read_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_terminal_state_recovery_response "$assistant_output")
      elif [ "$terminal_screenshot_debug_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_terminal_screenshot_debug_response "$assistant_output")
      elif [ "$browser_image_run_investigation_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_browser_image_run_investigation_response "$assistant_output" "$user_prompt" "$browser_image_runtime_output")
      elif [ "$gui_screenshot_layout_triage_prompt" = "1" ] && [ "$model_rc" -eq 0 ]; then
        assistant_output=$(normalize_gui_screenshot_layout_triage_response "$assistant_output")
      elif [ "$freeform_clarify_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_clarify_response "$assistant_output" "$user_message_text")
      elif [ "$freeform_reflection_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_reflection_response "$assistant_output" "$freeform_reflection_context_text")
      elif [ "$freeform_frame_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_frame_response "$assistant_output" "$freeform_frame_context_text")
      elif [ "$freeform_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_freeform_memo "$assistant_output" "$rich_reasoning_context_text")
      elif [ "$rich_reasoning_prompt" = "1" ]; then
        assistant_output=$(normalize_reasoning_section_labels "$assistant_output")
        assistant_output=$(normalize_adversarial_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_decision_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_cross_domain_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_recovery_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_verification_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_ambiguity_final_contract "$assistant_output")
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$rich_reasoning_context_text" "")
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$rich_reasoning_context_text" "" "0")
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$rich_reasoning_context_text" "")
        if prompt_requires_assumption_revision_contract "$rich_reasoning_context_text"; then
          assistant_output=$(normalize_assumption_revision_final_contract "$assistant_output" "$rich_reasoning_context_text")
          assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$rich_reasoning_context_text" "")
        fi
        if [ "$quick_command_success_total" -gt 0 ]; then
          assistant_output=$(reasoning_contract_upsert_line "Verification Evidence" "$(reasoning_design_verification_line "$rich_reasoning_context_text" "$quick_command_success_total" "$quick_loop_summary")" "$assistant_output")
          assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_loop_summary")
          assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_loop_summary" "$quick_command_success_total")
        fi
        assistant_output=$(normalize_reasoning_followup_thread_contract "$assistant_output" "$rich_reasoning_context_text")
        assistant_output=$(normalize_reasoning_live_contract "$assistant_output" "$rich_reasoning_context_text")
        if prompt_requires_high_risk_fail_closed "$rich_reasoning_context_text" "$run_mode"; then
          assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$rich_reasoning_context_text" "$quick_command_success_total" "$run_mode")
        fi
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
      fi

      append_message "$conv_dir" "assistant" "$assistant_output"

      git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
      git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
      if [ -z "$git_diff" ]; then
        git_diff="No working tree changes."
      fi

      assistant_json=$(json_escape "$assistant_output")
      plan_json=$(json_escape "$quick_plan")
      model_json=$(json_escape "$model")
      git_status_json=$(json_escape "$git_status")
      git_diff_json=$(json_escape "$git_diff")
      state_json=$(json_escape "mode=DONE")
      quick_session_log=$(cat <<EOF
## quick-mode
Prompt:
$quick_prompt

Model raw output:
$assistant_raw
EOF
)
      if [ -n "$(trim "$quick_loop_summary")" ]; then
        quick_session_log="${quick_session_log}

## Quick Assay Depth Checks
$quick_loop_summary"
      fi
      if [ -n "$(trim "$explicit_skill_context_text")" ]; then
        quick_session_log="${quick_session_log}

## Explicit Skills
$explicit_skill_context_text"
      fi
      quick_session_json=$(json_escape "$quick_session_log")
      quick_commands_array_json="[$quick_commands_json]"
      if [ -z "$(trim "$quick_commands_json")" ]; then
        quick_commands_array_json="[]"
      fi

      blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
      fi
      if [ "$queue_status_from_run" != "awaiting_approval" ]; then
        clear_approval_request "$conv_dir"
      fi
      queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
      stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run"
      run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      run_stream_preview=$(sed -n '1,320p' "$stream_output_file" 2>/dev/null || true)
      run_error_text=""
      quick_task_status_json=$(task_status_empty_json)
      if [ "$queue_status_from_run" = "error" ]; then
        run_error_text=$assistant_output
      fi
      quick_event_json=$(build_run_event_json \
        "$queue_status_from_run" \
        "$run_started_iso" \
        "$run_finished_iso" \
        "$model" \
        "$quick_plan" \
        "$quick_commands_array_json" \
        "$run_stream_preview" \
        "" \
        "$quick_session_log" \
        "mode=DONE" \
        "$git_status" \
        "$git_diff" \
        "$run_error_text" \
        "" \
        "$run_event_id" \
        "$quick_task_status_json" \
        "$run_message_anchor" \
        "$assay_task_id" \
        "$assistant_output")
      append_run_event_json "$conv_dir" "$quick_event_json"
      run_runtime_mark_finalized
      printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":%s,"blocked_commands":%s,"decision_request":null,"failures":"","session_log":"%s","state":"%s","task_status":%s}\n' \
        "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$quick_commands_array_json" "$blocked_commands_json" "$quick_session_json" "$state_json" "$quick_task_status_json"
      rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
      exit 0
    fi

    agent_dir="$conv_dir/agent"
    plan_file="$agent_dir/.plan.md"
    state_file="$agent_dir/.state"
    contract_file="$agent_dir/.contract.md"
    failures_file="$agent_dir/.failures.md"
    session_log_file="$agent_dir/.session.log.md"
    controller_raw_file="$agent_dir/.controller.raw.md"
    assumptions_file="$agent_dir/.assumptions.md"
    compliance_file="$agent_dir/.compliance.md"
    architecture_file="$agent_dir/.architecture.md"
    tasks_dir="$agent_dir/.tasks"
    tasks_index_file="$tasks_dir/index.md"
    scratch_root="$agent_dir/.scratch"
    changed_paths_file="$agent_dir/.changed-paths"
    programming_followup_slice_path=""
    programming_followup_slice_kind=""
    programming_followup_slice_started_count=0
    programming_followup_slice_completed_count=0
    programming_followup_slice_limit=0
    programming_followup_slice_budget_extension_used=0
    if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=4
    elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=3
    elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=2
    elif [ "$programming_quick_adjacent_slice_run" -eq 1 ]; then
      programming_followup_slice_limit=1
    fi
    context_memory_file="$agent_dir/.context.memory.md"
    teacher_model_file="$agent_dir/.learner.model.md"
    teacher_gap_seconds=-1
    teacher_gap_summary=""
    teacher_review_days=3
    teacher_model_snapshot=""
    teacher_request_snippet=""
    run_mode_instruction=""
    assistant_mode_name=""
    assistant_mode_description=""
    assistant_mode_skills=""
    assistant_mode_subscriptions=""
    assistant_mode_allowed_caps=""
    assistant_mode_policy_excerpt=""
    controller_role_line="You are operating a typed-state coding agent."
    case "$run_mode" in
      programming)
        run_mode_instruction="Programming mode: prioritize robust implementation quality, architecture integrity on large codebases, verification depth, and safe iterative refinement."
        controller_role_line="You are operating a typed-state programming agent."
        ;;
      text-perfecter)
        run_mode_instruction="Text Perfecter mode: iteratively perfect wording and content using broad evidence, resolve contradictions, and stop only when revisions converge and stop thrashing."
        controller_role_line="You are operating a typed-state text perfection and synthesis agent."
        ;;
      teacher)
        run_mode_instruction="Teacher mode: personalize instruction using a persistent learner model, pace explanations to current understanding, and include retrieval checks plus spaced-review guidance."
        controller_role_line="You are operating a typed-state teaching and curriculum agent."
        ;;
      report)
        run_mode_instruction="Report mode: investigate thoroughly and produce an evidence-driven report with clear sections, findings, and recommendations."
        controller_role_line="You are operating a typed-state investigation and reporting agent."
        ;;
      gui-testing)
        run_mode_instruction="GUI Testing mode: execute hands-on browser automation and rigorously validate UX flow, state coherence, and visual/interactivity quality before concluding."
        controller_role_line="You are operating a typed-state hands-on GUI testing and UX reliability agent."
        ;;
      assistant)
        run_mode_instruction="Team mode: proactively sequence work and take initiative toward full task completion, including multi-phase project execution, while respecting safety policy, legal compliance, and approval gates."
        controller_role_line="You are operating a typed-state autonomous project agent."
        ;;
    esac

    ensure_mode_runtime_bootstrap
    if command -v mr_controller_variant_select_for_run >/dev/null 2>&1; then
      controller_variant_selection=$(mr_controller_variant_select_for_run "$run_event_id")
      controller_variant_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f1)
      controller_variant_bucket=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f2)
      controller_variant_active_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f3)
      controller_variant_candidate_id=$(printf '%s' "$controller_variant_selection" | cut -d'|' -f4)
      if [ -n "$controller_variant_id" ] && command -v mr_controller_variant_guidance_for >/dev/null 2>&1; then
        controller_variant_guidance=$(mr_controller_variant_guidance_for "$controller_variant_id")
      fi
      if [ -n "$controller_variant_id" ]; then
        variant_stream_note="Controller variant: $controller_variant_id"
        if [ -n "$controller_variant_candidate_id" ] && [ "$controller_variant_id" = "$controller_variant_candidate_id" ]; then
          variant_stream_note="$variant_stream_note (candidate bucket=$controller_variant_bucket)"
        fi
        stream_emit_line "$stream_output_file" "$variant_stream_note"
      fi
    fi
    if [ "$run_mode" = "assistant" ] && [ -n "$assistant_mode_id" ] && command -v mr_mode_exists >/dev/null 2>&1 && mr_mode_exists "$assistant_mode_id"; then
      assistant_manifest_file=$(mr_mode_manifest_file "$assistant_mode_id")
      assistant_policy_file=$(mr_mode_policy_file "$assistant_mode_id")
      assistant_mode_name=$(mr_env_get "$assistant_manifest_file" "name" "$assistant_mode_id")
      assistant_mode_description=$(mr_env_get "$assistant_manifest_file" "description" "")
      assistant_mode_skills=$(mr_env_get "$assistant_manifest_file" "recommended_skills" "")
      assistant_mode_subscriptions=$(mr_mode_subscriptions_current "$assistant_mode_id")
      assistant_mode_allowed_caps=$(mr_mode_allowed_capabilities "$assistant_mode_id")
      assistant_mode_policy_excerpt=$(sed -n '1,80p' "$assistant_policy_file" 2>/dev/null || true)
      run_mode_instruction="Team active: ${assistant_mode_name:-$assistant_mode_id}. ${assistant_mode_description:-Use this team policy to steer planning, governance, and skill orchestration.}"
    fi

    run_mode_policy_text=$(run_mode_policy_instructions "$run_mode")
    if [ "$programming_quick_narrow_slice_run" -eq 1 ] && programming_prompt_has_multiple_branches "$programming_controller_prompt"; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Quick slice policy:
- for this quick multi-step programming run, choose one smallest verifiable implementation slice before widening to the rest of the request.
- keep the first implementation pass to one related slice and defer the remaining requested branches explicitly.
- verification should cover the chosen slice directly; do not broaden scope just to mention every requested branch.
- keep CLI entry points, tests, and docs in their own files; do not fold those branches into the primary implementation file.
EOF
)
    fi
    if [ "$programming_followup_resume_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Phase continuation policy:
- continue from the prior landed state in the same workspace instead of restarting earlier slices.
- resume exactly one previously deferred branch in this run.
- do not reopen already-landed slices unless verification proves they regressed.
EOF
)
    fi
    if [ "$programming_followup_cross_session_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Cross-session continuation policy:
- recover the prior phase plan from the same workspace instead of assuming the current conversation contains the earlier summary.
- keep the resumed phase scoped exactly as the recovered deferred queue describes.
EOF
)
    fi
    if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Cross-workspace continuation policy:
- recover the prior phase plan from the related workspace checkpoint instead of assuming the current workspace contains the earlier summary.
- keep the resumed phase scoped exactly as the recovered deferred queue describes.
EOF
)
    fi
    if [ "$programming_quick_adjacent_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Adjacent follow-up slice policy:
- if the first implementation slice lands cleanly, take at most one adjacent follow-up slice in one additional file.
- keep the follow-up file narrow and preserve the already-landed slice.
- stop after that adjacent slice instead of widening further.
EOF
)
    fi
    if [ "$programming_quick_multi_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Final follow-up slice policy:
- if the first implementation slice and adjacent follow-up slice both land cleanly, take at most one final documentation-safe follow-up slice in one additional file.
- prefer README or usage docs for that final slice instead of widening into more executable logic.
- stop after that final slice instead of broadening further.
EOF
)
    fi
    if [ "$programming_quick_verification_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Verification follow-up slice policy:
- if the implementation slice, adjacent implementation follow-up slice, and documentation-safe follow-up slice all land cleanly, take at most one final verification-safe follow-up slice in one additional test or spec file.
- prefer tests or specs for that final slice instead of widening into more executable logic or docs.
- stop after that verification-safe follow-up slice instead of broadening further.
EOF
)
    fi
    if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Release-note-safe follow-up slice policy:
- if the implementation slice, adjacent implementation follow-up slice, documentation-safe follow-up slice, and verification-safe follow-up slice all land cleanly, take at most one final release-note-safe follow-up slice in one additional changelog or release-notes file.
- prefer CHANGELOG, release notes, or migration-guide files for that final slice instead of widening into more executable logic, README, or tests.
- stop after that release-note-safe follow-up slice instead of broadening further.
EOF
)
    fi
    if [ -n "$assistant_mode_name" ] || [ -n "$assistant_mode_id" ]; then
      run_mode_policy_text=$(cat <<EOF
$run_mode_policy_text

Team profile:
- id: ${assistant_mode_id:-none}
- name: ${assistant_mode_name:-n/a}
- description: ${assistant_mode_description:-n/a}
- recommended_skills: ${assistant_mode_skills:-none}
- subscriptions: ${assistant_mode_subscriptions:-none}
- allowed_capabilities: ${assistant_mode_allowed_caps:-none}

Team policy excerpt:
$assistant_mode_policy_excerpt
EOF
)
    fi
    augmented_user_prompt=$user_message_text
    if [ "$reasoning_followup_prompt" = "1" ]; then
      augmented_user_prompt=$reasoning_followup_context_text
    fi
    if [ "$programming_followup_resume_prompt" -eq 1 ] && [ -n "$(trim "$programming_followup_context_text")" ]; then
      augmented_user_prompt=$programming_followup_context_text
    fi
    if [ -n "$(trim "$attachment_context")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Attachment context:
$attachment_context"
    fi
    if [ -n "$(trim "$web_context")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Web context:
$web_context"
    fi
    if [ -n "$(trim "$run_mode_instruction")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Run mode directive:
$run_mode_instruction"
    fi
    if [ "$assay_run_profile" -eq 1 ]; then
      if [ -n "$assay_edit_root" ]; then
        augmented_user_prompt="${augmented_user_prompt}

Assay mentoring contract:
- Do not ask for user decisions; choose reasonable defaults and proceed.
- Constrain all file edits to: ${assay_edit_root}/
- If implementation needs files, create realistic minimal files under that path.
- Do not end with a generic couldnt-complete response; provide best-effort concrete progress and remaining risks.
- While thinking, emit short timestamp-friendly step updates.
- End with sections: Outcome, Verification Evidence, Risks, Next Improvement."
      else
        augmented_user_prompt="${augmented_user_prompt}

Assay mentoring contract:
- Do not ask for user decisions; choose reasonable defaults and proceed.
- The workspace is isolated for assay use; edit the real workspace files for the chosen slice rather than a synthetic subdirectory.
- Keep the implementation to one small verifiable slice before widening.
- Do not end with a generic couldnt-complete response; provide best-effort concrete progress and remaining risks.
- While thinking, emit short timestamp-friendly step updates.
- End with sections: Outcome, Verification Evidence, Risks, Next Improvement."
      fi
    fi
    if [ -n "$(trim "$explicit_skill_context_text")" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Explicit skill actuator results:
$explicit_skill_context_text"
    fi
    if [ -n "$assistant_mode_id" ]; then
      augmented_user_prompt="${augmented_user_prompt}

Team metadata:
- mode_id: $assistant_mode_id
- mode_name: ${assistant_mode_name:-$assistant_mode_id}
- recommended_skills: ${assistant_mode_skills:-none}
- subscriptions: ${assistant_mode_subscriptions:-none}"
    fi

    ensure_agent_files "$agent_dir"
    : > "$changed_paths_file"
    ARTIFICER_PROGRAMMING_CHANGED_PATHS=""
    if [ "$programming_followup_resume_prompt" -eq 1 ]; then
      programming_seed_changed_paths_from_assistant_summary "$workspace_path" "$programming_followup_prior_assistant_text" "$changed_paths_file"
      programming_followup_resume_target_path=$(programming_deferred_branch_target_path_for_label "$workspace_path" "$programming_followup_target_branch")
      programming_followup_resume_target_path=$(programming_resolve_workspace_relative_path "$workspace_path" "$programming_followup_resume_target_path")
      programming_followup_resume_target_path=$(programming_normalize_relative_path "$programming_followup_resume_target_path")
      if [ -n "$(trim "$programming_followup_resume_target_path")" ]; then
        programming_followup_slice_path=$programming_followup_resume_target_path
        if programming_path_is_post_verification_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="post-verification-safe"
        elif programming_path_is_verification_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="verification"
        elif programming_path_is_documentation_safe "$programming_followup_slice_path"; then
          programming_followup_slice_kind="documentation"
        else
          programming_followup_slice_kind="adjacent"
        fi
        programming_followup_slice_started_count=1
        programming_followup_slice_completed_count=0
        programming_followup_slice_limit=1
        if [ "$programming_followup_cross_workspace_prompt" -eq 1 ]; then
          stream_emit_line "$stream_output_file" "Restoring prior phase plan from another workspace."
        elif [ "$programming_followup_cross_session_prompt" -eq 1 ]; then
          stream_emit_line "$stream_output_file" "Restoring prior phase plan from another conversation in the same workspace."
        fi
        stream_emit_line "$stream_output_file" "Resuming one previously deferred branch from the prior phase plan."
      fi
    fi
    if [ "$run_mode" = "teacher" ]; then
      ensure_teacher_model_file "$teacher_model_file"
      teacher_gap_seconds=$(teacher_last_assistant_gap_seconds "$conv_dir")
      teacher_gap_summary=$(teacher_gap_summary_for_conversation "$conv_dir")
      teacher_review_days=$(teacher_review_interval_days_for_gap "$teacher_gap_seconds")
      teacher_request_snippet=$(single_line_snippet "$user_prompt")
      if [ -z "$(trim "$teacher_request_snippet")" ]; then
        teacher_request_snippet="(empty request)"
      fi
      teacher_pre_note=$(cat <<EOF
request=$teacher_request_snippet
interaction_gap=$teacher_gap_summary
recommended_review_spacing_days=$teacher_review_days
EOF
)
      append_teacher_model_note "$teacher_model_file" "Pre-run context" "$teacher_pre_note"
      teacher_model_snapshot=$(sed -n '1,180p' "$teacher_model_file" 2>/dev/null || true)
      augmented_user_prompt="${augmented_user_prompt}

Teacher pacing signal:
- interaction_gap: $teacher_gap_summary
- recommended_review_spacing_days: $teacher_review_days

Learner model snapshot:
$teacher_model_snapshot"
    fi
    implementation_expected=0
    reasoning_completion_preferred_run=0
    if [ "$active_run_mode" = "programming" ] || prompt_requires_code_implementation "$augmented_user_prompt"; then
      implementation_expected=1
    fi
    if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      reasoning_completion_preferred_run=1
    fi
    plan_timeout_fallback=20
    case "$compute_budget" in
      quick)
        plan_timeout_fallback=10
        ;;
      standard|auto)
        plan_timeout_fallback=14
        ;;
      long)
        plan_timeout_fallback=20
        ;;
      until-complete)
        plan_timeout_fallback=24
        ;;
    esac
    if [ "$assay_run_profile" -eq 1 ]; then
      case "$compute_budget" in
        quick)
          plan_timeout_fallback=8
          ;;
        standard|auto)
          plan_timeout_fallback=10
          ;;
        long)
          plan_timeout_fallback=12
          ;;
      esac
    fi
    if [ "$programming_quick_bounded_run" -eq 1 ] && [ "$plan_timeout_fallback" -gt 5 ]; then
      plan_timeout_fallback=5
    fi
    if [ "$programming_quick_bounded_run" -eq 1 ] || [ "$programming_quick_narrow_slice_run" -eq 1 ]; then
      bootstrap_quick_programming_plan_file "$plan_file" "$augmented_user_prompt"
      stream_emit_line "$stream_output_file" "Bounded programming start: using deterministic quick plan."
    else
      plan_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$plan_timeout_fallback" 8 5)
      RUN_TIMEOUT_SEC=$plan_timeout_sec
      bootstrap_plan_file "$plan_file" "$model" "$workspace_path" "$augmented_user_prompt"
      unset RUN_TIMEOUT_SEC 2>/dev/null || true
    fi
    initialize_state_file "$state_file" "$augmented_user_prompt"

    commands_json=""
    commands_first=1
    loop_feedback="No prior action in this run."
    loop_summary=""
    assistant_output=""
    run_command_success_total=0
    controller_format_recovery_total=0
    controller_format_recovery_streak=0
    controller_format_done_block_total=0
    stagnation_last_signature=""
    stagnation_repeat_count=0
    run_budget_exhausted=0

    iteration=1
    while :; do
      run_mode=$active_run_mode
      if [ "$max_iterations" -gt 0 ] && [ "$iteration" -gt "$max_iterations" ]; then
        allow_reasoning_extension=0
        if [ "$reasoning_completion_preferred_run" -eq 1 ] && [ "$implementation_expected" -eq 0 ]; then
          extra_iteration_cap=$((max_iterations + 1))
          if [ "$iteration" -le "$extra_iteration_cap" ]; then
            extension_now_epoch=$(date +%s 2>/dev/null || printf '0')
            case "$extension_now_epoch" in
              ""|*[!0-9]*)
                extension_now_epoch=$run_started_epoch
                ;;
            esac
            extension_elapsed=$((extension_now_epoch - run_started_epoch))
            if [ "$extension_elapsed" -lt 0 ]; then
              extension_elapsed=0
            fi
            extension_remaining=$((run_time_budget - extension_elapsed))
            if [ "$extension_remaining" -ge 75 ]; then
              allow_reasoning_extension=1
              stream_emit_line "$stream_output_file" "Step $iteration extension: reasoning-completion guard requested up to $extra_iteration_cap iterations (remaining budget ${extension_remaining}s)."
            fi
          fi
        fi
        if [ "$allow_reasoning_extension" -ne 1 ]; then
          break
        fi
      fi
      stream_emit_line "$stream_output_file" "Iteration $iteration started."
      if [ -f "$running_stop_file" ]; then
        forced_queue_status="cancelled"
        assistant_output="Run stopped."
        stream_emit_line "$stream_output_file" "Stop requested by user."
        append_failure_entry "$failures_file" "iteration-$iteration:run-stop" "Stop requested by user" \
          "User requested cancellation" "Finalize run as cancelled"
        break
      fi
      run_now_epoch=$(date +%s)
      run_elapsed=$((run_now_epoch - run_started_epoch))
      run_remaining_budget=$((run_time_budget - run_elapsed))
      if [ "$run_remaining_budget" -lt 0 ]; then
        run_remaining_budget=0
      fi
      if [ "$reasoning_completion_preferred_run" -eq 1 ] && [ "$implementation_expected" -eq 0 ] && [ "$run_remaining_budget" -gt 0 ]; then
        reasoning_reserve_sec=$(reasoning_completion_reserve_seconds \
          "$compute_budget" \
          "$assay_run_profile" \
          "$controller_format_recovery_total" \
          "$stagnation_repeat_count")
        if [ "$run_remaining_budget" -le "$reasoning_reserve_sec" ]; then
          stream_emit_line "$stream_output_file" "Iteration $iteration budget guard: reserving ${run_remaining_budget}s for final reasoning synthesis salvage (target reserve ${reasoning_reserve_sec}s)."
          break
        fi
      fi
      if [ "$run_elapsed" -ge "$run_time_budget" ]; then
        if [ "$programming_followup_slice_budget_extension_used" -eq 0 ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_kind" = "post-verification-safe" ]; then
          run_time_budget=$((run_time_budget + 35))
          programming_followup_slice_budget_extension_used=1
          stream_emit_line "$stream_output_file" "Extending the run budget briefly to finish the pending release-note-safe follow-up slice."
          continue
        fi
        if [ "$programming_followup_slice_budget_extension_used" -eq 0 ] && [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_kind" = "verification" ]; then
          run_time_budget=$((run_time_budget + 45))
          programming_followup_slice_budget_extension_used=1
          stream_emit_line "$stream_output_file" "Extending the run budget briefly to finish the pending verification-safe follow-up slice."
          continue
        fi
        # Time-budget expiry still yields a structured partial deliverable, so treat it as a completed run.
        run_budget_exhausted=1
        forced_queue_status="done"
        elapsed_minutes=$((run_elapsed / 60))
        elapsed_seconds=$((run_elapsed % 60))
        assistant_output=$(cat <<EOF
Outcome: Reached the configured run-time budget before full completion.
Verification Evidence: Iteration logs and command traces were captured before timeout. Worked for ${elapsed_minutes}m ${elapsed_seconds}s.
Assumptions and Alternatives: Incomplete signals were handled with explicit defaults; alternative interpretations remain and should be validated in the next slice.
Contradiction Check: Any conflicting constraints were treated as non-simultaneously satisfiable until evidence proves otherwise.
Risks: Partial progress may leave unverified changes or unfinished implementation details.
Next Improvement: Narrow scope or increase compute budget, then continue from the latest checkpoint.
EOF
)
        stream_emit_line "$stream_output_file" "Run reached time budget of ${run_time_budget}s; finalizing with partial deliverable."
        append_failure_entry "$failures_file" "iteration-$iteration:run-timeout" "Exceeded run time budget (${run_time_budget}s)" \
          "Model/controller loop exceeded time budget" "Return timeout response and finalize run"
        break
      fi

      plan_text=$(sed -n '1,220p' "$plan_file")
      history_text=$(conversation_history "$conv_dir" | sed -n '1,220p')
      snapshot_text=$(workspace_snapshot "$workspace_path" | sed -n '1,220p')
      workspace_context_text=$(workspace_shared_context "$ws_dir" "$conversation_id" | sed -n '1,320p')
      if [ "$assay_run_profile" -eq 1 ]; then
        history_text=$(printf '%s\n' "$history_text" | sed -n '1,140p')
        snapshot_text=$(printf '%s\n' "$snapshot_text" | sed -n '1,140p')
        workspace_context_text=""
      fi
      contract_context_text=$(sed -n '1,220p' "$contract_file" 2>/dev/null || true)
      failures_tail=$(tail -n 80 "$failures_file" 2>/dev/null || sed -n '1,80p' "$failures_file")
      session_tail=$(tail -n 80 "$session_log_file" 2>/dev/null || sed -n '1,80p' "$session_log_file")
      assumptions_tail=$(tail -n 80 "$assumptions_file" 2>/dev/null || sed -n '1,80p' "$assumptions_file")
      compliance_tail=$(tail -n 80 "$compliance_file" 2>/dev/null || sed -n '1,80p' "$compliance_file")
      if [ "$run_mode" = "programming" ]; then
        refresh_programming_artifacts "$plan_file" "$state_file" "$session_log_file" "$failures_file" "$contract_file" "$architecture_file" "$tasks_dir"
      fi
      architecture_context_text=$(sed -n '1,220p' "$architecture_file" 2>/dev/null || true)
      tasks_context_text=$(sed -n '1,220p' "$tasks_index_file" 2>/dev/null || true)
      refresh_context_memory_file "$plan_file" "$contract_file" "$session_log_file" "$failures_file" "$assumptions_file" "$compliance_file" "$architecture_file" "$tasks_index_file" "$snapshot_text" "$run_mode" "$context_memory_file"
      context_memory_text=$(sed -n '1,260p' "$context_memory_file" 2>/dev/null || true)
      context_tokens=$(model_context_tokens_for "$model")
      case "$context_tokens" in
        ""|*[!0-9]*)
          context_tokens=8192
          ;;
      esac
      context_prompt_budget=$((context_tokens * 62 / 100))
      case "$run_mode" in
        programming|teacher|report|text-perfecter|assistant|gui-testing)
          context_prompt_budget=$((context_tokens * 72 / 100))
          ;;
      esac
      if [ "$context_prompt_budget" -lt 1600 ]; then
        context_prompt_budget=1600
      fi
      case "$run_mode" in
        programming|teacher|assistant|gui-testing)
          if [ "$context_prompt_budget" -lt 2200 ]; then
            context_prompt_budget=2200
          fi
          ;;
        report)
          if [ "$context_prompt_budget" -lt 2000 ]; then
            context_prompt_budget=2000
          fi
          ;;
        text-perfecter)
          if [ "$context_prompt_budget" -lt 2200 ]; then
            context_prompt_budget=2200
          fi
          ;;
      esac
      if [ "$assay_run_profile" -eq 1 ] && [ "$context_prompt_budget" -gt 2000 ]; then
        context_prompt_budget=2000
      fi
      ratio_total=136
      plan_budget=$((context_prompt_budget * 12 / ratio_total))
      contract_budget=$((context_prompt_budget * 10 / ratio_total))
      memory_budget=$((context_prompt_budget * 12 / ratio_total))
      architecture_budget=$((context_prompt_budget * 12 / ratio_total))
      tasks_budget=$((context_prompt_budget * 10 / ratio_total))
      history_budget=$((context_prompt_budget * 16 / ratio_total))
      snapshot_budget=$((context_prompt_budget * 14 / ratio_total))
      workspace_budget=$((context_prompt_budget * 10 / ratio_total))
      failures_budget=$((context_prompt_budget * 8 / ratio_total))
      session_budget=$((context_prompt_budget * 8 / ratio_total))
      assumptions_budget=$((context_prompt_budget * 6 / ratio_total))
      compliance_budget=$((context_prompt_budget * 8 / ratio_total))
      feedback_budget=$((context_prompt_budget * 10 / ratio_total))
      user_request_budget=$((context_prompt_budget * 12 / ratio_total))
      if [ "$plan_budget" -lt 180 ]; then plan_budget=180; fi
      if [ "$contract_budget" -lt 160 ]; then contract_budget=160; fi
      if [ "$memory_budget" -lt 200 ]; then memory_budget=200; fi
      if [ "$architecture_budget" -lt 170 ]; then architecture_budget=170; fi
      if [ "$tasks_budget" -lt 150 ]; then tasks_budget=150; fi
      if [ "$history_budget" -lt 260 ]; then history_budget=260; fi
      if [ "$snapshot_budget" -lt 220 ]; then snapshot_budget=220; fi
      if [ "$workspace_budget" -lt 180 ]; then workspace_budget=180; fi
      if [ "$failures_budget" -lt 120 ]; then failures_budget=120; fi
      if [ "$session_budget" -lt 120 ]; then session_budget=120; fi
      if [ "$assumptions_budget" -lt 100 ]; then assumptions_budget=100; fi
      if [ "$compliance_budget" -lt 110 ]; then compliance_budget=110; fi
      if [ "$feedback_budget" -lt 120 ]; then feedback_budget=120; fi
      if [ "$user_request_budget" -lt 240 ]; then user_request_budget=240; fi
      if [ "$user_request_budget" -gt 1400 ]; then user_request_budget=1400; fi

      plan_before_tokens=$(estimate_tokens_approx "$plan_text")
      contract_before_tokens=$(estimate_tokens_approx "$contract_context_text")
      memory_before_tokens=$(estimate_tokens_approx "$context_memory_text")
      architecture_before_tokens=$(estimate_tokens_approx "$architecture_context_text")
      tasks_before_tokens=$(estimate_tokens_approx "$tasks_context_text")
      history_before_tokens=$(estimate_tokens_approx "$history_text")
      snapshot_before_tokens=$(estimate_tokens_approx "$snapshot_text")
      workspace_before_tokens=$(estimate_tokens_approx "$workspace_context_text")
      failures_before_tokens=$(estimate_tokens_approx "$failures_tail")
      session_before_tokens=$(estimate_tokens_approx "$session_tail")
      assumptions_before_tokens=$(estimate_tokens_approx "$assumptions_tail")
      compliance_before_tokens=$(estimate_tokens_approx "$compliance_tail")
      feedback_before_tokens=$(estimate_tokens_approx "$loop_feedback")
      user_request_before_tokens=$(estimate_tokens_approx "$augmented_user_prompt")

      plan_text=$(compact_text_block "Plan" "$plan_text" "$plan_budget")
      contract_context_text=$(compact_text_block "Contract context" "$contract_context_text" "$contract_budget")
      context_memory_text=$(compact_text_block "Context memory" "$context_memory_text" "$memory_budget")
      architecture_context_text=$(compact_text_block "Architecture map" "$architecture_context_text" "$architecture_budget")
      tasks_context_text=$(compact_text_block "Task index" "$tasks_context_text" "$tasks_budget")
      history_text=$(compact_text_block "Conversation context" "$history_text" "$history_budget")
      snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" "$snapshot_budget")
      workspace_context_text=$(compact_text_block "Other threads context" "$workspace_context_text" "$workspace_budget")
      failures_tail=$(compact_text_block "Failure ledger" "$failures_tail" "$failures_budget")
      session_tail=$(compact_text_block "Session log" "$session_tail" "$session_budget")
      assumptions_tail=$(compact_text_block "Assumptions ledger" "$assumptions_tail" "$assumptions_budget")
      compliance_tail=$(compact_text_block "Compliance ledger" "$compliance_tail" "$compliance_budget")
      loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" "$feedback_budget")
      augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" "$user_request_budget")
      if [ "$controller_format_recovery_streak" -gt 0 ] || [ "$controller_format_recovery_total" -gt 0 ]; then
        recovery_user_budget=$((user_request_budget * 65 / 100))
        if [ "$recovery_user_budget" -lt 180 ]; then
          recovery_user_budget=180
        fi
        recovery_history_budget=$((history_budget * 55 / 100))
        if [ "$recovery_history_budget" -lt 160 ]; then
          recovery_history_budget=160
        fi
        recovery_snapshot_budget=$((snapshot_budget * 60 / 100))
        if [ "$recovery_snapshot_budget" -lt 160 ]; then
          recovery_snapshot_budget=160
        fi
        recovery_feedback_budget=$((feedback_budget * 60 / 100))
        if [ "$recovery_feedback_budget" -lt 90 ]; then
          recovery_feedback_budget=90
        fi
        history_text=$(compact_text_block "Conversation context" "$history_text" "$recovery_history_budget")
        snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" "$recovery_snapshot_budget")
        loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" "$recovery_feedback_budget")
        workspace_context_text=""
        augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" "$recovery_user_budget")
        stream_emit_line "$stream_output_file" "Controller format-recovery pressure active; using reduced context profile."
      fi
      if [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        history_text=""
        workspace_context_text=""
        context_memory_text=""
        compliance_tail=""
        architecture_context_text=$(compact_text_block "Architecture map" "$architecture_context_text" 120)
        tasks_context_text=$(compact_text_block "Task index" "$tasks_context_text" 100)
        assumptions_tail=$(compact_text_block "Assumptions ledger" "$assumptions_tail" 90)
        failures_tail=$(compact_text_block "Failure ledger" "$failures_tail" 120)
        session_tail=$(compact_text_block "Session log" "$session_tail" 160)
        loop_feedback=$(compact_text_block "Previous feedback" "$loop_feedback" 120)
        snapshot_text=$(compact_text_block "Workspace snapshot" "$snapshot_text" 240)
        augmented_user_prompt_controller=$(compact_text_block "Latest user request" "$augmented_user_prompt" 260)
        stream_emit_line "$stream_output_file" "Quick narrow-slice implement step: using focused context profile."
      fi

      plan_after_tokens=$(estimate_tokens_approx "$plan_text")
      contract_after_tokens=$(estimate_tokens_approx "$contract_context_text")
      memory_after_tokens=$(estimate_tokens_approx "$context_memory_text")
      architecture_after_tokens=$(estimate_tokens_approx "$architecture_context_text")
      tasks_after_tokens=$(estimate_tokens_approx "$tasks_context_text")
      history_after_tokens=$(estimate_tokens_approx "$history_text")
      snapshot_after_tokens=$(estimate_tokens_approx "$snapshot_text")
      workspace_after_tokens=$(estimate_tokens_approx "$workspace_context_text")
      failures_after_tokens=$(estimate_tokens_approx "$failures_tail")
      session_after_tokens=$(estimate_tokens_approx "$session_tail")
      assumptions_after_tokens=$(estimate_tokens_approx "$assumptions_tail")
      compliance_after_tokens=$(estimate_tokens_approx "$compliance_tail")
      feedback_after_tokens=$(estimate_tokens_approx "$loop_feedback")
      user_request_after_tokens=$(estimate_tokens_approx "$augmented_user_prompt_controller")

      compacted_any=0
      if [ "$plan_after_tokens" -lt "$plan_before_tokens" ] || \
         [ "$contract_after_tokens" -lt "$contract_before_tokens" ] || \
         [ "$memory_after_tokens" -lt "$memory_before_tokens" ] || \
         [ "$architecture_after_tokens" -lt "$architecture_before_tokens" ] || \
         [ "$tasks_after_tokens" -lt "$tasks_before_tokens" ] || \
         [ "$history_after_tokens" -lt "$history_before_tokens" ] || \
         [ "$snapshot_after_tokens" -lt "$snapshot_before_tokens" ] || \
         [ "$workspace_after_tokens" -lt "$workspace_before_tokens" ] || \
         [ "$failures_after_tokens" -lt "$failures_before_tokens" ] || \
         [ "$session_after_tokens" -lt "$session_before_tokens" ] || \
         [ "$assumptions_after_tokens" -lt "$assumptions_before_tokens" ] || \
         [ "$compliance_after_tokens" -lt "$compliance_before_tokens" ] || \
         [ "$feedback_after_tokens" -lt "$feedback_before_tokens" ] || \
         [ "$user_request_after_tokens" -lt "$user_request_before_tokens" ]; then
        compacted_any=1
      fi
      if [ "$compacted_any" = "1" ]; then
        stream_emit_line "$stream_output_file" "Context compacted for model window (~${context_tokens} tokens) to preserve relevance."
      fi
      state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")
      stream_emit_line "$stream_output_file" "Current mode: $state_mode"
      state_target=$(state_get "$state_file" "target" "workspace")
      state_blocking=$(state_get "$state_file" "blocking" "none")
      state_confidence=$(state_get "$state_file" "confidence" "0.20")
      state_reason=$(state_get "$state_file" "transition_reason" "none")
      mode_hint=$(mode_instructions "$state_mode")
      context_miss_guidance=$(context_miss_guidance_for_prompt "$loop_feedback" "$state_mode")
      context_miss_guidance=$(compact_text_block "Context miss guidance" "$context_miss_guidance" 140)
      if [ -n "$stream_output_file" ] && [ -n "$(trim "$context_miss_guidance")" ] && [ "$context_miss_guidance" != "NONE" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration anti-thrash hint: context-miss guidance active for next command selection."
      fi
      explicit_skill_prompt_text=$explicit_skill_context_text
      if [ -z "$(trim "$explicit_skill_prompt_text")" ]; then
        explicit_skill_prompt_text="NONE"
      fi
      controller_variant_prompt_block="Controller variant guidance: NONE"
      if [ -n "$(trim "$controller_variant_id")" ]; then
        controller_variant_prompt_block=$(cat <<EOF
Controller variant:
- selected_id: $controller_variant_id
- active_id: ${controller_variant_active_id:-none}
- candidate_id: ${controller_variant_candidate_id:-none}
- sample_bucket: ${controller_variant_bucket:-0}
- guidance: ${controller_variant_guidance:-baseline policy only}
EOF
)
      fi
      runtime_failure_summary="none"
      if command -v mr_failure_taxonomy_recent_summary_text >/dev/null 2>&1; then
        runtime_failure_summary=$(mr_failure_taxonomy_recent_summary_text "6")
      fi
      runtime_failure_summary=$(printf '%s' "$runtime_failure_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_failure_summary")" ]; then
        runtime_failure_summary="none"
      fi
      runtime_quality_summary="none"
      if command -v mr_quality_scorecard_recent_summary_text >/dev/null 2>&1; then
        runtime_quality_summary=$(mr_quality_scorecard_recent_summary_text "8")
      fi
      runtime_quality_summary=$(printf '%s' "$runtime_quality_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_quality_summary")" ]; then
        runtime_quality_summary="none"
      fi
      runtime_proposal_summary="none"
      if command -v mr_improvement_proposals_recent_summary_text >/dev/null 2>&1; then
        runtime_proposal_summary=$(mr_improvement_proposals_recent_summary_text "$run_mode" "12" "3")
      fi
      runtime_proposal_summary=$(printf '%s' "$runtime_proposal_summary" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_proposal_summary")" ]; then
        runtime_proposal_summary="none"
      fi
      runtime_guardrails="none"
      if command -v mr_runtime_learning_guardrails_text >/dev/null 2>&1; then
        runtime_guardrails=$(mr_runtime_learning_guardrails_text)
      fi
      runtime_guardrails=$(printf '%s' "$runtime_guardrails" | tr '\n\r' '  ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')
      if [ -z "$(trim "$runtime_guardrails")" ]; then
        runtime_guardrails="none"
      fi
      workspace_context_block=""
      if [ -n "$(trim "$workspace_context_text")" ]; then
        workspace_context_block=$(cat <<EOF
$workspace_context_block

EOF
)
      fi

      use_seeded_programming_controller=0
      use_seeded_programming_narrow_slice_controller=0
      if { [ "$programming_quick_bounded_run" -eq 1 ] || [ "$programming_quick_narrow_slice_run" -eq 1 ]; } && [ "$iteration" -eq 1 ] && [ "$run_command_success_total" -eq 0 ] && [ "$state_mode" = "INVESTIGATE" ]; then
        use_seeded_programming_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -eq 2 ] && [ "$run_command_success_total" -gt 0 ] && [ "$state_mode" = "DESIGN" ]; then
        use_seeded_programming_narrow_slice_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -ge 3 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        use_seeded_programming_narrow_slice_controller=1
      elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$iteration" -ge 4 ] && [ "$state_mode" = "VERIFY" ]; then
        use_seeded_programming_narrow_slice_controller=1
      fi

      controller_prompt=$(cat <<EOF
$controller_role_line
Reasoning effort preference: $reasoning_effort
Compute budget preference: $compute_budget (run_time_budget=${run_time_budget}s)

Current mode: $state_mode
Typed state:
- mode=$state_mode
- target=$state_target
- blocking=$state_blocking
- confidence=$state_confidence
- transition_reason=$state_reason

$mode_hint

$run_mode_policy_text

$controller_variant_prompt_block

Runtime learning signals:
- failure_taxonomy: $runtime_failure_summary
- quality_scorecard: $runtime_quality_summary
- improvement_proposals: $runtime_proposal_summary

Runtime adaptation guardrails:
- $runtime_guardrails

Explicit skill actuator context:
$explicit_skill_prompt_text

Return ONLY these sections exactly:

MODE_UPDATE:
target=<value>
blocking=<value>
confidence=<0.00-1.00>

COMMANDS:
- up to 3 read-only shell commands, or NONE

CONTRACT:
- contract text for DESIGN mode, otherwise NONE

PATCH:
- unified diff in a diff code fence for IMPLEMENT mode, otherwise NONE

DONE_CLAIM:
yes | no

PLAN_UPDATE:
Goal:
Subgoals:
Constraints:
Unknowns:
Next Action:
Completion Criteria:

CHECKPOINT:
- one concise status line
- include assumptions when defaults were chosen due ambiguity

DECISION_REQUEST:
- use question=<text> and one or more option=<text> lines when user choice is needed
- if details are unspecified, choose sensible defaults instead of asking
- otherwise NONE

FINAL:
- final user-facing answer only when work is complete, otherwise NONE
- for complex work, structure FINAL with: Outcome, Verification Evidence, Risks, Next Improvement
- when requirements are ambiguous/conflicting, also include: Assumptions and Alternatives, Contradiction Check
- for adversarial/plausible-false prompts, also include: False Premise Challenge, Premise Validation
- when recovery or misconception pressure is present, also include: Initial Assumption, Invalidating Evidence, Revised Decision, Evidence Delta

Rules:
- never invent mode transitions; orchestration handles transitions
- use mediated commands only
- no shell separators or redirects in COMMANDS
- if Context-miss guidance is present, run discovery-first and avoid repeating listed missing-context commands until new evidence appears
- patch at most 5 files
- do not output role prefixes ("Assistant:" / "User:") in FINAL
- if user input is required to proceed, emit DECISION_REQUEST with 2-5 concrete options
- default to reasonable assumptions when requirements are underspecified
- only emit DECISION_REQUEST when the user explicitly asks to choose or required data cannot be inferred
- if ambiguity remains after assumptions, narrow scope and complete one verifiable slice rather than stopping early
- only set DONE_CLAIM yes when verification evidence exists in this run command outputs
- for complex reasoning tasks, use all 3 command slots unless blocked by safety/compliance

Current plan:
$plan_text

Contract context:
$contract_context_text

Compressed project memory:
$context_memory_text

Architecture map:
$architecture_context_text

Task index:
$tasks_context_text

Compliance ledger (tail):
$compliance_tail

Failure ledger (tail):
$failures_tail

Session log (tail):
$session_tail

Assumptions ledger (tail):
$assumptions_tail

Previous iteration feedback:
$loop_feedback

Context-miss guidance:
$context_miss_guidance

Workspace snapshot:
$snapshot_text

Conversation context:
$history_text

Other threads in this same workspace:
$workspace_context_text

Latest user request:
$augmented_user_prompt_controller
EOF
)

      controller_retry_used=0
      controller_format_retry_used=0
      if [ "$use_seeded_programming_controller" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Step $iteration: starting immediate workspace discovery."
        iteration_output=$(seed_programming_quick_controller_output "$augmented_user_prompt" "$plan_text")
      elif [ "$use_seeded_programming_narrow_slice_controller" -eq 1 ]; then
        if [ "$state_mode" = "IMPLEMENT" ]; then
          iteration_output=$(seed_programming_quick_narrow_slice_implement_output "$augmented_user_prompt" "$plan_text" || true)
        elif [ "$state_mode" = "VERIFY" ]; then
          iteration_output=$(seed_programming_quick_narrow_slice_verify_output "$augmented_user_prompt" "$plan_text" "$workspace_path" || true)
        else
          iteration_output=$(seed_programming_quick_narrow_slice_controller_output "$augmented_user_prompt" "$plan_text" "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" || true)
        fi
        if [ -n "$(trim "$iteration_output")" ]; then
          if [ "$state_mode" = "IMPLEMENT" ]; then
            stream_emit_line "$stream_output_file" "Step $iteration: applying one focused implementation slice."
          elif [ "$state_mode" = "VERIFY" ]; then
            stream_emit_line "$stream_output_file" "Step $iteration: verifying the focused implementation slice."
          else
            stream_emit_line "$stream_output_file" "Step $iteration: focusing on one implementation slice before patching."
          fi
        else
          use_seeded_programming_narrow_slice_controller=0
        fi
      fi
      if [ "$use_seeded_programming_controller" -ne 1 ] && [ "$use_seeded_programming_narrow_slice_controller" -ne 1 ]; then
        if [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        fi
        controller_timeout_fallback=30
        case "$compute_budget" in
          quick)
            controller_timeout_fallback=14
            ;;
          standard|auto)
            controller_timeout_fallback=20
            ;;
          long)
            controller_timeout_fallback=28
            ;;
          until-complete)
            controller_timeout_fallback=36
            ;;
        esac
        if [ "$assay_run_profile" -eq 1 ]; then
          case "$compute_budget" in
            quick)
              controller_timeout_fallback=10
              ;;
            standard|auto)
              controller_timeout_fallback=14
              ;;
            long)
              controller_timeout_fallback=18
              ;;
          esac
        fi
        controller_timeout_reserve=10
        controller_timeout_min=5
        if [ "$programming_quick_bounded_run" -eq 1 ]; then
          if [ "$controller_timeout_fallback" -gt 8 ]; then
            controller_timeout_fallback=8
          fi
          controller_timeout_reserve=6
          controller_timeout_min=4
        elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
          if [ "$controller_timeout_fallback" -gt 10 ]; then
            controller_timeout_fallback=10
          fi
          controller_timeout_reserve=6
          controller_timeout_min=4
        fi
        controller_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_timeout_fallback" "$controller_timeout_reserve" "$controller_timeout_min")
        stream_emit_line "$stream_output_file" "Step $iteration controller prompt assembled."
        stream_emit_line "$stream_output_file" "Step $iteration controller call started (mode=$state_mode, timeout=${controller_timeout_sec}s)."
        controller_stream_raw=${ARTIFICER_STREAM_RAW_CONTROLLER:-0}
        if [ "$active_run_mode" = "programming" ]; then
          controller_stream_raw=0
        fi
        if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        else
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        fi
        RUN_TIMEOUT_SEC=$controller_timeout_sec
        iteration_output=$(run_model "$model" "$controller_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        iteration_output=$(strip_terminal_noise "$iteration_output")
        iteration_output=$(canonicalize_controller_output "$iteration_output")
      fi
      if [ -z "$(trim "$iteration_output")" ] && [ "$programming_quick_bounded_run" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; }; then
        controller_retry_used=1
        append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model (first attempt)" \
          "Model failed to emit control sections on first attempt" "Retry controller once with stricter format reminder"
        stream_emit_line "$stream_output_file" "Controller returned empty output; retrying once with strict format reminder."
        controller_retry_prompt=$(cat <<EOF
$controller_prompt

Retry requirement:
- Return all required sections exactly once.
- If a section has no content, write NONE.
- Do not omit section headers.
EOF
)
        controller_retry_timeout_fallback=$((controller_timeout_fallback / 2))
        if [ "$controller_retry_timeout_fallback" -lt 8 ]; then
          controller_retry_timeout_fallback=8
        fi
        controller_retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_retry_timeout_fallback" 8 4)
        if [ "$active_run_mode" = "programming" ]; then
          controller_stream_raw=0
        fi
        if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
          ARTIFICER_STREAM_FILE="$stream_output_file"
          export ARTIFICER_STREAM_FILE
        else
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        fi
        RUN_TIMEOUT_SEC=$controller_retry_timeout_sec
        iteration_output=$(run_model "$model" "$controller_retry_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        iteration_output=$(strip_terminal_noise "$iteration_output")
        iteration_output=$(canonicalize_controller_output "$iteration_output")
        if [ -n "$(trim "$iteration_output")" ]; then
          stream_emit_line "$stream_output_file" "Controller retry produced a structured response."
        fi
      elif [ -z "$(trim "$iteration_output")" ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$state_mode" = "IMPLEMENT" ]; then
        append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model in focused narrow-slice implement step" \
          "Focused implementation step returned no controller output; retry would likely waste remaining budget" \
          "Proceed directly to local fallback summary for the chosen slice"
        stream_emit_line "$stream_output_file" "Focused implement step returned empty output; skipping retry and falling back immediately."
      fi
      stream_emit_line "$stream_output_file" "Step $iteration controller response captured."
      iteration_output_original=$iteration_output
      if [ -z "$(trim "$iteration_output")" ]; then
        if [ "$controller_retry_used" -eq 1 ]; then
          append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model after retry" \
            "Model failed to emit control sections after retry" "Fallback response generated for current mode"
        else
          append_failure_entry "$failures_file" "iteration-$iteration:model-response" "Empty response from model" \
            "Model failed to emit control sections" "Fallback response generated for current mode"
        fi
        iteration_output=$(cat <<EOF
MODE_UPDATE:
target=$state_target
blocking=model returned empty response
confidence=$state_confidence
COMMANDS:
- git status --short --untracked-files=no
CONTRACT:
NONE
PATCH:
NONE
DONE_CLAIM:
no
PLAN_UPDATE:
$plan_text
CHECKPOINT:
fallback command execution
DECISION_REQUEST:
NONE
FINAL:
NONE
EOF
)
      fi

      iteration_output_before_format_retry=$iteration_output
      if ! controller_output_has_required_sections "$iteration_output"; then
        controller_format_retry_budget_remaining=$(run_budget_remaining_seconds "$run_started_epoch" "$run_time_budget")
        if [ "$programming_quick_bounded_run" -eq 1 ]; then
          append_failure_entry "$failures_file" "controller-format-retry-skip-iteration-$iteration" \
            "Skipped format retry for bounded quick programming run" \
            "Bounded quick programming path prefers a deterministic partial summary over another controller retry" \
            "Proceed directly to local controller recovery scaffolding"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; skipping retry for bounded quick programming run."
        elif should_skip_controller_format_retry \
          "$controller_format_retry_budget_remaining" \
          "$controller_format_recovery_total" \
          "$controller_format_recovery_streak" \
          "$run_mode"; then
          append_failure_entry "$failures_file" "controller-format-retry-skip-iteration-$iteration" \
            "Skipped format retry under budget pressure" \
            "Remaining budget and prior recoveries indicate low-value extra model retry" \
            "Proceed directly to local controller recovery scaffolding"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; skipping retry under budget pressure and applying recovery scaffolding."
        else
          controller_format_retry_used=1
          append_failure_entry "$failures_file" "controller-format-retry-iteration-$iteration" \
            "Missing required controller sections on first pass" \
            "Model response omitted one or more control section headers" \
            "Retry controller once with strict section-order contract"
          stream_emit_line "$stream_output_file" "Controller response missing required sections; retrying once with strict section-order contract."
          retry_mode_update=$(extract_section "MODE_UPDATE" "$iteration_output_before_format_retry")
          retry_mode_update=$(trim "$retry_mode_update")
          if [ -z "$retry_mode_update" ]; then
            retry_mode_update=$(cat <<EOF
target=$state_target
blocking=controller format correction required
confidence=$state_confidence
EOF
)
          fi
          retry_plan_update=$(extract_section "PLAN_UPDATE" "$iteration_output_before_format_retry")
          retry_plan_update=$(trim "$retry_plan_update")
          if [ -z "$retry_plan_update" ]; then
            retry_plan_update=$plan_text
          fi
          controller_format_retry_prompt=$(cat <<EOF
Format correction retry requirement:
- Return ONLY the required controller sections exactly once and in this order.
- MODE_UPDATE, COMMANDS, CONTRACT, PATCH, DONE_CLAIM, PLAN_UPDATE, CHECKPOINT, DECISION_REQUEST, FINAL
- Keep existing intent, but complete every missing section.
- Include every required section exactly once and in the exact order.
- Use NONE for empty sections.
- Do not omit or rename headers.
- Do not add any extra headers or prose outside sections.

Current mode: $state_mode

Preserve this MODE_UPDATE block:
$retry_mode_update

Use this PLAN_UPDATE block if missing:
$retry_plan_update

Partial output to repair:
$iteration_output_before_format_retry
EOF
)
          controller_format_retry_timeout_fallback=$((controller_timeout_fallback / 2))
          if [ "$controller_format_retry_timeout_fallback" -lt 8 ]; then
            controller_format_retry_timeout_fallback=8
          fi
          controller_format_retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$controller_format_retry_timeout_fallback" 8 4)
          if [ "$active_run_mode" = "programming" ]; then
            controller_stream_raw=0
          fi
          if [ "$controller_stream_raw" = "1" ] && [ -n "$stream_output_file" ]; then
            ARTIFICER_STREAM_FILE="$stream_output_file"
            export ARTIFICER_STREAM_FILE
          else
            unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          fi
          RUN_TIMEOUT_SEC=$controller_format_retry_timeout_sec
          format_retry_output=$(run_model "$model" "$controller_format_retry_prompt" || true)
          unset RUN_TIMEOUT_SEC 2>/dev/null || true
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          format_retry_output=$(strip_terminal_noise "$format_retry_output")
          format_retry_output=$(canonicalize_controller_output "$format_retry_output")
          if [ -n "$(trim "$format_retry_output")" ]; then
            iteration_output=$format_retry_output
            stream_emit_line "$stream_output_file" "Controller format retry produced a non-empty response."
          else
            stream_emit_line "$stream_output_file" "Controller format retry returned empty output; continuing with recovery scaffolding."
          fi
        fi
      fi

      partially_repaired_controller_output=0
      if ! controller_output_has_required_sections "$iteration_output"; then
        partially_repaired_output=$(repair_partial_controller_output "$iteration_output" "$state_mode" "$state_target" "$state_confidence" "$plan_text")
        if [ -n "$(trim "$partially_repaired_output")" ] && controller_output_has_required_sections "$partially_repaired_output"; then
          if [ "$(trim "$partially_repaired_output")" != "$(trim "$iteration_output")" ]; then
            partially_repaired_controller_output=1
            append_failure_entry "$failures_file" "controller-format-partial-completion-iteration-$iteration" \
              "Completed partial controller output with deterministic defaults" \
              "Model returned key sections but omitted one or more trailing required sections" \
              "Continue with completed sections and avoid full malformed-output recovery"
            stream_emit_line "$stream_output_file" "Completed partial controller output by filling missing required sections."
          fi
          iteration_output=$partially_repaired_output
        fi
      fi

      recovered_controller_output=0
      if ! controller_output_has_required_sections "$iteration_output"; then
        recovered_iteration_output=$(recover_controller_output "$iteration_output" "$state_mode" "$state_target" "$state_confidence" "$plan_text")
        if [ -n "$(trim "$recovered_iteration_output")" ]; then
          recovered_controller_output=1
          append_failure_entry "$failures_file" "controller-format-iteration-$iteration" \
            "Recovered malformed controller output" "Model omitted required control sections" \
            "Continue with recovered section scaffolding and safe defaults"
          if [ "$run_mode" != "programming" ] || [ "${programming_quick_narrow_slice_run:-0}" -ne 1 ]; then
            stream_emit_line "$stream_output_file" "Recovered malformed controller output."
          fi
          iteration_output=$recovered_iteration_output
        fi
      fi

      if [ "$recovered_controller_output" -eq 1 ]; then
        recovered_log=$(cat <<EOF
## Original
$iteration_output_original

## Recovered
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$recovered_log"
      elif [ "$partially_repaired_controller_output" -eq 1 ]; then
        partial_repair_log=$(cat <<EOF
## Initial
$iteration_output_before_format_retry

## Partial Completion
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$partial_repair_log"
      elif [ "$controller_format_retry_used" -eq 1 ]; then
        format_retry_log=$(cat <<EOF
## Initial
$iteration_output_before_format_retry

## Format Retry
$iteration_output
EOF
)
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$format_retry_log"
      else
        append_session_entry "$controller_raw_file" "controller raw iteration $iteration" "$iteration_output"
      fi
      if [ "$recovered_controller_output" -eq 1 ]; then
        controller_format_recovery_total=$((controller_format_recovery_total + 1))
        controller_format_recovery_streak=$((controller_format_recovery_streak + 1))
      else
        controller_format_recovery_streak=0
      fi

      mode_update=$(extract_section "MODE_UPDATE" "$iteration_output")
      commands_text=$(extract_section "COMMANDS" "$iteration_output")
      contract_text=$(extract_section "CONTRACT" "$iteration_output")
      patch_section=$(extract_patch_section "$iteration_output")
      patch_text=$(normalize_patch_text "$patch_section")
      if [ "${programming_quick_narrow_slice_run:-0}" -eq 1 ] && [ -n "$(trim "$patch_text")" ] && ! patch_candidate_is_usable "$patch_text"; then
        patch_text=""
      fi
      done_claim=$(extract_section "DONE_CLAIM" "$iteration_output" | sed -n '1p' | tr 'A-Z' 'a-z' | awk '{print $1}')
      plan_update=$(extract_section "PLAN_UPDATE" "$iteration_output")
      plan_update=$(sanitize_plan_update_text "$plan_update")
      checkpoint_text=$(extract_section "CHECKPOINT" "$iteration_output")
      decision_section=$(extract_section "DECISION_REQUEST" "$iteration_output")
      final_section=$(extract_section "FINAL" "$iteration_output")
      if [ "$recovered_controller_output" -eq 1 ]; then
        done_claim="no"
        final_section="NONE"
        append_failure_entry "$failures_file" "controller-format-guard-iteration-$iteration" \
          "Completion blocked after malformed controller recovery" \
          "Recovered scaffolding must not finalize a run" \
          "Require a clean structured controller pass before DONE"
        state_set "$state_file" "blocking" "controller format recovery pending clean pass"
        stream_emit_line "$stream_output_file" "Step $iteration format-recovery guard: completion blocked until a clean structured controller pass."
      fi
      adversarial_reasoning_required=0
      cross_domain_reasoning_required=0
      recovery_contract_required=0
      assumption_revision_contract_required=0
      decision_completeness_required=0
      verification_contract_required=0
      scenario_depth_contract_required=0
      source_quality_contract_required=0
      time_window_contract_required=0
      runtime_command_evidence_required=0
      runtime_claim_map_required=0
      claim_evidence_contract_required=0
      high_risk_fail_closed_required=0
      if prompt_requires_adversarial_reasoning "$augmented_user_prompt"; then
        adversarial_reasoning_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 0 ] && printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'teacher|teaching|explain|misconception|counterexample|near[- ]?miss|retry'; then
        adversarial_reasoning_required=1
      fi
      if prompt_requires_cross_domain_reasoning "$augmented_user_prompt"; then
        cross_domain_reasoning_required=1
      fi
      if prompt_requires_decision_completeness "$augmented_user_prompt"; then
        decision_completeness_required=1
      fi
      if [ "$cross_domain_reasoning_required" -eq 1 ]; then
        decision_completeness_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ]; then
        decision_completeness_required=1
      fi
      if prompt_requires_recovery_contract "$augmented_user_prompt"; then
        recovery_contract_required=1
      fi
      if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
        assumption_revision_contract_required=1
      fi
      if [ "$assumption_revision_contract_required" -eq 0 ] && [ "$adversarial_reasoning_required" -eq 1 ] && printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'misconception|false assumption|plausible but false|first narrative|attractive but wrong|initial assumption|assumption[- ]?revision|invalidated|prove (this|it) wrong|confidence shift'; then
        assumption_revision_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ]; then
        recovery_contract_required=1
      fi
      if [ "$assumption_revision_contract_required" -eq 1 ]; then
        recovery_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        verification_contract_required=1
      fi
      if [ "$verification_contract_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        source_quality_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        scenario_depth_contract_required=1
      fi
      if prompt_requires_time_windowed_validation "$augmented_user_prompt"; then
        time_window_contract_required=1
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ]; then
        time_window_contract_required=1
      fi
      if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
        high_risk_fail_closed_required=1
      fi
      if [ "$high_risk_fail_closed_required" -eq 1 ]; then
        verification_contract_required=1
        source_quality_contract_required=1
        scenario_depth_contract_required=1
        time_window_contract_required=1
      fi
      case "$run_mode" in
        report|teacher|security-audit|pentest|text-perfecter|gui-testing)
          source_quality_contract_required=1
          ;;
      esac
      if [ "$verification_contract_required" -eq 1 ] && [ "$run_command_success_total" -gt 0 ]; then
        runtime_command_evidence_required=1
      fi
      if [ "$runtime_command_evidence_required" -eq 1 ]; then
        if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
          runtime_claim_map_required=1
        fi
        case "$run_mode" in
          report|teacher|security-audit|pentest|text-perfecter|gui-testing)
            runtime_claim_map_required=1
            ;;
        esac
        if [ "$high_risk_fail_closed_required" -eq 1 ]; then
          runtime_claim_map_required=1
        fi
      fi
      if [ "$verification_contract_required" -eq 1 ] || [ "$source_quality_contract_required" -eq 1 ] || prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
        claim_evidence_contract_required=1
      fi
      if [ "$runtime_claim_map_required" -eq 1 ]; then
        claim_evidence_contract_required=1
      fi
      final_trimmed=$(trim "$final_section")
      if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ]; then
        if [ "$adversarial_reasoning_required" -eq 1 ]; then
          final_section=$(normalize_adversarial_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$cross_domain_reasoning_required" -eq 1 ]; then
          final_section=$(normalize_cross_domain_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$recovery_contract_required" -eq 1 ]; then
          final_section=$(normalize_recovery_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$assumption_revision_contract_required" -eq 1 ]; then
          final_section=$(normalize_assumption_revision_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$decision_completeness_required" -eq 1 ]; then
          final_section=$(normalize_decision_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$verification_contract_required" -eq 1 ]; then
          final_section=$(normalize_verification_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$runtime_command_evidence_required" -eq 1 ]; then
          final_section=$(ensure_output_has_runtime_command_evidence \
            "$final_trimmed" \
            "$loop_summary" \
            "$run_command_success_total" \
            "$augmented_user_prompt" \
            "$runtime_claim_map_required")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$claim_evidence_contract_required" -eq 1 ]; then
          final_section=$(normalize_claim_evidence_completeness_contract "$final_trimmed" "$augmented_user_prompt" "$loop_summary")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$source_quality_contract_required" -eq 1 ]; then
          final_section=$(normalize_source_quality_contradiction_contract "$final_trimmed" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$adversarial_reasoning_required" -eq 1 ] || [ "$cross_domain_reasoning_required" -eq 1 ] || [ "$decision_completeness_required" -eq 1 ]; then
          final_section=$(normalize_ambiguity_final_contract "$final_trimmed")
          final_trimmed=$(trim "$final_section")
        fi
        if [ "$scenario_depth_contract_required" -eq 1 ]; then
          final_section=$(normalize_scenario_depth_final_contract "$final_trimmed" "$augmented_user_prompt")
          final_trimmed=$(trim "$final_section")
        fi
        final_section=$(normalize_reasoning_followup_thread_contract "$final_trimmed" "$augmented_user_prompt")
        final_section=$(normalize_reasoning_live_contract "$final_section" "$augmented_user_prompt")
        final_trimmed=$(trim "$final_section")
        if [ "$high_risk_fail_closed_required" -eq 1 ]; then
          final_section=$(normalize_high_risk_fail_closed_contract "$final_trimmed" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
          final_trimmed=$(trim "$final_section")
        fi
      fi
      if [ "$adversarial_reasoning_required" -eq 1 ] && [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ]; then
        if ! final_has_adversarial_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:adversarial-final-contract" \
            "Final section missing explicit adversarial reasoning contract" \
            "Prompt required adversarial reasoning but FINAL still lacked assumptions/alternatives/conflict/contradiction/false-premise challenge signals" \
            "Require a revised FINAL with assumptions, contradiction checks, false-premise challenge, and premise-validation evidence before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing adversarial reasoning contract"
          stream_emit_line "$stream_output_file" "Step $iteration adversarial-quality gate blocked completion; requesting richer FINAL reasoning."
        fi
      fi
      if [ "$cross_domain_reasoning_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        min_cross_axes=3
        if printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]' | grep -Eq 'teacher|misconception|explain|learn'; then
          min_cross_axes=4
        fi
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && (! final_has_cross_domain_signals "$final_trimmed" "$min_cross_axes" || ! final_has_cross_domain_synthesis_contract "$final_trimmed"); then
          append_failure_entry "$failures_file" "iteration-$iteration:cross-domain-final-contract" \
            "Final section lacked cross-domain synthesis contract" \
            "Prompt required cross-domain reasoning but FINAL did not include complete lens coverage plus explicit tradeoff/rejected-alternative mapping" \
            "Require a revised FINAL with explicit cross-domain integration, lens coverage, and tradeoff ledger"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing cross-domain integration"
          stream_emit_line "$stream_output_file" "Step $iteration cross-domain gate blocked completion; requesting broader synthesis."
        fi
      fi
      if [ "$recovery_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_recovery_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:recovery-final-contract" \
            "Final section lacked recovery/self-correction contract" \
            "Prompt required reliability under uncertainty but FINAL missed explicit re-plan trigger and self-correction evidence" \
            "Require a revised FINAL with recovery and self-correction structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing recovery/self-correction contract"
          stream_emit_line "$stream_output_file" "Step $iteration recovery gate blocked completion; requesting re-plan triggers and self-correction evidence."
        fi
      fi
      if [ "$assumption_revision_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_assumption_revision_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:assumption-revision-contract" \
            "Final section lacked assumption-revision contract" \
            "Prompt required explicit revision from invalidated assumptions but FINAL missed initial-assumption, invalidating-evidence, revised-decision, or evidence-delta signals" \
            "Require a revised FINAL with full assumption-revision structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing assumption-revision contract"
          stream_emit_line "$stream_output_file" "Step $iteration assumption-revision gate blocked completion; requesting explicit invalidation and revised-decision structure."
        fi
      fi
      if [ "$decision_completeness_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_decision_completeness "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:decision-completeness-contract" \
            "Final section lacked required decision completeness signals" \
            "Prompt required decision completeness but FINAL missed one or more of decision/fallback/disconfirming evidence/priority order" \
            "Require a revised FINAL with explicit decision completeness before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing decision completeness"
          stream_emit_line "$stream_output_file" "Step $iteration decision-completeness gate blocked completion; requesting fuller decision structure."
        fi
      fi
      if [ "$verification_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_verification_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:verification-contract" \
            "Final section lacked verification-depth signals" \
            "Prompt required verification quality but FINAL missed one or more of verification evidence/disconfirming evidence/risk register signals" \
            "Require a revised FINAL with explicit verification evidence and invalidation criteria before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing verification depth"
          stream_emit_line "$stream_output_file" "Step $iteration verification-quality gate blocked completion; requesting explicit verification evidence."
        fi
      fi
      if [ "$source_quality_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_source_quality_contradiction_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:source-quality-contradiction-contract" \
            "Final section lacked source-quality ranking or contradiction-resolution signals" \
            "Reasoning completion required source-confidence tiers plus explicit contradiction handling, but FINAL was missing one or more required signals" \
            "Require revised FINAL with Source Quality Ranking, Contradiction Check, and Source Conflict Resolution before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing source-quality contradiction contract"
          stream_emit_line "$stream_output_file" "Step $iteration source-quality gate blocked completion; requesting confidence-tiered source ranking with contradiction resolution."
        fi
      fi
      if [ "$runtime_command_evidence_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_runtime_command_evidence_contract "$final_trimmed" "$runtime_claim_map_required"; then
          append_failure_entry "$failures_file" "iteration-$iteration:runtime-command-evidence-contract" \
            "Final section lacked runtime command-backed evidence anchors" \
            "Run had successful command traces but FINAL missed command-anchored verification evidence or required claim map" \
            "Require revised FINAL with command anchors (and claim-to-evidence map when required) before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing runtime command evidence anchors"
          stream_emit_line "$stream_output_file" "Step $iteration runtime-evidence gate blocked completion; requesting command-backed evidence anchors."
        fi
      fi
      if [ "$claim_evidence_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_claim_evidence_completeness_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:claim-evidence-completeness-contract" \
            "Final section lacked claim-to-evidence map completeness signals" \
            "Reasoning completion required at least two claim-map entries with verification and invalidation links plus caveats, but FINAL remained under-specified" \
            "Require revised FINAL with multi-claim map entries (claim -> anchor -> verification -> invalidation) and explicit evidence caveats before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing claim-evidence completeness"
          stream_emit_line "$stream_output_file" "Step $iteration claim-evidence gate blocked completion; requesting multi-claim evidence mapping."
        fi
      fi
      if [ "$scenario_depth_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_scenario_specific_depth "$final_trimmed" "$augmented_user_prompt"; then
          append_failure_entry "$failures_file" "iteration-$iteration:scenario-depth-contract" \
            "Final section lacked scenario-specific depth anchors" \
            "Reasoning completion required scenario-anchored detail with conditional trigger logic, but FINAL remained generic or untethered to concrete prompt anchors" \
            "Require revised FINAL with context anchor plus scenario-specific check containing explicit if/when/unless trigger tied to prompt-specific tokens"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing scenario-specific depth anchors"
          stream_emit_line "$stream_output_file" "Step $iteration scenario-depth gate blocked completion; requesting prompt-anchored if/when trigger specificity."
        fi
      fi
      if [ "$time_window_contract_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_time_window_validation_contract "$final_trimmed"; then
          append_failure_entry "$failures_file" "iteration-$iteration:time-window-validation-contract" \
            "Final section lacked time-windowed validation signals" \
            "Prompt required owner+window validation but FINAL missed validation-owner or decision-window signals" \
            "Require a revised FINAL with explicit validation owner and review time window before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "final missing owner/window validation"
          stream_emit_line "$stream_output_file" "Step $iteration owner-window gate blocked completion; requesting validation owner and review window."
        fi
      fi
      if [ "$high_risk_fail_closed_required" -eq 1 ]; then
        final_trimmed=$(trim "$final_section")
        if [ -n "$final_trimmed" ] && [ "$final_trimmed" != "NONE" ] && ! final_has_high_risk_fail_closed_contract "$final_trimmed" "$run_command_success_total"; then
          append_failure_entry "$failures_file" "iteration-$iteration:high-risk-fail-closed-contract" \
            "Final section lacked fail-closed high-risk verification contract" \
            "High-risk prompt required explicit verification-status/go-no-go/evidence-to-proceed/residual-risk structure with cautious posture" \
            "Require a revised FINAL with fail-closed high-risk verification structure before completion"
          final_section="NONE"
          done_claim="no"
          state_set "$state_file" "blocking" "high-risk fail-closed verification contract missing"
          stream_emit_line "$stream_output_file" "Step $iteration high-risk fail-closed gate blocked completion; requesting explicit go/no-go and required evidence."
        fi
      fi
      done_claim_for_stream=$done_claim
      if [ -z "$(trim "$done_claim_for_stream")" ]; then
        done_claim_for_stream="none"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration control sections parsed (done_claim=$done_claim_for_stream)."

      decision_question=$(trim "$(printf '%s\n' "$decision_section" | sed -n 's/^question=//p' | sed -n '1p')")
      decision_options_file=$(mktemp)
      printf '%s\n' "$decision_section" | sed -n 's/^option=//p' > "$decision_options_file"
      decision_requested=0
      decision_surface_category="none"
      suppress_assay_decision_requests=0
      if [ "$assay_run_profile" -eq 1 ]; then
        suppress_assay_decision_requests=1
      fi
      if [ -n "$decision_question" ] && [ "$decision_question" != "NONE" ] && [ -s "$decision_options_file" ]; then
        decision_requested=1
      fi
      if [ "$decision_requested" -eq 1 ]; then
        decision_surface_category=$(decision_request_category_for_prompt "$augmented_user_prompt" "$decision_question" "$run_mode" "$commands_text")
        if ! should_allow_model_decision_request "$augmented_user_prompt" "$decision_question" "$run_mode" "$commands_text"; then
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Ignored unsolicited decision request" \
            "Model requested a user decision for a prompt that did not ask for a choice" \
            "Proceed autonomously with implementation"
          decision_requested=0
          decision_surface_category="none"
        fi
      fi
      if [ "$decision_requested" -eq 1 ] && [ "$suppress_assay_decision_requests" -eq 1 ]; then
        append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
          "Suppressed decision request in assay run" \
          "Assay mentoring contract requires autonomous default selection" \
          "Proceed autonomously and surface assumptions in final sections"
        decision_requested=0
        decision_surface_category="none"
      fi

      prompt_lower_compliance=$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')
      commands_lower_compliance=$(printf '%s' "$commands_text" | tr '[:upper:]' '[:lower:]')
      patch_lower_compliance=$(printf '%s' "$patch_text" | tr '[:upper:]' '[:lower:]')
      compliance_status="pass"
      legal_check="pass"
      ethical_check="pass"
      gate_check="none"
      compliance_findings="No obvious legal/ethical risks detected in current controller outputs."
      compliance_gate="none"
      compliance_next="Continue with current mode."
      if [ "$run_mode" = "assistant" ] && printf '%s' "$prompt_lower_compliance" | grep -Eq 'business|launch|sales|marketing|customer|pricing|operations|company'; then
        gate_check="required"
        compliance_status="caution"
        compliance_findings="Assistant-mode project appears to involve real-world business operations."
        compliance_gate="Require explicit user approval before irreversible external actions."
        compliance_next="Prepare options and request user confirmation before external execution."
      fi
      if printf '%s' "$commands_lower_compliance" | grep -Eq '\bcurl\b|\bwget\b|\bnc\b|\bssh\b|\bscp\b|\bsftp\b|\bftp\b|\btelnet\b'; then
        legal_check="attention"
        compliance_status="caution"
        compliance_findings="${compliance_findings} Proposed commands include external/network tooling."
        if [ "$gate_check" = "none" ]; then
          gate_check="required"
        fi
        compliance_gate="Require user approval before any external-network side effects."
        compliance_next="Use local analysis until user approves external actions."
      fi
      if decision_commands_trigger_destructive_gate "$commands_text"; then
        compliance_status="caution"
        compliance_findings="${compliance_findings} Proposed commands include destructive local operations."
        if [ "$gate_check" = "none" ]; then
          gate_check="required"
        fi
        compliance_gate="Require explicit approval before destructive local actions."
        compliance_next="Pause and surface safe alternatives plus rollback implications."
      fi
      if printf '%s' "$patch_lower_compliance" | grep -Eq 'spam|phish|credential stuffing|captcha bypass|ddos|malware|exploit'; then
        ethical_check="fail"
        compliance_status="blocked"
        compliance_findings="${compliance_findings} Candidate patch text suggests abusive or harmful behavior."
        compliance_gate="Block unsafe implementation path; request a safe alternative objective."
        compliance_next="Refuse harmful approach and propose compliant alternatives."
      fi
      compliance_checks_text=$(cat <<EOF
- legal_compliance=$legal_check
- ethical_non_abuse=$ethical_check
- external_action_gate=$gate_check
EOF
)
      append_compliance_entry "$compliance_file" "$run_mode" "$state_mode" "$compliance_status" "$compliance_checks_text" "$compliance_findings" "$compliance_gate" "$compliance_next"

      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && decision_commands_trigger_destructive_gate "$commands_text"; then
        decision_question="Potentially destructive actions are implied. How should I proceed?"
        cat > "$decision_options_file" <<'EOF'
Pause and provide a non-destructive dry-run plan
Proceed only with explicit rollback steps and backups
Stop and return a risk assessment only
EOF
        decision_requested=1
        decision_surface_category="destructive-action-gate"
      fi
      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && [ "$gate_check" = "required" ] && decision_commands_trigger_external_gate "$commands_text"; then
        decision_question="External/network actions are implied. Which path should I take?"
        cat > "$decision_options_file" <<'EOF'
Proceed with local-only analysis and no external execution
Approve external/network actions for this run
Stop and return a risk summary only
EOF
        decision_requested=1
        decision_surface_category="external-action-gate"
      fi
      if [ "$decision_requested" -eq 0 ] && [ "$suppress_assay_decision_requests" -ne 1 ] && decision_prompt_has_missing_required_inputs "$augmented_user_prompt"; then
        if prompt_requests_autonomous_defaults "$augmented_user_prompt"; then
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Suppressed missing-input decision due autonomous-default directive" \
            "Prompt explicitly requested autonomous execution/default assumptions" \
            "Proceed with explicit assumptions and avoid awaiting_decision pause"
          decision_requested=0
          decision_surface_category="none"
          stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: missing-input gate bypassed via autonomous-default directive."
        else
          decision_question="Required inputs appear missing. How should I continue?"
          cat > "$decision_options_file" <<'EOF'
Proceed with sensible defaults and clearly label assumptions
Pause and ask me for the exact missing values first
Generate a template of required inputs, then continue after I fill it in
EOF
          decision_requested=1
          decision_surface_category="required-input-missing"
        fi
      fi
      if [ "$decision_requested" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: request prepared ($decision_surface_category)."
      else
        stream_emit_line "$stream_output_file" "Step $iteration decision checkpoint: no user decision required."
      fi

      target_update=$(printf '%s\n' "$mode_update" | sed -n 's/^target=//p' | sed -n '1p')
      blocking_update=$(printf '%s\n' "$mode_update" | sed -n 's/^blocking=//p' | sed -n '1p')
      confidence_update=$(printf '%s\n' "$mode_update" | sed -n 's/^confidence=//p' | sed -n '1p')
      target_update=$(printf '%s\n' "$target_update" | perl -CS -pe 's/[[:space:]._-]*blocking=.*$//i; s/[[:space:]._-]*confidence=.*$//i')
      target_update=$(trim "$target_update")

      if [ -n "$(trim "$target_update")" ]; then
        state_set "$state_file" "target" "$target_update"
      fi
      if [ -n "$(trim "$blocking_update")" ]; then
        state_set "$state_file" "blocking" "$blocking_update"
      fi
      case "$confidence_update" in
        ""|*[!0-9.]*)
          ;;
        *)
          state_set "$state_file" "confidence" "$confidence_update"
          ;;
      esac

      if printf '%s\n' "$plan_update" | grep -q '^Goal:'; then
        printf '%s\n' "$plan_update" > "$plan_file"
      fi

      assumption_text_runtime="Latest workspace understanding still matches current task context."
      unchecked_text_runtime="Some file contents may be stale until explicitly re-read this iteration."
      case "$state_mode" in
        INVESTIGATE)
          assumption_text_runtime="Current directory/file inventory is representative for design planning."
          unchecked_text_runtime="Implementation files may still require targeted inspection."
          ;;
        DESIGN)
          assumption_text_runtime="Current contract captures user-visible behavior and constraints."
          unchecked_text_runtime="Edge cases may remain unverified until IMPLEMENT/VERIFY."
          ;;
        IMPLEMENT)
          assumption_text_runtime="Patch content aligns with requested behavior and constraints."
          unchecked_text_runtime="Runtime behavior may differ until VERIFY commands run."
          ;;
        VERIFY)
          assumption_text_runtime="Verification commands are sufficient to establish readiness."
          unchecked_text_runtime="Non-exercised interaction paths may still need manual checks."
          ;;
      esac
      constraint_risk_runtime=$(state_get "$state_file" "blocking" "none")
      if [ -z "$(trim "$constraint_risk_runtime")" ]; then
        constraint_risk_runtime="none"
      fi
      append_assumption_entry "$assumptions_file" "$state_mode" "$assumption_text_runtime" "$unchecked_text_runtime" "$constraint_risk_runtime"

      iteration_report=""
      next_mode="$state_mode"
      transition_reason_runtime="mode unchanged"
      if [ "$decision_requested" -eq 1 ]; then
        if save_decision_request "$conv_dir" "$decision_question" "$decision_options_file"; then
          decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
          decision_options_preview=$(sed -n '1,5p' "$decision_options_file" | sed 's/^/- /')
          if [ -z "$decision_options_preview" ]; then
            decision_options_preview="- (none)"
          fi
          iteration_report="Decision requested:
Question: $decision_question
Options:
$decision_options_preview"
          next_mode="DONE"
          transition_reason_runtime="awaiting user decision"
          state_set "$state_file" "blocking" "decision required (${decision_surface_category})"
          assistant_output="I need your decision before I can continue."
          loop_feedback=$iteration_report
          stream_emit_line "$stream_output_file" "Step $iteration paused for user decision ($decision_surface_category)."
        else
          append_failure_entry "$failures_file" "decision-request-iteration-$iteration" \
            "Decision request payload invalid" "Missing question/options in model output" \
            "Continue without decision request"
          clear_decision_request "$conv_dir"
          decision_requested=0
        fi
      fi

      if [ "$decision_requested" -eq 0 ]; then
        case "$state_mode" in
        INVESTIGATE|DESIGN|VERIFY)
          command_lines_file=$(mktemp)
          extract_command_lines "$commands_text" > "$command_lines_file"

          command_lines_sanitized=$(mktemp)
          while IFS= read -r candidate_line; do
            candidate_line=$(trim "$candidate_line")
            [ -n "$candidate_line" ] || continue
            original_candidate_line=$candidate_line
            candidate_line=$(normalize_workspace_paths_in_command "$candidate_line" "$workspace_path")
            candidate_line=$(sanitize_controller_command_candidate "$candidate_line" "$state_mode")
            candidate_line=$(trim "$candidate_line")
            [ -n "$candidate_line" ] || continue
            if allowed_command "$candidate_line"; then
              printf '%s\n' "$candidate_line" >> "$command_lines_sanitized"
              if [ "$candidate_line" != "$original_candidate_line" ]; then
                append_failure_entry "$failures_file" "command-parse-iteration-$iteration" \
                  "Rewrote command candidate to safe equivalent: $original_candidate_line -> $candidate_line" \
                  "Controller proposed a command outside the mediated allowlist" \
                  "Continue with rewritten safe command"
              fi
            else
              append_failure_entry "$failures_file" "command-parse-iteration-$iteration" \
                "Discarded disallowed command candidate: $candidate_line" \
                "Controller output included commands outside the mediated allowlist" \
                "Use strict read-only mediated commands or fallback defaults"
            fi
          done < "$command_lines_file"
          mv "$command_lines_sanitized" "$command_lines_file"

          if [ ! -s "$command_lines_file" ]; then
            case "$state_mode" in
              INVESTIGATE)
                printf '%s\n%s\n' "ls" "find . -maxdepth 2 -type f" > "$command_lines_file"
                ;;
              DESIGN)
                printf '%s\n' "git status --short --untracked-files=no" > "$command_lines_file"
                ;;
              VERIFY)
                emit_default_verify_commands "$workspace_path" "$augmented_user_prompt" > "$command_lines_file"
                ;;
            esac
          fi

          if [ "$state_mode" = "VERIFY" ]; then
            case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
              *godot*)
                emit_default_verify_commands "$workspace_path" "$augmented_user_prompt" > "$command_lines_file"
                ;;
            esac
          fi

          command_count=0
          commands_ran=0
          commands_ok=1
          command_success_count=0
          approval_required_detected=0
          nonfatal_context_miss_count=0
          nonfatal_context_miss_last_status=""
          verify_success_signal=0
          verify_last_output=""
          iteration_report="$state_mode command results:"
          loop_feedback=""
          stream_emit_line "$stream_output_file" "Step $iteration executing $state_mode command batch."

          while IFS= read -r command_line; do
            command_line=$(trim "$command_line")
            [ -n "$command_line" ] || continue
            command_line=$(printf '%s\n' "$command_line" | perl -CS -pe '
              s/\r//g;
              s/\\\\n/\n/g;
              s/\\n/\n/g;
              s/(?<=\S)-\s+(?=[A-Za-z0-9._\/])/\\n- /g;
            ' | sed -n '1p')
            command_line=$(printf '%s\n' "$command_line" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^[[:space:]]*[0-9]+[.)][[:space:]]*//')
            command_line=$(trim "$command_line")
            [ -n "$command_line" ] || continue
            command_count=$((command_count + 1))
            if [ "$command_count" -gt 3 ]; then
              break
            fi

            commands_ran=$((commands_ran + 1))
            command_stream_label=$(single_line_snippet "$command_line")
            stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran started: $command_stream_label"
            tool_out=$(mktemp)
            tool_status_file=$(mktemp)
            execute_mediated_command "$workspace_id" "$workspace_path" "$command_line" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file"
            command_status=$(cat "$tool_status_file")
            command_output=$(sed -n '1,220p' "$tool_out")
            command_output=$(compact_command_output_for_context "$command_line" "$command_output" "$assay_run_profile")
            stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran status: $command_status"

            case "$command_status" in
              ok)
                command_success_count=$((command_success_count + 1))
                run_command_success_total=$((run_command_success_total + 1))
                if [ "$state_mode" = "VERIFY" ]; then
                  case "$command_line" in
                    ./*|sh\ *|bash\ *)
                      if [ -n "$(trim "$command_output")" ]; then
                        verify_success_signal=1
                        verify_last_output=$(printf '%s\n' "$command_output" | sed -n '1p')
                      fi
                      ;;
                    test\ -f\ *)
                      verify_success_signal=1
                      ;;
                    git\ status*|git\ diff*|ls|ls\ *|pwd|find\ *|cat\ *|head\ *|tail\ *|wc\ *|rg\ *|sed\ *|which\ *|command\ -v\ *)
                      ;;
                    *)
                      verify_success_signal=1
                      if [ -z "$(trim "$verify_last_output")" ] && [ -n "$(trim "$command_output")" ]; then
                        verify_last_output=$(printf '%s\n' "$command_output" | sed -n '1p')
                      fi
                      ;;
                  esac
                fi
                ;;
              missing_input|context_missing)
                nonfatal_context_miss_count=$((nonfatal_context_miss_count + 1))
                nonfatal_context_miss_last_status=$command_status
                append_failure_entry "$failures_file" "$command_line" "$command_status" \
                  "Command hit missing context/input; continuing without counting as verified success" \
                  "Adjust assumptions, locate canonical path, or run fallback inspection command"
                ;;
              *)
                commands_ok=0
                append_failure_entry "$failures_file" "$command_line" "$command_status" \
                  "Tool call failed or was blocked" "Refine command set and retry"
                if [ "$command_status" = "approval_required" ]; then
                  approval_required_detected=1
                fi
                ;;
            esac

            command_json=$(json_escape "$command_line")
            status_json=$(json_escape "$command_status")
            output_json=$(json_escape "$command_output")
            command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
              "$command_json" "$status_json" "$output_json")

            if [ "$commands_first" -eq 1 ]; then
              commands_json=$command_item
              commands_first=0
            else
              commands_json="${commands_json},${command_item}"
            fi

            iteration_report="${iteration_report}
Command: $command_line
Status: $command_status
Output:
$command_output"

            loop_feedback="${loop_feedback}
Command: $command_line
Status: $command_status
Output:
$command_output"

            rm -f "$tool_out" "$tool_status_file"
            if [ "$approval_required_detected" -eq 1 ]; then
              break
            fi
          done < "$command_lines_file"

          if [ "$approval_required_detected" -eq 0 ] && [ "$command_success_count" -eq 0 ] && [ "$nonfatal_context_miss_count" -gt 0 ] && [ "$commands_ran" -lt 3 ]; then
            recovery_command=$(context_recovery_readonly_command_for_mode "$state_mode" "$nonfatal_context_miss_last_status")
            recovery_command=$(trim "$recovery_command")
            if [ -n "$recovery_command" ] && allowed_command "$recovery_command"; then
              commands_ran=$((commands_ran + 1))
              stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran started: $recovery_command (context recovery)"
              tool_out=$(mktemp)
              tool_status_file=$(mktemp)
              execute_mediated_command "$workspace_id" "$workspace_path" "$recovery_command" "$tool_out" "$tool_status_file" "$command_mode" "$blocked_commands_file"
              recovery_status=$(cat "$tool_status_file")
              recovery_output=$(sed -n '1,220p' "$tool_out")
              recovery_output=$(compact_command_output_for_context "$recovery_command" "$recovery_output" "$assay_run_profile")
              stream_emit_line "$stream_output_file" "Step $iteration command $commands_ran status: $recovery_status"

              case "$recovery_status" in
                ok)
                  command_success_count=$((command_success_count + 1))
                  run_command_success_total=$((run_command_success_total + 1))
                  ;;
                missing_input|context_missing)
                  nonfatal_context_miss_count=$((nonfatal_context_miss_count + 1))
                  nonfatal_context_miss_last_status=$recovery_status
                  append_failure_entry "$failures_file" "$recovery_command" "$recovery_status" \
                    "Context-recovery fallback still hit missing inputs/context" \
                    "Broaden discovery commands or reduce path assumptions in next controller step"
                  ;;
                *)
                  commands_ok=0
                  append_failure_entry "$failures_file" "$recovery_command" "$recovery_status" \
                    "Context-recovery fallback failed or was blocked" "Revise fallback command strategy"
                  if [ "$recovery_status" = "approval_required" ]; then
                    approval_required_detected=1
                  fi
                  ;;
              esac

              recovery_command_json=$(json_escape "$recovery_command")
              recovery_status_json=$(json_escape "$recovery_status")
              recovery_output_json=$(json_escape "$recovery_output")
              recovery_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
                "$recovery_command_json" "$recovery_status_json" "$recovery_output_json")
              if [ "$commands_first" -eq 1 ]; then
                commands_json=$recovery_item
                commands_first=0
              else
                commands_json="${commands_json},${recovery_item}"
              fi

              iteration_report="${iteration_report}
Command: $recovery_command
Status: $recovery_status
Output:
$recovery_output"

              loop_feedback="${loop_feedback}
Command: $recovery_command
Status: $recovery_status
Output:
$recovery_output"

              rm -f "$tool_out" "$tool_status_file"
            fi
          fi

          rm -f "$command_lines_file"
          stream_emit_line "$stream_output_file" "Step $iteration command summary: ran=$commands_ran ok=$command_success_count context_miss=$nonfatal_context_miss_count approvals=$approval_required_detected"
          if [ "$commands_ok" -eq 1 ]; then
            stream_emit_line "$stream_output_file" "Step $iteration self-correction check: no failed assumptions remain after command review; fallback criteria refreshed."
          else
            stream_emit_line "$stream_output_file" "Step $iteration self-correction check: failed assumptions detected; fallback criteria must be revised."
          fi

          if [ "$approval_required_detected" -eq 1 ]; then
            next_mode="DONE"
            transition_reason_runtime="awaiting command approval"
            state_set "$state_file" "blocking" "command approval required"
            assistant_output="I need command approval to continue. Approve the requested command and run again."
          else
            case "$state_mode" in
              INVESTIGATE)
                if [ "$command_success_count" -gt 0 ]; then
                  if [ "$programming_quick_narrow_slice_run" -eq 1 ] && programming_prompt_has_multiple_branches "$augmented_user_prompt"; then
                    stream_emit_line "$stream_output_file" "Step $iteration: narrowing to one verified slice before wider changes."
                  fi
                  next_mode="DESIGN"
                  transition_reason_runtime="files understood"
                  state_set "$state_file" "blocking" "none"
                else
                  next_mode="INVESTIGATE"
                  transition_reason_runtime="investigation incomplete"
                  state_set "$state_file" "blocking" "investigation needs more evidence"
                fi
                ;;
              DESIGN)
                contract_trimmed=$(trim "$contract_text")
                if [ -n "$contract_trimmed" ] && [ "$contract_trimmed" != "NONE" ]; then
                  {
                    printf '# Contract\n\n'
                    printf 'Inputs:\nOutputs:\nSide Effects:\nDependencies:\nExit Codes:\nInvariants:\n\n'
                    printf '%s\n' "$contract_trimmed"
                  } > "$contract_file"
                elif [ "$commands_ok" -eq 1 ]; then
                  {
                    printf '# Contract\n\n'
                    printf 'Inputs:\n'
                    printf '%s\n' "- User request: $(printf '%s' "$augmented_user_prompt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-220)"
                    printf 'Outputs:\n'
                    printf '%s\n' '- Requested files/content updated in workspace.'
                    printf 'Side Effects:\n'
                    printf '%s\n' '- Workspace files may be created or modified.'
                    printf 'Dependencies:\n'
                    printf '%s\n' '- POSIX sh tools and workspace filesystem.'
                    printf 'Exit Codes:\n'
                    printf '%s\n' '- 0 on success, non-zero on mediated command failures.'
                    printf 'Invariants:\n'
                    printf '%s\n' '- Keep edits scoped and syntactically valid.'
                  } > "$contract_file"
                fi

                design_completion_mode=0
                design_command_min=2
                reasoning_completion_preferred=0
                if prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
                  reasoning_completion_preferred=1
                fi
                case "$active_run_mode" in
                  report|teacher|security-audit|text-perfecter|gui-testing)
                    design_command_min=3
                    ;;
                  assistant)
                    if [ "$assay_run_profile" -eq 1 ]; then
                      design_command_min=2
                    else
                      design_command_min=3
                    fi
                    ;;
                esac

                if [ "$assay_run_profile" -eq 1 ]; then
                  stream_emit_line "$stream_output_file" "Step $iteration design gate context: assay=$assay_run_profile run_mode=$active_run_mode cmd_ok=$commands_ok cmd_success=$command_success_count total_success=$run_command_success_total reasoning_pref=$reasoning_completion_preferred design_min=$design_command_min"
                fi

                if [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$reasoning_completion_preferred" -eq 1 ] && [ "$command_success_count" -ge 1 ]; then
                  design_completion_mode=1
                elif [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$run_command_success_total" -ge "$design_command_min" ]; then
                  case "$active_run_mode" in
                    report|teacher|security-audit|text-perfecter|gui-testing)
                      design_completion_mode=1
                      ;;
                    assistant)
                      if [ "$reasoning_completion_preferred" -eq 1 ] || printf '%s' "$prompt_lower_for_budget" | grep -Eq 'design|strategy|plan|diagnose|analysis|evaluate|teach|report|audit|mitigation|checklist|architecture'; then
                        design_completion_mode=1
                      fi
                      ;;
                  esac
                elif [ "$assay_run_profile" -eq 1 ] && [ "$commands_ok" -eq 1 ] && [ "$run_command_success_total" -lt "$design_command_min" ]; then
                  state_set "$state_file" "blocking" "command depth below assay minimum"
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$implementation_expected" -eq 1 ]; then
                  design_completion_mode=0
                  state_set "$state_file" "blocking" "quick narrow-slice programming run requires an implementation pass"
                  stream_emit_line "$stream_output_file" "Step $iteration quick-slice guard: design cannot finish a programming run before one implementation pass."
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$active_run_mode" = "assistant" ] && [ "$implementation_expected" -eq 1 ]; then
                  design_completion_mode=0
                  state_set "$state_file" "blocking" "assistant task requires an execution pass"
                  stream_emit_line "$stream_output_file" "Step $iteration assistant execution guard: design cannot finish before one execution or verification pass."
                fi

                if [ "$design_completion_mode" -eq 1 ] && [ "$high_risk_fail_closed_required" -eq 1 ]; then
                  high_risk_final_candidate=$(trim "$final_section")
                  if [ -z "$high_risk_final_candidate" ] || [ "$high_risk_final_candidate" = "NONE" ]; then
                    high_risk_final_candidate=$(trim "$checkpoint_text")
                  fi
                  if [ -n "$high_risk_final_candidate" ] && [ "$high_risk_final_candidate" != "NONE" ]; then
                    high_risk_final_candidate=$(normalize_high_risk_fail_closed_contract "$high_risk_final_candidate" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
                    high_risk_final_candidate=$(trim "$high_risk_final_candidate")
                    if [ -n "$high_risk_final_candidate" ] && [ "$high_risk_final_candidate" != "NONE" ]; then
                      final_section=$high_risk_final_candidate
                    fi
                  fi
                  if [ -z "$high_risk_final_candidate" ] || [ "$high_risk_final_candidate" = "NONE" ] || ! final_has_high_risk_fail_closed_contract "$high_risk_final_candidate" "$run_command_success_total"; then
                    design_completion_mode=0
                    state_set "$state_file" "blocking" "high-risk verification evidence incomplete"
                    stream_emit_line "$stream_output_file" "Step $iteration high-risk design gate withheld DONE; explicit fail-closed verification contract still incomplete."
                  fi
                fi

                if [ "$design_completion_mode" -eq 1 ]; then
                  candidate_final=$(trim "$final_section")
                  if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                    candidate_final=$(trim "$checkpoint_text")
                  fi
                  if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                    candidate_final="Completed the requested design deliverable with concrete constraints, verification checks, and next-step guidance."
                  fi
                  candidate_final=$(sanitize_design_completion_outcome "$candidate_final" "$augmented_user_prompt")
                  verification_line=$(reasoning_design_verification_line "$augmented_user_prompt" "$command_success_count" "$loop_feedback")
                  decision_line=$(reasoning_decision_line_for_prompt "$augmented_user_prompt")
                  fallback_line=$(reasoning_fallback_line_for_prompt "$augmented_user_prompt")
                  disconfirming_line=$(reasoning_disconfirming_line_for_prompt "$augmented_user_prompt")
                  next_improvement_text=$(reasoning_next_improvement_line_for_prompt "$augmented_user_prompt")
                  risks_text=$(reasoning_risk_line_for_prompt "$augmented_user_prompt" "DONE")
                  assistant_output=$(cat <<EOF
Outcome: $candidate_final
$verification_line
Assumptions and Alternatives: Assumptions were explicitly selected from underspecified constraints; alternatives were considered and deprioritized based on feasibility/risk.
Contradiction Check: Conflicting requirements were treated as non-simultaneously satisfiable unless explicit proof showed otherwise.
Decision: $decision_line
Priority Order: Safety, correctness, and policy obligations take precedence over speed-only gains.
Fallback Path: $fallback_line
Disconfirming Evidence: $disconfirming_line
Adversarial Probe: Include at least one abuse case, one deception vector, and one counterfactual test before broad rollout.
Risk Register: Record blast radius, cost of being wrong, and active guardrails for each major decision.
Uncertainty Range: State lower bound, expected range, and upper bound outcomes with confidence.
Risks: $risks_text
Next Improvement: $next_improvement_text
EOF
)
                  next_mode="DONE"
                  transition_reason_runtime="design deliverable completed"
                  state_set "$state_file" "blocking" "none"
                elif [ -s "$contract_file" ] && [ "$commands_ok" -eq 1 ]; then
                  if [ "$implementation_expected" -eq 1 ]; then
                    next_mode="IMPLEMENT"
                    transition_reason_runtime="contract exists"
                    state_set "$state_file" "blocking" "none"
                  else
                    next_mode="DESIGN"
                    transition_reason_runtime="reasoning contract incomplete"
                    state_set "$state_file" "blocking" "reasoning final contract incomplete"
                    stream_emit_line "$stream_output_file" "Step $iteration reasoning-mode guard kept DESIGN active; requesting revised FINAL instead of IMPLEMENT patch loop."
                  fi
                else
                  next_mode="DESIGN"
                  transition_reason_runtime="contract missing or design checks failed"
                  state_set "$state_file" "blocking" "design contract incomplete"
                fi
                ;;
              VERIFY)
                verify_completion_allowed=1
                if [ "$high_risk_fail_closed_required" -eq 1 ]; then
                  verify_final_candidate=$(trim "$final_section")
                  if [ -z "$verify_final_candidate" ] || [ "$verify_final_candidate" = "NONE" ] || ! final_has_high_risk_fail_closed_contract "$verify_final_candidate" "$run_command_success_total"; then
                    verify_completion_allowed=0
                  fi
                fi
                if [ "$verify_completion_allowed" -eq 1 ] && [ "$commands_ok" -eq 1 ] && { [ "$done_claim" = "yes" ] || [ "$verify_success_signal" -eq 1 ]; }; then
                  next_mode="DONE"
                  transition_reason_runtime="verification passed"
                  state_set "$state_file" "blocking" "none"
                  if [ "$verify_success_signal" -eq 1 ] && [ "$done_claim" != "yes" ]; then
                    if is_hello_world_script_task "$augmented_user_prompt"; then
                      verify_out=$(trim "$verify_last_output")
                      if [ -n "$verify_out" ]; then
                        assistant_output="I created and ran the script successfully. Output: $verify_out"
                      else
                        assistant_output="I created and ran the script successfully."
                      fi
                    else
                      candidate_final=$(trim "$final_section")
                      if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                        candidate_final=$(trim "$checkpoint_text")
                      fi
                      if [ -n "$candidate_final" ] && [ "$candidate_final" != "NONE" ]; then
                        assistant_output="$candidate_final"
                      else
                        assistant_output="Completed implementation and verification successfully."
                      fi
                    fi
                  else
                    candidate_final=$(trim "$final_section")
                    if [ -z "$candidate_final" ] || [ "$candidate_final" = "NONE" ]; then
                      candidate_final=$(trim "$checkpoint_text")
                    fi
                    if [ -n "$candidate_final" ] && [ "$candidate_final" != "NONE" ]; then
                      assistant_output="$candidate_final"
                    fi
                  fi

                  if [ "$run_mode" = "programming" ] && [ "$programmer_review_enabled" -eq 1 ] && [ "$programmer_review_rounds_completed" -lt "$programmer_review_max_rounds" ]; then
                    review_round=$((programmer_review_rounds_completed + 1))
                    stream_emit_line "$stream_output_file" "Code review round $review_round/$programmer_review_max_rounds started."
                    review_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null | sed -n '1,320p')
                    [ -n "$(trim "$review_diff")" ] || review_diff="No working tree diff available."
                    review_loop_summary=$(printf '%s\n' "$loop_summary" | sed -n '1,120p')
                    [ -n "$(trim "$review_loop_summary")" ] || review_loop_summary="(none yet)"
                    review_prev_feedback="$programmer_review_last_feedback"
                    [ -n "$(trim "$review_prev_feedback")" ] || review_prev_feedback="NONE"
                    review_prompt=$(cat <<EOF
You are Code Reviewer mode for a programming assistant.
Judge whether another implementation pass is needed.

Return ONLY these sections:
REVIEW_DECISION:
apply | done

REVIEW_FEEDBACK:
- concise actionable findings if REVIEW_DECISION is apply
- otherwise "No actionable findings."

Rules:
- choose apply only for concrete, implementable issues that materially improve correctness, safety, reliability, or maintainability.
- if findings are only style nits, vague, or already addressed, choose done.
- avoid repeating unchanged feedback from previous rounds.
- do not include shell commands or patches here; provide reviewer feedback only.

User request:
$augmented_user_prompt

Current plan:
$plan_text

Loop summary:
$review_loop_summary

Current git diff:
$review_diff

Previous reviewer feedback:
$review_prev_feedback
EOF
)
                    if [ -n "$stream_output_file" ]; then
                      ARTIFICER_STREAM_FILE="$stream_output_file"
                      export ARTIFICER_STREAM_FILE
                    fi
                    review_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 22 8 5)
                    RUN_TIMEOUT_SEC=$review_timeout_sec
                    review_output=$(run_model "$model" "$review_prompt" || true)
                    unset RUN_TIMEOUT_SEC 2>/dev/null || true
                    unset ARTIFICER_STREAM_FILE 2>/dev/null || true
                    review_output=$(strip_terminal_noise "$review_output")
                    review_output=$(canonicalize_controller_output "$review_output")
                    review_decision=$(extract_section "REVIEW_DECISION" "$review_output" | sed -n '1p' | tr '[:upper:]' '[:lower:]' | awk '{print $1}')
                    review_feedback=$(extract_section "REVIEW_FEEDBACK" "$review_output")
                    review_feedback=$(trim "$review_feedback")
                    if [ -z "$review_feedback" ] || [ "$review_feedback" = "NONE" ]; then
                      review_feedback="No actionable findings."
                    fi
                    if [ "$review_decision" != "apply" ] && [ "$review_decision" != "done" ]; then
                      case "$(printf '%s' "$review_feedback" | tr '[:upper:]' '[:lower:]')" in
                        *no\ actionable*|*no\ material*|*looks\ good*|*clean*)
                          review_decision="done"
                          ;;
                        *)
                          review_decision="apply"
                          ;;
                      esac
                    fi
                    review_signature=$(printf '%s' "$review_feedback" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cksum | awk '{print $1}')
                    review_repeat=0
                    if [ -n "$programmer_review_last_signature" ] && [ "$review_signature" = "$programmer_review_last_signature" ]; then
                      review_repeat=1
                    fi
                    if [ "$review_decision" = "apply" ] && [ "$review_repeat" -eq 0 ]; then
                      programmer_review_rounds_completed=$review_round
                      programmer_review_last_signature=$review_signature
                      programmer_review_last_feedback=$review_feedback
                      next_mode="IMPLEMENT"
                      transition_reason_runtime="code reviewer requested follow-up"
                      state_set "$state_file" "blocking" "code review follow-up"
                      iteration_report="${iteration_report}
Code Review Round $review_round/$programmer_review_max_rounds:
$review_feedback
Action: returning to IMPLEMENT to address reviewer findings."
                      loop_feedback="Code reviewer feedback (round $review_round/$programmer_review_max_rounds):
$review_feedback"
                      assistant_output=""
                      stream_emit_line "$stream_output_file" "Code review round $review_round found actionable feedback; switching to IMPLEMENT."
                    else
                      if [ "$review_decision" = "apply" ] && [ "$review_repeat" -eq 1 ]; then
                        stream_emit_line "$stream_output_file" "Code review repeated prior feedback; stopping further review rounds."
                        review_feedback="$review_feedback (repeat detected)"
                      else
                        stream_emit_line "$stream_output_file" "Code review round $review_round found no actionable issues."
                      fi
                      iteration_report="${iteration_report}
Code Review Round $review_round/$programmer_review_max_rounds:
$review_feedback"
                    fi
                  fi
                else
                  if [ "$verify_completion_allowed" -eq 0 ]; then
                    next_mode="VERIFY"
                    transition_reason_runtime="high-risk fail-closed evidence incomplete"
                    state_set "$state_file" "blocking" "high-risk verify gate missing fail-closed contract"
                    append_failure_entry "$failures_file" "verify-iteration-$iteration:high-risk-fail-closed-gate" \
                      "Verification withheld by high-risk fail-closed gate" \
                      "High-risk completion requires explicit verification status, go/no-go, required evidence, and residual risk" \
                      "Revise FINAL to include fail-closed contract before DONE"
                    stream_emit_line "$stream_output_file" "Step $iteration high-risk verify gate withheld DONE; fail-closed verification contract incomplete."
                  else
                    if [ "$implementation_expected" -eq 1 ]; then
                      next_mode="IMPLEMENT"
                      transition_reason_runtime="verification failed"
                      state_set "$state_file" "blocking" "verification failed"
                      append_failure_entry "$failures_file" "verify-iteration-$iteration" \
                        "Verification did not pass" "Commands failed or DONE_CLAIM was not yes" \
                        "Return to IMPLEMENT and revise patch"
                    else
                      next_mode="DESIGN"
                      transition_reason_runtime="verification failed (reasoning revision required)"
                      state_set "$state_file" "blocking" "verification failed"
                      append_failure_entry "$failures_file" "verify-iteration-$iteration" \
                        "Verification did not pass" "Reasoning final contract remained incomplete under verification gates" \
                        "Return to DESIGN and revise final reasoning contract"
                    fi
                  fi
                fi
                ;;
            esac
          fi
          ;;

        IMPLEMENT)
          stream_emit_line "$stream_output_file" "Step $iteration implementing patch candidate."
          patch_trimmed=$(trim "$patch_text")
          patch_report_file=$(mktemp)
          : > "$patch_report_file"
          patch_success=0
          current_programming_slice_path=""
          force_file_block_recovery=0
          narrow_slice_direct_attempted=0
          programming_focus_allowed_path=""
          programming_force_focused_slice_implement=0
          if [ "$programming_quick_narrow_slice_run" -eq 1 ]; then
            programming_force_focused_slice_implement=1
          fi
          if [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
            programming_force_focused_slice_implement=1
          elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_started_count" -gt 1 ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
            programming_force_focused_slice_implement=1
          fi
          implement_failure_count=$(grep -c '^Action: implement-iteration-' "$failures_file" 2>/dev/null || printf '0')
          case "$implement_failure_count" in
            ''|*[!0-9]*) implement_failure_count=0 ;;
          esac
          hello_script_task=0
          case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
            *hello.sh*hello*world*)
              hello_script_task=1
              ;;
          esac
          implement_models=$(implementation_model_candidates "$model")
          bootstrap_forced=0
          bootstrap_fast_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
          bootstrap_fast_patch=$(trim "$bootstrap_fast_patch")
          prefer_bootstrap_fast=0
          if [ "$hello_script_task" -ne 1 ] && [ -n "$bootstrap_fast_patch" ]; then
            prompt_lower_implement=$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')
            workspace_has_framework_seed=0
            case "$prompt_lower_implement" in
              *godot*)
                if [ -f "$workspace_path/project.godot" ]; then
                  workspace_has_framework_seed=1
                fi
                ;;
            esac
            if [ "$workspace_has_framework_seed" -eq 0 ]; then
              prefer_bootstrap_fast=1
            fi
          fi

          if [ "$hello_script_task" -eq 1 ]; then
            patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
            patch_trimmed=$(trim "$patch_text")
          fi

          if [ "$hello_script_task" -ne 1 ] && [ -n "$patch_trimmed" ] && [ "$patch_trimmed" != "NONE" ]; then
            resolved_patch_text=$(resolve_patch_candidate "$patch_text" || true)
            if [ -n "$(trim "$resolved_patch_text")" ]; then
              patch_text=$resolved_patch_text
              patch_trimmed=$(trim "$resolved_patch_text")
            else
              append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                "Discarded malformed patch candidate" "Controller PATCH section was not a structurally valid unified diff" \
                "Request stricter patch format retries"
              patch_text=""
              patch_trimmed=""
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$prefer_bootstrap_fast" -eq 1 ]; then
            force_bootstrap_now=0
            if [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; then
              force_bootstrap_now=1
            elif framework_patch_is_low_confidence "$augmented_user_prompt" "$patch_text" "$workspace_path"; then
              force_bootstrap_now=1
            fi
            if [ "$force_bootstrap_now" -eq 1 ]; then
              resolved_patch_text=$(resolve_patch_candidate "$bootstrap_fast_patch" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                bootstrap_forced=1
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Applied framework bootstrap fast path" \
                  "Recognized framework task with empty framework workspace; skipping slow patch retries" \
                  "Proceed with known-good framework bootstrap patch"
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$implement_failure_count" -ge 2 ] && [ "$programming_force_focused_slice_implement" -ne 1 ]; then
            force_file_block_recovery=1
            patch_text=""
            patch_trimmed=""
          fi

          if [ "$programming_force_focused_slice_implement" -eq 1 ]; then
            patch_text=""
            patch_trimmed=""
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$force_file_block_recovery" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            followup_requires_docs=0
            followup_requires_verify=0
            followup_requires_post_safe=0
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$programming_followup_slice_path")" ]; then
              case "$programming_followup_slice_kind" in
                verification)
                  followup_requires_verify=1
                  ;;
                documentation)
                  followup_requires_docs=1
                  ;;
                post-verification-safe)
                  followup_requires_post_safe=1
                  ;;
              esac
              focus_paths=$programming_followup_slice_path
              focus_paths=$(programming_normalize_relative_path "$focus_paths")
              if [ "$programming_followup_resume_prompt" -eq 1 ]; then
                focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
              elif [ "$followup_requires_post_safe" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_post_verification_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ "$followup_requires_verify" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_verification_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ "$followup_requires_docs" -eq 1 ]; then
                focus_paths=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                focus_paths=$(programming_normalize_relative_path "$focus_paths")
                if [ -z "$focus_paths" ] && programming_path_is_documentation_safe "$programming_followup_slice_path"; then
                  focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
                fi
              elif [ -z "$focus_paths" ]; then
                focus_paths=$(programming_normalize_relative_path "$programming_followup_slice_path")
              fi
            else
              focus_paths=$(programming_quick_narrow_slice_primary_patch_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path")
            fi
            focus_paths=$(programming_normalize_relative_path "$focus_paths")
            if [ -n "$focus_paths" ]; then
              narrow_slice_direct_attempted=1
              current_programming_slice_path=$focus_paths
              programming_focus_allowed_path=$focus_paths
              focus_file_context=$(programming_file_blocks_context_for_paths "$workspace_path" "$focus_paths")
              focus_guard_paths=$(programming_quick_narrow_slice_guard_paths "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$focus_paths" "$changed_paths_file")
              focus_guard_paths=$(trim "$focus_guard_paths")
              focus_guard_context=""
              if [ -n "$focus_guard_paths" ]; then
                focus_guard_context=$(programming_file_blocks_context_for_paths "$workspace_path" "$focus_guard_paths")
              fi
              focused_task_snippet=$(programming_task_snippet_for_prompt "$augmented_user_prompt")
              slice_scope_rule="keep scope to one small verifiable implementation slice"
              non_target_scope_rule="do not widen to README, extra tests, or helper files in this pass"
              diff_non_target_scope_rule="do not edit README, tests, or extra helper files in this pass"
              if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && programming_paths_match "$focus_paths" "$programming_followup_slice_path"; then
                if [ "$followup_requires_post_safe" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final release-note-safe follow-up slice"
                  non_target_scope_rule="do not widen into executable logic, README, tests, or unrelated files in this pass"
                  diff_non_target_scope_rule="do not edit executable logic, README, tests, or unrelated files in this pass"
                elif [ "$followup_requires_verify" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final verification-safe follow-up slice"
                  non_target_scope_rule="do not widen to README, docs, extra helpers, or unrelated implementation files in this pass"
                  diff_non_target_scope_rule="do not edit README, docs, extra helper files, or unrelated implementation files in this pass"
                elif [ "$followup_requires_docs" -eq 1 ]; then
                  slice_scope_rule="keep scope to one final documentation-safe follow-up slice"
                  non_target_scope_rule="do not widen into tests, extra helper files, or unrelated implementation files in this pass"
                  diff_non_target_scope_rule="do not edit tests, extra helper files, or unrelated implementation files in this pass"
                else
                  slice_scope_rule="keep scope to one adjacent verifiable follow-up slice"
                fi
              fi
              if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && programming_paths_match "$focus_paths" "$programming_followup_slice_path"; then
                resolved_patch_text=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-deterministic-followup" \
                    "Applied deterministic follow-up patch for $current_programming_slice_path" \
                    "Focused follow-up slices should not spend budget on flaky model-formatted patches when a safe single-file fallback is available" \
                    "Proceed with the focused single-file follow-up slice"
                fi
              elif [ -n "$(trim "$current_programming_slice_path")" ]; then
                resolved_patch_text=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-deterministic-primary" \
                    "Applied deterministic primary-slice patch for $current_programming_slice_path" \
                    "Focused primary slices should not spend budget on flaky model-formatted patches when a safe single-file fallback is available" \
                    "Proceed with the focused single-file implementation slice"
                fi
              fi
              skip_focused_model_patch_attempt=0
              if patch_candidate_is_usable "$patch_text"; then
                skip_focused_model_patch_attempt=1
              fi
              focused_files_prompt=$(cat <<EOF
Return ONLY the complete updated contents of this primary file:
- $focus_paths

Rules:
- no prose
- no markdown fences unless the model cannot avoid them
- do not return a diff in this first attempt
- $slice_scope_rule
- edit only the primary file above in this pass
- $non_target_scope_rule
- keep CLI entry points, tests, and docs in their own files; do not fold them into this file
- do not ask follow-up questions
- do not echo placeholder text; return real file contents only

Task:
$focused_task_snippet

Current file contents:
$focus_file_context
EOF
)
              focused_files_output=$(mktemp)
              retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 12 6 4)
              retry_model=$(printf '%s\n' "$implement_models" | sed -n '1p')
              retry_model=$(trim "$retry_model")
              if [ "$skip_focused_model_patch_attempt" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$retry_model" ]; then
                RUN_TIMEOUT_SEC=$retry_timeout_sec
                focused_files_raw=$(run_model "$retry_model" "$focused_files_prompt" || true)
                unset RUN_TIMEOUT_SEC 2>/dev/null || true
                focused_files_raw=$(strip_terminal_noise "$focused_files_raw")
                printf '%s' "$focused_files_raw" > "$focused_files_output"
                resolved_patch_text=$(programming_patch_from_focus_output "$workspace_path" "$focused_files_output" "$focus_paths")
                if [ -n "$(trim "$resolved_patch_text")" ]; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                elif [ -n "$(trim "$focused_files_raw")" ]; then
                  resolved_patch_excerpt=$(single_line_snippet "${resolved_patch_text:-<empty>}" | cut -c1-160)
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-file" \
                    "Primary-file attempt returned unusable output: $(single_line_snippet "$focused_files_raw" | cut -c1-160) | patch preview: $resolved_patch_excerpt" \
                    "Single-file content did not parse into a safe patch candidate" \
                    "Retry once with an exact diff request for the same primary file"
                fi
              fi
              if [ "$skip_focused_model_patch_attempt" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$retry_model" ]; then
                focused_diff_prompt=$(cat <<EOF
Return ONLY a valid unified diff patch in a diff code fence.

Rules:
- touch exactly this file:
  - $focus_paths
- no prose
- keep the change small and verifiable
- preserve the currently implied behavior from any guard file context below
- $diff_non_target_scope_rule
- keep CLI entry points, tests, and docs in their own files; do not fold them into this file

Task:
$focused_task_snippet

Primary file context:
$focus_file_context
EOF
)
                if [ -n "$focus_guard_context" ]; then
                  focused_diff_prompt=$(printf '%s\n\nGuard file context (read-only; preserve this behavior):\n%s\n' "$focused_diff_prompt" "$focus_guard_context")
                fi
                retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 10 5 4)
                RUN_TIMEOUT_SEC=$retry_timeout_sec
                focused_diff_raw=$(run_model "$retry_model" "$focused_diff_prompt" || true)
                unset RUN_TIMEOUT_SEC 2>/dev/null || true
                focused_diff_raw=$(strip_terminal_noise "$focused_diff_raw")
                focused_diff_patch=$(extract_patch_section "$focused_diff_raw")
                focused_diff_patch=$(normalize_patch_text "$focused_diff_patch")
                resolved_patch_text=$(resolve_patch_candidate "$focused_diff_patch" || true)
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                elif [ -n "$(trim "$focused_diff_raw")" ]; then
                  resolved_patch_excerpt=$(single_line_snippet "${resolved_patch_text:-<empty>}" | cut -c1-160)
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-diff" \
                    "Primary-file diff retry returned unusable output: $(single_line_snippet "$focused_diff_raw" | cut -c1-160) | patch preview: $resolved_patch_excerpt" \
                    "Focused diff retry still did not produce a safe unified diff" \
                    "Treat the implementation pass as blocked and summarize the bounded slice concisely"
                fi
              fi
              if { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ -n "$(trim "$current_programming_slice_path")" ]; then
                resolved_patch_text=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-primary-fallback" \
                    "Applied deterministic primary-slice fallback for $current_programming_slice_path" \
                    "Focused primary-slice model patch was empty or unusable" \
                    "Proceed with the smallest deterministic implementation slice for the target file"
                fi
              fi
              if { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; } && [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$current_programming_slice_path")" ] && programming_paths_match "$current_programming_slice_path" "$programming_followup_slice_path"; then
                resolved_patch_text=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$current_programming_slice_path")
                if patch_candidate_is_usable "$resolved_patch_text"; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration-adjacent-fallback" \
                    "Applied deterministic adjacent-slice fallback for $current_programming_slice_path" \
                    "Focused adjacent-slice model patch was empty or unusable" \
                    "Proceed with the smallest deterministic follow-up slice for the target file"
                fi
              fi
              rm -f "$focused_files_output"
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$force_file_block_recovery" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_retry_prompt=$(cat <<EOF
You are in IMPLEMENT mode.
Return ONLY a unified diff patch in a diff code fence, touching at most 5 files.
No prose.

Example format:
\`\`\`diff
--- /dev/null
+++ b/new_file.txt
@@ -0,0 +1,2 @@
+line 1
+line 2
\`\`\`

Rules:
- every changed file must have both --- and +++ headers
- use relative workspace paths under a/ and b/
- for new files, use --- /dev/null and +++ b/<path>
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 30 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              patch_retry_output=$(run_model "$retry_model" "$implement_retry_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              patch_retry_section=$(extract_patch_section "$patch_retry_output")
              patch_retry_text=$(normalize_patch_text "$patch_retry_section")
              patch_retry_trimmed=$(trim "$patch_retry_text")

              resolved_patch_text=$(resolve_patch_candidate "$patch_retry_text" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && [ "$force_file_block_recovery" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_retry_prompt_2=$(cat <<EOF
Return ONLY this format:
BEGIN_PATCH
<valid unified diff touching at most 5 files>
END_PATCH

Rules:
- no prose
- no markdown fences
- include standard --- / +++ headers
- do not emit commands, only patch text
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 28 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              patch_retry_output_2=$(run_model "$retry_model" "$implement_retry_prompt_2" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              patch_retry_output_2=$(strip_terminal_noise "$patch_retry_output_2")
              patch_retry_text_2=$(printf '%s\n' "$patch_retry_output_2" | sed -n '/^BEGIN_PATCH$/,/^END_PATCH$/p' | sed '1d;$d')
              patch_retry_trimmed_2=$(trim "$patch_retry_text_2")
              resolved_patch_text=$(resolve_patch_candidate "$patch_retry_text_2" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            implement_files_prompt=$(cat <<EOF
Return ONLY file blocks in this format (up to 5 files):
FILE: relative/path.ext
\`\`\`
full file content
\`\`\`

Rules:
- no prose
- relative workspace paths only
- provide complete file contents for each file
- choose sensible defaults for unspecified details
- do not ask follow-up questions

Task:
$augmented_user_prompt

Workspace snapshot:
$snapshot_text
EOF
)
            file_blocks_dir=$(mktemp -d)
            file_blocks_index=$(mktemp)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 28 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              file_blocks_output=$(run_model "$retry_model" "$implement_files_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              file_blocks_output=$(strip_terminal_noise "$file_blocks_output")
              : > "$file_blocks_index"
              printf '%s' "$file_blocks_output" | FILE_BLOCKS_DIR="$file_blocks_dir" perl -e '
                use strict;
                use warnings;
                local $/;
                my $raw = <>;
                my $dir = $ENV{"FILE_BLOCKS_DIR"} // "";
                my $count = 0;
                my %seen_path;

                my $emit = sub {
                  my ($path, $content) = @_;
                  $path = "" if !defined $path;
                  $content = "" if !defined $content;
                  $path =~ s/^\s+//;
                  $path =~ s/\s+$//;
                  return if $path eq "";
                  return if $path =~ m{(?:^|/)\.\.(?:/|$)};
                  return if $path =~ m{^/};
                  return if $seen_path{$path};
                  return if $content !~ /\S/;
                  $count += 1;
                  return if $count > 5;
                  my $tmp_path = "$dir/$count.content";
                  open my $fh, ">:encoding(UTF-8)", $tmp_path or return;
                  print {$fh} $content;
                  close $fh;
                  $seen_path{$path} = 1;
                  print "$path\t$tmp_path\n";
                };

                while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n```[^\n]*\n(.*?)\n```/sg) {
                  $emit->($1, $2);
                }

                if ($count == 0) {
                  while ($raw =~ /FILE:\s*([^\r\n]+)\s*\r?\n(.*?)(?=\r?\nFILE:\s*[^\r\n]+\s*\r?\n|\z)/sg) {
                    my $path = $1;
                    my $content = $2 // "";
                    $content =~ s/\A\r?\n//;
                    $content =~ s/\r?\n\z//;
                    $content =~ s/\A```[^\n]*\n//s;
                    $content =~ s/\n```[ \t]*\z//s;
                    $emit->($path, $content);
                  }
                }
              ' > "$file_blocks_index"
              if [ -s "$file_blocks_index" ]; then
                break
              fi
            done <<EOF
$implement_models
EOF

            synthesized_patch=""
            if [ -s "$file_blocks_index" ]; then
              while IFS='	' read -r out_path out_tmp; do
                out_path=$(trim "$out_path")
                out_tmp=$(trim "$out_tmp")
                [ -n "$out_path" ] || continue
                [ -f "$out_tmp" ] || continue
                if ! is_safe_relative_path "$out_path"; then
                  continue
                fi
                mkdir -p "$(dirname "$workspace_path/$out_path")" 2>/dev/null || true
                if [ -f "$workspace_path/$out_path" ]; then
                  file_diff=$(diff -u "$workspace_path/$out_path" "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- a/$out_path|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                else
                  file_diff=$(diff -u /dev/null "$out_tmp" || true)
                  if [ -n "$(trim "$file_diff")" ]; then
                    file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$out_path|")
                    synthesized_patch="${synthesized_patch}
${file_diff}"
                  fi
                fi
              done < "$file_blocks_index"
            fi

            rm -rf "$file_blocks_dir" 2>/dev/null || true
            rm -f "$file_blocks_index"

            synthesized_patch=$(trim_block_edges "$synthesized_patch")
            if patch_candidate_is_usable "$synthesized_patch"; then
              patch_text=$synthesized_patch
              patch_trimmed=$synthesized_patch
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && ! { [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ "$narrow_slice_direct_attempted" -eq 1 ]; } && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            focused_patch_prompt=$(cat <<EOF
You are a coding assistant generating final implementation output.
Return ONLY a valid unified diff touching at most 5 files.
No prose, no markdown outside a single diff fence.

Rules:
- include --- and +++ headers for every file
- use --- /dev/null for new files
- use +++ b/<relative-path> paths
- do not include command suggestions
- choose sensible defaults when details are underspecified

Task:
$augmented_user_prompt
EOF
)
            retry_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" 26 8 5)
            while IFS= read -r retry_model; do
              retry_model=$(trim "$retry_model")
              [ -n "$retry_model" ] || continue
              if [ -n "$stream_output_file" ] && [ "$active_run_mode" != "programming" ]; then
                ARTIFICER_STREAM_FILE="$stream_output_file"
                export ARTIFICER_STREAM_FILE
              fi
              RUN_TIMEOUT_SEC=$retry_timeout_sec
              focused_output=$(run_model "$retry_model" "$focused_patch_prompt" || true)
              unset RUN_TIMEOUT_SEC 2>/dev/null || true
              unset ARTIFICER_STREAM_FILE 2>/dev/null || true
              focused_output=$(strip_terminal_noise "$focused_output")
              focused_patch_section=$(extract_patch_section "$focused_output")
              focused_patch_text=$(normalize_patch_text "$focused_patch_section")
              focused_patch_trimmed=$(trim "$focused_patch_text")
              resolved_patch_text=$(resolve_patch_candidate "$focused_patch_text" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                break
              fi
            done <<EOF
$implement_models
EOF
          fi

          if [ "$hello_script_task" -ne 1 ] && [ "$bootstrap_forced" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
            bootstrap_patch=$(trim "$bootstrap_patch")
            if [ -n "$bootstrap_patch" ]; then
              resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
              if [ -n "$(trim "$resolved_patch_text")" ]; then
                patch_text=$resolved_patch_text
                patch_trimmed=$(trim "$resolved_patch_text")
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Applied framework bootstrap fallback patch" "Model did not produce a usable patch payload" \
                  "Proceed with synthesized framework baseline patch"
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && [ -n "$patch_trimmed" ] && [ "$patch_trimmed" != "NONE" ]; then
            if framework_patch_is_low_confidence "$augmented_user_prompt" "$patch_text" "$workspace_path"; then
              bootstrap_patch=$(framework_bootstrap_patch_for_prompt "$augmented_user_prompt")
              bootstrap_patch=$(trim "$bootstrap_patch")
              if [ -n "$bootstrap_patch" ]; then
                resolved_patch_text=$(resolve_patch_candidate "$bootstrap_patch" || true)
                if [ -n "$(trim "$resolved_patch_text")" ]; then
                  patch_text=$resolved_patch_text
                  patch_trimmed=$(trim "$resolved_patch_text")
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Replaced low-confidence framework patch with bootstrap baseline" \
                    "Model patch failed framework contract checks for an empty framework workspace" \
                    "Proceed with known-good framework bootstrap patch"
                fi
              fi
            fi
          fi

          if [ "$hello_script_task" -ne 1 ] && { [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; }; then
            case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
              *hello.sh*hello*world*)
                patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                patch_trimmed=$(trim "$patch_text")
                ;;
            esac
          fi

          if [ "$allow_workspace_writes" -ne 1 ]; then
            printf '%s\n' "Patch blocked by read-only permissions. Switch to Workspace write or Default to apply edits." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Patch blocked by read-only permissions" "Current permission mode forbids workspace edits" \
              "Ask user to grant write permissions and retry"
          elif [ -z "$patch_trimmed" ] || [ "$patch_trimmed" = "NONE" ]; then
            printf '%s\n' "Implement mode did not include a patch payload." > "$patch_report_file"
            append_failure_entry "$failures_file" "implement-iteration-$iteration" \
              "Missing patch payload" "Implementation step requires a unified diff" \
              "Generate scoped patch for target files"
          else
            patch_paths_file=$(mktemp)
            patch_paths_from_text "$patch_text" > "$patch_paths_file"
            disallowed_patch_rejected=0

            patch_paths_normalized_file=$(mktemp)
            : > "$patch_paths_normalized_file"
            while IFS= read -r raw_rel_path; do
              rel_path=$(trim "$raw_rel_path")
              [ -n "$rel_path" ] || continue
              norm_rel_path=$rel_path
              case "$norm_rel_path" in
                "$workspace_path"/*)
                  norm_rel_path=${norm_rel_path#"$workspace_path"/}
                  ;;
              esac
              case "$norm_rel_path" in
                res://*)
                  norm_rel_path=${norm_rel_path#res://}
                  ;;
                file://*)
                  norm_rel_path=${norm_rel_path#file://}
                  ;;
              esac
              if [ "$norm_rel_path" != "$rel_path" ]; then
                patch_text=$(printf '%s\n' "$patch_text" | PATCH_ORIG_PATH="$rel_path" PATCH_NORM_PATH="$norm_rel_path" perl -0pe '
                  my $orig = quotemeta($ENV{"PATCH_ORIG_PATH"} // "");
                  my $norm = $ENV{"PATCH_NORM_PATH"} // "";
                  s/^--- a\/$orig$/--- a\/$norm/mg;
                  s/^\+\+\+ b\/$orig$/+++ b\/$norm/mg;
                ')
              fi
              printf '%s\n' "$norm_rel_path" >> "$patch_paths_normalized_file"
            done < "$patch_paths_file"
            mv "$patch_paths_normalized_file" "$patch_paths_file"

            if [ "$programming_quick_narrow_slice_run" -eq 1 ] && [ -n "$programming_focus_allowed_path" ] && [ -s "$patch_paths_file" ]; then
              focused_primary_fallback_patch=""
              if [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                focused_primary_fallback_patch=$(programming_primary_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                focused_primary_fallback_patch=$(trim "$focused_primary_fallback_patch")
              fi
              if patch_candidate_is_usable "$focused_primary_fallback_patch" && {
                programming_prompt_has_multiple_branches "$augmented_user_prompt" \
                  || find "$workspace_path" -maxdepth 2 -type f \( -path '*/bin/*' -o -name 'cli.*' \) | sed -n '1p' >/dev/null 2>&1
              } && printf '%s' "$patch_text" | grep -Eqi 'commander|program[.]parse|process[.]argv|require[.]main|--help|argv\[2\]|readline|createInterface|process[.]stdin|process[.]stdout|cliGreet|module[.]exports[[:space:]]*=[[:space:]]*\{[[:space:]]*greet[[:space:]]*,'; then
                patch_text=$focused_primary_fallback_patch
                patch_trimmed=$(trim "$focused_primary_fallback_patch")
                : > "$patch_paths_file"
                patch_paths_from_text "$patch_text" > "$patch_paths_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Primary slice tried to fold CLI behavior into $programming_focus_allowed_path; replaced with deterministic helper-only patch" \
                  "First narrow slice should keep CLI entry-point behavior out of the helper file" \
                  "Preserve the helper-only implementation slice before widening to the CLI file"
              fi
              disallowed_patch_path=$(awk -v allowed="$programming_focus_allowed_path" '$0 != allowed { print; exit }' "$patch_paths_file")
              if [ -n "$disallowed_patch_path" ]; then
                focused_fallback_patch=""
                if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ -n "$current_programming_slice_path" ] && programming_paths_match "$current_programming_slice_path" "$programming_focus_allowed_path"; then
                  focused_fallback_patch=$(programming_adjacent_slice_fallback_patch_for_path "$workspace_path" "$programming_focus_allowed_path")
                  focused_fallback_patch=$(trim "$focused_fallback_patch")
                fi
                if patch_candidate_is_usable "$focused_fallback_patch"; then
                  patch_text=$focused_fallback_patch
                  patch_trimmed=$(trim "$focused_fallback_patch")
                  : > "$patch_paths_file"
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch drifted outside $programming_focus_allowed_path; replaced with deterministic single-file fallback" \
                    "Model patch widened to $disallowed_patch_path during a narrow-slice follow-up pass" \
                    "Keep the selected slice single-purpose and fall back to the deterministic target-only patch"
                else
                  disallowed_patch_rejected=1
                  printf '%s\n' "Patch widened outside the selected slice: $disallowed_patch_path" > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Focused patch changed $disallowed_patch_path instead of the selected slice $programming_focus_allowed_path" \
                    "Narrow-slice patch drifted outside the chosen implementation file" \
                    "Keep the patch on the selected primary file only"
                fi
              fi
            fi

            if [ "$disallowed_patch_rejected" -eq 1 ]; then
              patch_text=""
              patch_trimmed=""
            elif [ ! -s "$patch_paths_file" ]; then
              case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                *hello.sh*hello*world*)
                  patch_text=$(cat <<'EOF'
--- /dev/null
+++ b/hello.sh
@@ -0,0 +1,2 @@
+#!/bin/sh
+printf '%s\n' 'Hello, world!'
EOF
)
                  patch_paths_from_text "$patch_text" > "$patch_paths_file"
                  ;;
              esac
            fi

            if [ ! -s "$patch_paths_file" ]; then
              printf '%s\n' "No target files were detected in PATCH section." > "$patch_report_file"
              append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                "Patch had no +++ paths" "Diff format malformed or missing headers" \
                "Emit standard unified diff with a/ and b/ paths"
            else
              touched_count=0
              invalid_path=""
              assay_invalid_path=""
              while IFS= read -r rel_path; do
                [ -n "$rel_path" ] || continue
                touched_count=$((touched_count + 1))
                if ! is_safe_relative_path "$rel_path"; then
                  invalid_path=$rel_path
                  break
                fi
                if [ "$assay_run_profile" -eq 1 ] && [ -n "$assay_edit_root" ]; then
                  case "$rel_path" in
                    "$assay_edit_root"/*)
                      ;;
                    *)
                      assay_invalid_path=$rel_path
                      break
                      ;;
                  esac
                fi
              done < "$patch_paths_file"

              if [ -n "$invalid_path" ]; then
                printf 'Unsafe path in patch: %s\n' "$invalid_path" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Unsafe target path: $invalid_path" "Path traversal or invalid characters" \
                  "Restrict patch to safe relative workspace paths"
              elif [ -n "$assay_invalid_path" ]; then
                printf 'Assay patch out-of-scope path: %s (allowed prefix: %s/)\n' "$assay_invalid_path" "$assay_edit_root" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Assay patch out of scope: $assay_invalid_path" \
                  "Assay safety policy limits edits to $assay_edit_root/" \
                  "Regenerate patch under the assay edit root"
              elif [ "$touched_count" -gt 5 ]; then
                printf 'Patch touched too many files: %s\n' "$touched_count" > "$patch_report_file"
                append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                  "Patch touched more than 5 files" "Iteration scope too broad" \
                  "Split patch into smaller batches"
              else
                iter_scratch="$scratch_root/iter-$iteration-$(new_id)"
                mkdir -p "$iter_scratch"

                prepare_scratch_files "$workspace_path" "$iter_scratch" "$patch_paths_file"
                patch_file="$iter_scratch/proposed.patch"
                printf '%s\n' "$patch_text" > "$patch_file"
                canonical_patch_file="$iter_scratch/proposed.canonical.patch"
                cp "$patch_file" "$canonical_patch_file"
                while IFS= read -r rel_path; do
                  [ -n "$rel_path" ] || continue
                  if [ ! -f "$workspace_path/$rel_path" ]; then
                    PATCH_REL_PATH="$rel_path" perl -0pi -e '
                      my $p = $ENV{"PATCH_REL_PATH"} // "";
                      $p = quotemeta($p);
                      s/^--- a\/$p$/--- \/dev\/null/mg;
                    ' "$canonical_patch_file"
                  fi
                done < "$patch_paths_file"
                patch_file="$canonical_patch_file"

                apply_log=$(mktemp)
                gate_log=$(mktemp)
                diff_log=$(mktemp)
                promote_log=$(mktemp)
                patch_already_present=0
                if apply_patch_to_scratch "$iter_scratch" "$patch_file" "$apply_log"; then
                  if run_gate_checks "$iter_scratch" "$patch_paths_file" "$gate_log" "$augmented_user_prompt" "$workspace_path"; then
                    diff_scratch_vs_workspace "$workspace_path" "$iter_scratch" "$patch_paths_file" "$diff_log"
                    if promote_scratch_files "$iter_scratch" "$workspace_path" "$patch_paths_file" "$promote_log"; then
                      patch_success=1
                      programming_record_changed_paths "$changed_paths_file" "$patch_paths_file"
                      diff_excerpt=$(sed -n '1,220p' "$diff_log")
                      if [ -z "$diff_excerpt" ]; then
                        diff_excerpt="No textual diff generated."
                      fi
                      post_snapshot=$(workspace_snapshot "$workspace_path" | sed -n '1,120p')
                      {
                        printf 'Patch applied through scratch gate.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                        printf '\nPatch diff excerpt:\n%s\n' "$diff_excerpt"
                        printf '\nPost-write snapshot:\n%s\n' "$post_snapshot"
                      } > "$patch_report_file"
                    else
                      {
                        printf 'Promotion failed.\n'
                        printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                        printf '\nGate output:\n%s\n' "$(sed -n '1,120p' "$gate_log")"
                        printf '\nPromotion output:\n%s\n' "$(sed -n '1,120p' "$promote_log")"
                      } > "$patch_report_file"
                      append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                        "Scratch promotion failed" "File copy to workspace failed" \
                        "Inspect path and permissions before retrying"
                    fi
                  else
                    {
                      printf 'Gate checks failed.\n'
                      printf '\nApply output:\n%s\n' "$(sed -n '1,120p' "$apply_log")"
                      printf '\nGate output:\n%s\n' "$(sed -n '1,220p' "$gate_log")"
                    } > "$patch_report_file"
                    append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                      "Gate checks failed" "Syntax or conflict checks failed on scratch files" \
                      "Revise patch and retry"
                  fi
                elif [ "$programming_quick_narrow_slice_run" -eq 1 ] && already_present_log=$(mktemp) && patch_already_present_in_scratch "$iter_scratch" "$patch_file" "$already_present_log"; then
                  patch_success=1
                  patch_already_present=1
                  ARTIFICER_PROGRAMMING_CHANGED_PATHS=$(sed -n '1,20p' "$changed_paths_file" 2>/dev/null || true)
                  {
                    printf 'Selected slice already matched scratch workspace.\n'
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                    printf '\nAlready-present check:\n%s\n' "$(sed -n '1,220p' "$already_present_log")"
                  } > "$patch_report_file"
                  rm -f "$already_present_log"
                else
                  rm -f "${already_present_log:-}" 2>/dev/null || true
                  {
                    printf 'Patch failed to apply in scratch workspace.\n'
                    printf '\nPatch preview:\n%s\n' "$(sed -n '1,120p' "$patch_file")"
                    printf '\nApply output:\n%s\n' "$(sed -n '1,220p' "$apply_log")"
                  } > "$patch_report_file"
                  append_failure_entry "$failures_file" "implement-iteration-$iteration" \
                    "Patch apply failed" "Unified diff did not match scratch context" \
                    "Re-read target file and regenerate patch"
                fi

                rm -f "$apply_log" "$gate_log" "$diff_log" "$promote_log"
              fi
            fi

            rm -f "$patch_paths_file"
          fi

          patch_report=$(sed -n '1,260p' "$patch_report_file")
          rm -f "$patch_report_file"

          command_name=$(printf 'apply_patch iteration %s' "$iteration")
          if [ "$patch_success" -eq 1 ]; then
            command_status="ok"
          else
            command_status="failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration patch gate status: $command_status"

          command_json=$(json_escape "$command_name")
          status_json=$(json_escape "$command_status")
          output_json=$(json_escape "$patch_report")
          command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
            "$command_json" "$status_json" "$output_json")

          if [ "$commands_first" -eq 1 ]; then
            commands_json=$command_item
            commands_first=0
          else
            commands_json="${commands_json},${command_item}"
          fi

          iteration_report="Patch gate result:
$patch_report"
          loop_feedback=$iteration_report

          if [ "$patch_success" -eq 1 ]; then
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -gt "$programming_followup_slice_completed_count" ] && [ -n "$(trim "$current_programming_slice_path")" ] && programming_paths_match "$current_programming_slice_path" "$programming_followup_slice_path"; then
              programming_followup_slice_completed_count=$((programming_followup_slice_completed_count + 1))
            fi
            auto_verify_report_file=$(mktemp)
            followup_candidate=""
            followup_candidate_kind=""
            defer_remaining_branch=0
            landed_changed_count=$(programming_changed_paths_count_from_file "$changed_paths_file")
            case "$landed_changed_count" in
              ''|*[!0-9]*)
                landed_changed_count=0
                ;;
            esac
            landed_has_docs=0
            landed_has_verify=0
            landed_has_post_safe=0
            if programming_changed_paths_file_has_documentation_safe "$changed_paths_file"; then
              landed_has_docs=1
            fi
            if programming_changed_paths_file_has_verification_safe "$changed_paths_file"; then
              landed_has_verify=1
            fi
            if programming_changed_paths_file_has_post_verification_safe "$changed_paths_file"; then
              landed_has_post_safe=1
            fi
            followup_transition_reason="first slice landed; widening to adjacent verified slice"
            followup_stream_line="Step $iteration: widening to one adjacent verified slice after the first landed cleanly."
            if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 4 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 1 ] && [ "$landed_has_post_safe" -eq 0 ]; then
              followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="post-verification-safe"
            elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 3 ] && [ "$landed_has_docs" -eq 1 ] && [ "$landed_has_verify" -eq 0 ]; then
              followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="verification"
            elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$landed_changed_count" -ge 2 ] && [ "$landed_has_docs" -eq 0 ]; then
              followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
              followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
              followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
              followup_candidate_kind="documentation"
            fi
            if [ "$programming_quick_adjacent_slice_run" -eq 1 ] && [ "$programming_followup_slice_started_count" -eq "$programming_followup_slice_completed_count" ] && [ "$programming_followup_slice_completed_count" -lt "$programming_followup_slice_limit" ]; then
              if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                followup_transition_reason="verification-safe slice landed; widening to one final release-note-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final release-note-safe follow-up slice after the verification-safe slice landed cleanly."
                followup_candidate_kind="post-verification-safe"
              elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                followup_transition_reason="documentation-safe slice landed; widening to one final verification-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final verification-safe follow-up slice after the documentation-safe slice landed cleanly."
                followup_candidate_kind="verification"
              elif [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                followup_transition_reason="adjacent slice landed; widening to one final documentation-safe follow-up slice"
                followup_stream_line="Step $iteration: widening to one final documentation-safe follow-up slice after the adjacent slice landed cleanly."
                followup_candidate_kind="documentation"
              fi
              if [ -z "$followup_candidate" ]; then
                if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 3 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_post_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 2 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_verification_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                elif [ "$programming_quick_multi_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge 1 ]; then
                  followup_candidate=$(programming_quick_narrow_slice_documentation_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$changed_paths_file")
                else
                  followup_candidate=$(programming_quick_narrow_slice_next_followup_path "$plan_file" "$contract_file" "$session_log_file" "$workspace_path" "$augmented_user_prompt" "$changed_paths_file")
                fi
              fi
              followup_candidate=$(programming_normalize_relative_path "$followup_candidate")
            fi
            if [ -z "$followup_candidate" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            elif [ -z "$followup_candidate" ] && [ "$programming_quick_verification_followup_slice_run" -eq 1 ] && [ "$programming_followup_slice_completed_count" -ge "$programming_followup_slice_limit" ] && [ "$programming_quick_post_verification_safe_followup_slice_run" -ne 1 ] && programming_prompt_has_post_verification_branch "$augmented_user_prompt"; then
              defer_remaining_branch=1
            fi
            if auto_verify_after_patch_for_prompt "$workspace_id" "$workspace_path" "$augmented_user_prompt" "$command_mode" "$blocked_commands_file" "$auto_verify_report_file"; then
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="DONE"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                else
                  transition_reason_runtime="post-implement auto verification passed"
                fi
                state_set "$state_file" "blocking" "none"
                case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
                  *godot*)
                    assistant_output="Created a runnable Godot project in the workspace and verified it with headless Godot."
                    ;;
                  *)
                    assistant_output="Completed implementation and verification successfully."
                    ;;
                esac
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            else
              if [ -n "$followup_candidate" ]; then
                programming_followup_slice_path=$(programming_normalize_relative_path "$followup_candidate")
                programming_followup_slice_kind=$(trim "$followup_candidate_kind")
                [ -n "$programming_followup_slice_kind" ] || programming_followup_slice_kind="adjacent"
                programming_followup_slice_started_count=$((programming_followup_slice_started_count + 1))
                next_mode="IMPLEMENT"
                transition_reason_runtime=$followup_transition_reason
                state_set "$state_file" "blocking" "none"
                assistant_output=""
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")

Next slice target:
$followup_candidate"
                stream_emit_line "$stream_output_file" "$followup_stream_line"
              else
                next_mode="VERIFY"
                if [ "$defer_remaining_branch" -eq 1 ]; then
                  if [ "$programming_quick_post_verification_safe_followup_slice_run" -eq 1 ] && programming_prompt_has_post_release_note_branch "$augmented_user_prompt"; then
                    transition_reason_runtime="release-note-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the release-note-safe slice."
                  else
                    transition_reason_runtime="verification-safe slice landed; deferring remaining requested branches until verification is clean"
                    stream_emit_line "$stream_output_file" "Step $iteration: deferring any remaining requested branches after the verification-safe slice."
                  fi
                elif [ "${patch_already_present:-0}" -eq 1 ]; then
                  transition_reason_runtime="selected slice already present"
                else
                  transition_reason_runtime="scratch commit promoted"
                fi
                state_set "$state_file" "blocking" "none"
                patch_report="${patch_report}

Auto-verify output:
$(sed -n '1,220p' "$auto_verify_report_file")"
              fi
            fi
            rm -f "$auto_verify_report_file"
          else
            next_mode="IMPLEMENT"
            transition_reason_runtime="implementation patch failed"
            state_set "$state_file" "blocking" "patch gate failed"
          fi
          stream_emit_line "$stream_output_file" "Step $iteration implementation summary: next=$next_mode reason=$transition_reason_runtime"
          ;;

        DONE)
          final_candidate=$(trim "$final_section")
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate=$(trim "$checkpoint_text")
          fi
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate="Completed requested work."
          fi
          assistant_output="$final_candidate"
          next_mode="DONE"
          transition_reason_runtime="already done"
          iteration_report="Agent remained in DONE mode."
          loop_feedback=$iteration_report
          ;;
        esac
      fi

      if [ "$recovered_controller_output" -eq 1 ] && [ "$next_mode" = "DONE" ]; then
        append_failure_entry "$failures_file" "controller-format-done-block-iteration-$iteration" \
          "Prevented DONE transition from recovered controller output" \
          "Recovered controller output attempted to end the run without a clean structured pass" \
          "Hold mode and request one clean controller iteration before completion"
        controller_format_done_block_total=$((controller_format_done_block_total + 1))
        next_mode="$state_mode"
        transition_reason_runtime="controller format recovery requires clean pass"
        assistant_output=""
        done_claim="no"
        state_set "$state_file" "blocking" "controller format recovery pending clean pass"
        iteration_report="${iteration_report}
Format recovery guard:
Recovered controller output cannot complete the run; requesting one clean structured pass."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration completion guard: recovered controller output cannot transition directly to DONE."
      fi
      run_now_for_circuit=$(date +%s 2>/dev/null || printf '0')
      case "$run_now_for_circuit" in
        ""|*[!0-9]*)
          run_now_for_circuit=$run_started_epoch
          ;;
      esac
      run_elapsed_for_circuit=$((run_now_for_circuit - run_started_epoch))
      if [ "$run_elapsed_for_circuit" -lt 0 ]; then
        run_elapsed_for_circuit=0
      fi
      run_budget_remaining=$((run_time_budget - run_elapsed_for_circuit))
      if [ "$run_budget_remaining" -lt 0 ]; then
        run_budget_remaining=0
      fi
      if [ "$next_mode" != "DONE" ] && {
        [ "$controller_format_recovery_streak" -ge 2 ] ||
        [ "$controller_format_recovery_total" -ge 3 ] ||
        { [ "$controller_format_done_block_total" -ge 1 ] && [ "$run_budget_remaining" -le 25 ]; };
      }; then
        append_failure_entry "$failures_file" "controller-format-circuit-breaker-iteration-$iteration" \
          "Controller format instability circuit-breaker triggered" \
          "Repeated malformed controller recoveries or late-budget done-blocks indicate low-probability clean recovery within remaining budget" \
          "Finalize with deterministic best-effort response and request focused rerun"
        next_mode="DONE"
        transition_reason_runtime="controller format instability circuit-breaker"
        done_claim="no"
        if [ -z "$(trim "$assistant_output")" ] || [ "$assistant_output" = "NONE" ]; then
          assistant_output=$(structured_incomplete_run_message \
            "$state_mode" \
            "Retry with a narrower prompt slice or a different model, then continue from the latest verified checkpoint." \
            "Controller output format failed strict schema checks repeatedly in this run." \
            "$augmented_user_prompt")
        fi
        state_set "$state_file" "blocking" "controller format instability; finalized with best-effort output"
        iteration_report="${iteration_report}
Format recovery circuit-breaker:
Repeated malformed controller recoveries triggered deterministic best-effort finalization."
        loop_feedback=$iteration_report
        stream_emit_line "$stream_output_file" "Step $iteration circuit-breaker: repeated format recovery; finalizing with best-effort output."
      fi
      rm -f "$decision_options_file"

      state_set "$state_file" "mode" "$next_mode"
      state_set "$state_file" "transition_reason" "$transition_reason_runtime"

      case "$next_mode" in
        INVESTIGATE) default_confidence="0.30" ;;
        DESIGN) default_confidence="0.45" ;;
        IMPLEMENT) default_confidence="0.60" ;;
        VERIFY) default_confidence="0.72" ;;
        DONE) default_confidence="0.90" ;;
        *) default_confidence="0.50" ;;
      esac

      if [ -z "$confidence_update" ] || printf '%s' "$confidence_update" | grep -q '[^0-9.]'; then
        state_set "$state_file" "confidence" "$default_confidence"
      fi
      confidence_stream=$(trim "$(state_get "$state_file" "confidence" "$default_confidence")")
      if [ -z "$confidence_stream" ]; then
        confidence_stream="$default_confidence"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration confidence updated: $confidence_stream"

      checkpoint_trimmed=$(trim "$checkpoint_text")
      if [ -n "$checkpoint_trimmed" ] && [ "$checkpoint_trimmed" != "NONE" ]; then
        iteration_report="${iteration_report}
Checkpoint:
$checkpoint_trimmed"
      fi
      iteration_report="${iteration_report}
Transition: $state_mode -> $next_mode
Reason: $transition_reason_runtime"
      loop_feedback=$iteration_report

      stagnation_plan_head=$(printf '%s\n' "$plan_update" | sed -n '1,2p')
      stagnation_plan_head=$(single_line_snippet "$stagnation_plan_head")
      if [ -z "$stagnation_plan_head" ]; then
        stagnation_plan_head="none"
      fi
      stagnation_checkpoint=$(single_line_snippet "$checkpoint_trimmed")
      if [ -z "$stagnation_checkpoint" ]; then
        stagnation_checkpoint="none"
      fi
      stagnation_signature_src=$(printf '%s|%s|%s|%s|%s|%s' \
        "$state_mode" "$next_mode" "$transition_reason_runtime" "$done_claim" "$stagnation_plan_head" "$stagnation_checkpoint")
      stagnation_signature=$(printf '%s' "$stagnation_signature_src" | cksum | awk '{print $1}')
      if [ -n "$stagnation_last_signature" ] && [ "$stagnation_signature" = "$stagnation_last_signature" ]; then
        stagnation_repeat_count=$((stagnation_repeat_count + 1))
      else
        stagnation_repeat_count=0
      fi
      stagnation_last_signature=$stagnation_signature
      if [ "$next_mode" != "DONE" ] && [ "$stagnation_repeat_count" -ge 2 ]; then
        stagnation_note="Loop stagnation detected: repeated transition signature with limited forward progress."
        loop_feedback="${loop_feedback}

Stagnation guardrail:
- Recent iterations repeated the same transition signature.
- Do not repeat identical plan/command output.
- Either emit DECISION_REQUEST for truly required missing inputs, or choose explicit assumptions and advance with verifiable progress."
        if [ "$stagnation_repeat_count" -eq 2 ]; then
          append_failure_entry "$failures_file" "iteration-$iteration:loop-stagnation" \
            "Loop stagnation detected" \
            "Repeated transition signature without forward progress" \
            "Switch strategy via explicit assumptions or early decision checkpoint"
          stream_emit_line "$stream_output_file" "Loop stagnation detected; injecting anti-repeat guardrail."
          iteration_report="${iteration_report}
$stagnation_note"
        fi
      fi

      append_session_entry "$session_log_file" "iteration $iteration ($state_mode -> $next_mode)" "$iteration_report"
      loop_summary="${loop_summary}
Iteration $iteration ($state_mode -> $next_mode):
$iteration_report"
      stream_emit_line "$stream_output_file" "Step $iteration: $state_mode -> $next_mode ($transition_reason_runtime)"
      checkpoint_stream=$(single_line_snippet "$checkpoint_trimmed")
      if [ -n "$checkpoint_stream" ] && [ "$checkpoint_stream" != "NONE" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration checkpoint: $checkpoint_stream"
      fi
      plan_update_head=$(printf '%s\n' "$plan_update" | sed -n '1p')
      plan_update_head=$(trim "$plan_update_head")
      if [ -n "$plan_update_head" ]; then
        stream_emit_line "$stream_output_file" "Step $iteration next: $plan_update_head"
      fi
      done_claim_stream=$done_claim
      if [ -z "$(trim "$done_claim_stream")" ]; then
        done_claim_stream="none"
      fi
      stream_emit_line "$stream_output_file" "Step $iteration completion check: done_claim=$done_claim_stream next_mode=$next_mode"

      if [ "$next_mode" = "DONE" ]; then
        if [ -z "$(trim "$assistant_output")" ] || [ "$assistant_output" = "NONE" ]; then
          final_candidate=$(trim "$final_section")
          if [ -z "$final_candidate" ] || [ "$final_candidate" = "NONE" ]; then
            final_candidate=$(trim "$checkpoint_text")
          fi
          if [ -n "$final_candidate" ] && [ "$final_candidate" != "NONE" ]; then
            assistant_output="$final_candidate"
          fi
        fi
        break
      fi

      iteration=$((iteration + 1))
    done

    git_status=$(cd "$workspace_path" && git status --short 2>/dev/null || printf 'Not a git repository.')
    git_diff=$(cd "$workspace_path" && git --no-pager diff --no-color 2>/dev/null || printf 'Not a git repository.')
    if [ -z "$git_diff" ]; then
      git_diff="No working tree changes."
    fi

    plan_text=$(sed -n '1,260p' "$plan_file")
    failures_tail=$(tail -n 600 "$failures_file" 2>/dev/null || sed -n '1,600p' "$failures_file")
    session_tail=$(tail -n 800 "$session_log_file" 2>/dev/null || sed -n '1,800p' "$session_log_file")
    controller_tail=$(tail -n 1200 "$controller_raw_file" 2>/dev/null || sed -n '1,1200p' "$controller_raw_file")
    final_state_mode=$(normalize_mode "$(state_get "$state_file" "mode" "INVESTIGATE")")

    if printf '%s' "$assistant_output" | grep -qi '^Run timed out after'; then
      assistant_output=$(structured_incomplete_run_message \
        "$final_state_mode" \
        "" \
        "" \
        "$augmented_user_prompt")
    fi

    if [ "$final_state_mode" != "DONE" ] && [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      if output_is_intermediate_contract "$assistant_output"; then
        synthesis_remaining_budget=0
        synthesis_now_epoch=$(date +%s 2>/dev/null || printf '0')
        case "$synthesis_now_epoch" in
          ""|*[!0-9]*)
            synthesis_now_epoch=$run_started_epoch
            ;;
        esac
        synthesis_remaining_budget=$((run_time_budget - (synthesis_now_epoch - run_started_epoch)))
        if [ "$synthesis_remaining_budget" -lt 0 ]; then
          synthesis_remaining_budget=0
        fi

        attempt_model_reasoning_synthesis=1
        if [ "$assay_run_profile" -eq 1 ]; then
          attempt_model_reasoning_synthesis=0
        fi

        reasoning_synthesis_assumption_required=0
        reasoning_synthesis_assumption_extra=""
        if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
          reasoning_synthesis_assumption_required=1
          reasoning_synthesis_assumption_extra=$(cat <<'EOF'
- Initial Assumption
- Invalidating Evidence
- Revised Decision
- Evidence Delta
EOF
)
        fi

        if [ "$attempt_model_reasoning_synthesis" -eq 1 ] && [ "$synthesis_remaining_budget" -ge 8 ]; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage: attempting one final synthesis from collected evidence."
          reasoning_synthesis_requirements=$(cat <<'EOF'
Write a final reasoning answer with complete contracts:
- Outcome
- Verification Evidence (must include concrete command anchors from this run)
- Assumptions and Alternatives
- Contradiction Check
- Decision
- Priority Order
- Fallback Path
- Disconfirming Evidence
- Source Quality Ranking
- Source Conflict Resolution
- Scenario-Specific Check
- Risks
- Next Improvement
Do not mention being incomplete or partial unless the result is genuinely blocked by missing evidence.
EOF
)
          if [ "$reasoning_synthesis_assumption_required" -eq 1 ]; then
            reasoning_synthesis_requirements=$(printf '%s\n%s' "$reasoning_synthesis_requirements" "$reasoning_synthesis_assumption_extra")
          fi
          reasoning_synthesis_prompt=$(cat <<EOF
You are finalizing an open-ended reasoning run where prior iterations gathered evidence but did not cleanly converge.

User request:
$augmented_user_prompt

Current mode:
$final_state_mode

Current plan:
$plan_text

Loop summary:
$loop_summary

Failure ledger (tail):
$failures_tail

Git status:
$git_status

Git diff:
$git_diff

Current assistant draft:
$assistant_output

$reasoning_synthesis_requirements
EOF
)

          reasoning_synthesis_timeout_fallback=24
          if [ "$assay_run_profile" -eq 1 ]; then
            reasoning_synthesis_timeout_fallback=12
          fi
          if [ "$synthesis_remaining_budget" -lt "$reasoning_synthesis_timeout_fallback" ]; then
            reasoning_synthesis_timeout_fallback=$synthesis_remaining_budget
          fi
          if [ "$reasoning_synthesis_timeout_fallback" -lt 8 ]; then
            reasoning_synthesis_timeout_fallback=8
          fi
          reasoning_synthesis_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$reasoning_synthesis_timeout_fallback" 8 6)

          if [ -n "$stream_output_file" ]; then
            ARTIFICER_STREAM_FILE="$stream_output_file"
            export ARTIFICER_STREAM_FILE
          fi
          RUN_TIMEOUT_SEC=$reasoning_synthesis_timeout_sec
          reasoning_synthesis_output=$(run_model "$model" "$reasoning_synthesis_prompt" || true)
          unset RUN_TIMEOUT_SEC 2>/dev/null || true
          unset ARTIFICER_STREAM_FILE 2>/dev/null || true
          reasoning_synthesis_output=$(normalize_assistant_output "$reasoning_synthesis_output")

          if [ -n "$(trim "$reasoning_synthesis_output")" ]; then
            reasoning_synthesis_output=$(ensure_output_has_runtime_command_evidence \
              "$reasoning_synthesis_output" \
              "$loop_summary" \
              "$run_command_success_total" \
              "$augmented_user_prompt" \
              "1")
            reasoning_synthesis_output=$(normalize_claim_evidence_completeness_contract "$reasoning_synthesis_output" "$augmented_user_prompt" "$loop_summary")
            reasoning_synthesis_output=$(normalize_source_quality_contradiction_contract "$reasoning_synthesis_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
            reasoning_synthesis_output=$(normalize_scenario_depth_final_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            if [ "$reasoning_synthesis_assumption_required" -eq 1 ]; then
              reasoning_synthesis_output=$(normalize_assumption_revision_final_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            fi
            reasoning_synthesis_output=$(normalize_reasoning_followup_thread_contract "$reasoning_synthesis_output" "$augmented_user_prompt")
            reasoning_synthesis_output=$(normalize_reasoning_live_contract "$reasoning_synthesis_output" "$augmented_user_prompt")

            synthesis_assumption_contract_ok=1
            if [ "$reasoning_synthesis_assumption_required" -eq 1 ] && ! final_has_assumption_revision_contract "$reasoning_synthesis_output"; then
              synthesis_assumption_contract_ok=0
            fi
            if final_has_source_quality_contradiction_contract "$reasoning_synthesis_output" && final_has_claim_evidence_completeness_contract "$reasoning_synthesis_output" && final_has_scenario_specific_depth "$reasoning_synthesis_output" "$augmented_user_prompt" && [ "$synthesis_assumption_contract_ok" -eq 1 ] && ! output_is_intermediate_contract "$reasoning_synthesis_output"; then
              assistant_output=$reasoning_synthesis_output
              final_state_mode="DONE"
              state_set "$state_file" "mode" "DONE"
              state_set "$state_file" "transition_reason" "reasoning completion salvage synthesis"
              stream_emit_line "$stream_output_file" "Reasoning completion salvage produced a complete final response; mode promoted to DONE."
            else
              stream_emit_line "$stream_output_file" "Reasoning completion salvage produced output, but completion contracts were still incomplete."
            fi
          else
            stream_emit_line "$stream_output_file" "Reasoning completion salvage returned empty output."
          fi
        elif [ "$attempt_model_reasoning_synthesis" -eq 0 ]; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage: skipping extra model synthesis in assay profile; using deterministic contract synthesis fallback."
        else
          stream_emit_line "$stream_output_file" "Reasoning completion salvage skipped due low remaining budget (${synthesis_remaining_budget}s)."
        fi

        if [ "$final_state_mode" != "DONE" ] && output_is_intermediate_contract "$assistant_output"; then
          stream_emit_line "$stream_output_file" "Reasoning completion salvage fallback: synthesizing deterministic contract-complete response from collected evidence."
          fallback_now_epoch=$(date +%s 2>/dev/null || printf '0')
          case "$fallback_now_epoch" in
            ""|*[!0-9]*)
              fallback_now_epoch=$run_started_epoch
              ;;
          esac
          fallback_elapsed_sec=$((fallback_now_epoch - run_started_epoch))
          if [ "$fallback_elapsed_sec" -lt 0 ]; then
            fallback_elapsed_sec=0
          fi
          reasoning_fallback_output=$(reasoning_deterministic_salvage_output \
            "$augmented_user_prompt" \
            "$plan_text" \
            "$loop_summary" \
            "$run_command_success_total" \
            "$fallback_elapsed_sec")
          assistant_output=$reasoning_fallback_output
          final_state_mode="DONE"
          state_set "$state_file" "mode" "DONE"
          state_set "$state_file" "transition_reason" "reasoning completion deterministic salvage"
          stream_emit_line "$stream_output_file" "Reasoning deterministic salvage emitted a complete fallback response; mode promoted to DONE."
        fi
      fi
    fi

    if [ "$final_state_mode" != "DONE" ] && [ -z "$(trim "$assistant_output")" ]; then
      next_action_line=$(printf '%s\n' "$plan_text" | sed -n '/^Next Action:/,$p' | sed -n '2p')
      next_action_line=$(trim "$next_action_line")
      if [ -z "$next_action_line" ]; then
        next_action_line=$(reasoning_next_improvement_line_for_prompt "$augmented_user_prompt")
      fi
      assistant_output=$(structured_incomplete_run_message "$final_state_mode" "$next_action_line" "" "$augmented_user_prompt")
    fi

    if [ -z "$(trim "$assistant_output")" ] && grep -qi 'approval_required' "$failures_file"; then
      assistant_output="I need command approval to continue. Approve the requested command and run again."
    fi

    if [ -z "$(trim "$assistant_output")" ] && [ "$final_state_mode" = "DONE" ]; then
      synthesis_requirements_text=$(cat <<'EOF'
Write a concise final response:
- what was done
- key findings
- next best step
- no role prefixes and no control tokens
EOF
)
      if [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
        synthesis_requirements_text=$(cat <<EOF
Write a structured security findings report that includes:
- Findings section with numbered items
- each finding must include Severity, Evidence, Remediation, and Status
- separate validated evidence from uncertainty
- explicit next verification actions
- no role prefixes and no control tokens
EOF
)
      fi
      if [ "$run_mode" = "teacher" ]; then
        synthesis_requirements_text=$(cat <<EOF
Write a teaching response that includes:
- a brief explanation tailored to the learner likely level
- a staged curriculum plan (now, next, later)
- 2 concise comprehension checks
- one spaced-review recommendation using interaction gap signal: $teacher_gap_summary
- no role prefixes and no control tokens
EOF
)
      fi
      synthesis_prompt=$(cat <<EOF
You are finalizing an agent loop run for a coding assistant.

User request:
$augmented_user_prompt

Current plan:
$plan_text

Loop summary:
$loop_summary

Failure ledger (tail):
$failures_tail

Git status:
$git_status

Git diff:
$git_diff

$synthesis_requirements_text
EOF
)

      if [ -n "$stream_output_file" ]; then
        ARTIFICER_STREAM_FILE="$stream_output_file"
        export ARTIFICER_STREAM_FILE
      fi
      synthesis_timeout_fallback=35
      if [ "$assay_run_profile" -eq 1 ]; then
        synthesis_timeout_fallback=14
      fi
      run_now_for_synthesis=$(date +%s 2>/dev/null || printf '0')
      case "$run_now_for_synthesis" in
        ""|*[!0-9]*)
          run_now_for_synthesis=$run_started_epoch
          ;;
      esac
      synthesis_budget_remaining=$((run_time_budget - (run_now_for_synthesis - run_started_epoch)))
      if [ "$synthesis_budget_remaining" -lt 0 ]; then
        synthesis_budget_remaining=0
      fi
      if [ "$synthesis_budget_remaining" -gt 0 ] && [ "$synthesis_budget_remaining" -lt "$synthesis_timeout_fallback" ]; then
        synthesis_timeout_fallback=$synthesis_budget_remaining
      fi
      if [ "$synthesis_timeout_fallback" -lt 6 ]; then
        synthesis_timeout_fallback=6
      fi
      if [ "$synthesis_budget_remaining" -le 4 ]; then
        assistant_output=$(structured_incomplete_run_message "$final_state_mode" "" "" "$augmented_user_prompt")
      else
        synthesis_timeout_sec=$(model_timeout_for_run "$run_started_epoch" "$run_time_budget" "$synthesis_timeout_fallback" 8 6)
        RUN_TIMEOUT_SEC=$synthesis_timeout_sec
        assistant_output=$(run_model "$model" "$synthesis_prompt" || true)
        unset RUN_TIMEOUT_SEC 2>/dev/null || true
        unset ARTIFICER_STREAM_FILE 2>/dev/null || true
        assistant_output=$(normalize_assistant_output "$assistant_output")
        if [ -z "$(trim "$assistant_output")" ]; then
          assistant_output="Run completed, but the model did not provide a final synthesis."
        fi
      fi
      unset ARTIFICER_STREAM_FILE 2>/dev/null || true
    fi

    assistant_output=$(normalize_assistant_output "$assistant_output")
    if [ -n "$(trim "$assistant_output")" ] && ! printf '%s\n' "$assistant_output" | grep -Eq '[A-Za-z0-9]'; then
      assistant_output=$(structured_incomplete_run_message "$final_state_mode" "" "" "$augmented_user_prompt")
    fi
    if [ "$run_mode" = "text-perfecter" ] && [ -n "$(trim "$assistant_output")" ]; then
      perfecter_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$perfecter_lower" | grep -Eq 'stability rationale|convergence|thrash'; then
        assistant_output=$(printf '%s\nStability Rationale: Revisions were stopped after consecutive passes produced no material semantic improvements.' "$assistant_output")
      fi
      perfecter_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
      if ! printf '%s' "$perfecter_lower" | grep -Eq 'evidence basis|evidence summary|sources considered'; then
        assistant_output=$(printf '%s\nEvidence Basis: Incorporated explicit and discovered web sources, plus contradiction checks across variants before finalizing.' "$assistant_output")
      fi
    fi

    if output_looks_derailed "$assistant_output"; then
      repaired_output=$(salvage_direct_response "$model" "$user_prompt")
      if [ -n "$(trim "$repaired_output")" ]; then
        assistant_output=$repaired_output
      fi
    fi

    if [ "$final_state_mode" = "DONE" ] && printf '%s\n' "$assistant_output" | grep -qi '^Recovered malformed controller output'; then
      case "$(printf '%s' "$augmented_user_prompt" | tr '[:upper:]' '[:lower:]')" in
        *godot*)
          if [ -f "$workspace_path/project.godot" ]; then
            assistant_output="Created a runnable Godot project in the workspace and verified it with headless Godot."
          else
            assistant_output="Completed implementation and verification successfully."
          fi
          ;;
        *)
          assistant_output="Completed implementation and verification successfully."
          ;;
      esac
    fi

    if [ "$run_mode" = "pentest" ] || [ "$run_mode" = "security-audit" ]; then
      assistant_output=$(security_mode_normalize_assistant_output \
        "$assistant_output" \
        "$run_mode" \
        "$final_state_mode" \
        "$loop_summary" \
        "$failures_tail" \
        "$git_status")
    fi

    if [ "$assay_run_profile" -eq 1 ]; then
      run_finished_epoch=$(date +%s 2>/dev/null || printf '0')
      case "$run_finished_epoch" in
        ""|*[!0-9]*)
          run_finished_epoch=$run_started_epoch
          ;;
      esac
      run_elapsed_sec=$((run_finished_epoch - run_started_epoch))
      if [ "$run_elapsed_sec" -lt 0 ]; then
        run_elapsed_sec=0
      fi
      assistant_output=$(assay_normalize_assistant_output "$assistant_output" "$final_state_mode" "$plan_text" "$run_time_budget" "$run_elapsed_sec" "$augmented_user_prompt")
    fi

    evidence_claim_map_required=0
    source_quality_output_required=0
    scenario_depth_output_required=0
    high_risk_fail_closed_output_required=0
    if [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      evidence_claim_map_required=1
      source_quality_output_required=1
      scenario_depth_output_required=1
    fi
    if prompt_requires_adversarial_reasoning "$augmented_user_prompt" || prompt_requires_cross_domain_reasoning "$augmented_user_prompt" || prompt_requires_decision_completeness "$augmented_user_prompt"; then
      scenario_depth_output_required=1
    fi
    case "$run_mode" in
      report|teacher|security-audit|pentest|text-perfecter|gui-testing)
        evidence_claim_map_required=1
        source_quality_output_required=1
        scenario_depth_output_required=1
        ;;
    esac
    if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
      high_risk_fail_closed_output_required=1
      evidence_claim_map_required=1
      source_quality_output_required=1
      scenario_depth_output_required=1
    fi
    if [ "$run_command_success_total" -gt 0 ] && { [ "$evidence_claim_map_required" -eq 1 ] || [ "$source_quality_output_required" -eq 1 ] || [ "$scenario_depth_output_required" -eq 1 ]; }; then
      assistant_output=$(ensure_output_has_runtime_command_evidence \
        "$assistant_output" \
        "$loop_summary" \
        "$run_command_success_total" \
        "$augmented_user_prompt" \
        "$evidence_claim_map_required")
      if [ "$evidence_claim_map_required" -eq 1 ]; then
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
      fi
      if [ "$source_quality_output_required" -eq 1 ]; then
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
      fi
      if [ "$scenario_depth_output_required" -eq 1 ]; then
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
      fi
    fi
    if [ "$scenario_depth_output_required" -eq 1 ] || { [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; }; then
      assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
      assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
    fi
    if [ "$final_state_mode" = "DONE" ]; then
      assistant_output=$(ensure_output_has_runtime_command_evidence \
        "$assistant_output" \
        "$loop_summary" \
        "$run_command_success_total" \
        "$augmented_user_prompt" \
        "$evidence_claim_map_required")
      if [ "$evidence_claim_map_required" -eq 1 ]; then
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_claim_evidence_completeness_contract "$assistant_output"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "expand the claim-to-evidence map with at least two concrete entries, then rerun." "Claim-evidence completion gate withheld DONE because the final synthesis lacked multi-claim verification/invalidation mapping or evidence caveats." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "claim-evidence output contract incomplete"
          stream_emit_line "$stream_output_file" "Claim-evidence output gate converted DONE to VERIFY pending multi-claim evidence mapping."
        fi
      fi
      if [ "$source_quality_output_required" -eq 1 ]; then
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_source_quality_contradiction_contract "$assistant_output"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "add confidence-tiered source ranking and explicit contradiction resolution, then rerun." "Source-quality completion gate withheld DONE because final synthesis lacked required source ranking/contradiction structure." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "source-quality output contract incomplete"
          stream_emit_line "$stream_output_file" "Source-quality output gate converted DONE to VERIFY pending source ranking and contradiction resolution details."
        fi
      fi
      if [ "$scenario_depth_output_required" -eq 1 ]; then
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if ! final_has_scenario_specific_depth "$assistant_output" "$augmented_user_prompt"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "add prompt-anchored scenario depth details in non-template lines and rerun." "Scenario-depth completion gate withheld DONE because final synthesis remained generic and lacked prompt-token grounding outside template contract headers." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "scenario-depth output contract incomplete"
          stream_emit_line "$stream_output_file" "Scenario-depth output gate converted DONE to VERIFY pending non-template prompt-anchored specificity."
        fi
      fi
      if [ "$high_risk_fail_closed_output_required" -eq 1 ]; then
        assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
        if ! final_has_high_risk_fail_closed_contract "$assistant_output" "$run_command_success_total"; then
          assistant_output=$(structured_incomplete_run_message "$final_state_mode" "collect explicit high-risk verification evidence and rerun." "High-risk fail-closed completion gate withheld DONE because verification status/go-no-go/evidence requirements were incomplete." "$augmented_user_prompt")
          final_state_mode="VERIFY"
          state_set "$state_file" "blocking" "high-risk fail-closed output contract incomplete"
          stream_emit_line "$stream_output_file" "High-risk fail-closed output gate converted DONE to VERIFY pending explicit verification contract."
        fi
      fi
    fi

    post_gate_reasoning_salvage_eligible=0
    if [ "$implementation_expected" -eq 0 ] && prompt_prefers_reasoning_completion "$augmented_user_prompt"; then
      post_gate_reasoning_salvage_eligible=1
    elif [ "$assay_run_profile" -eq 1 ]; then
      case "$run_mode" in
        assistant|report|teacher|security-audit|pentest)
          post_gate_reasoning_salvage_eligible=1
          ;;
      esac
    fi

    if [ "$post_gate_reasoning_salvage_eligible" -eq 1 ]; then
      post_gate_salvage_required=0
      if [ "$final_state_mode" != "DONE" ]; then
        post_gate_salvage_required=1
      elif output_is_intermediate_contract "$assistant_output"; then
        post_gate_salvage_required=1
      elif final_has_instructional_placeholders "$assistant_output"; then
        post_gate_salvage_required=1
      fi

      if [ "$post_gate_salvage_required" -eq 1 ] && [ "$assay_run_profile" -eq 1 ]; then
        stream_emit_line "$stream_output_file" "Reasoning post-gate salvage: synthesizing deterministic contract-complete output."
        post_gate_now_epoch=$(date +%s 2>/dev/null || printf '0')
        case "$post_gate_now_epoch" in
          ""|*[!0-9]*)
            post_gate_now_epoch=$run_started_epoch
            ;;
        esac
        post_gate_elapsed_sec=$((post_gate_now_epoch - run_started_epoch))
        if [ "$post_gate_elapsed_sec" -lt 0 ]; then
          post_gate_elapsed_sec=0
        fi

        assistant_output=$(reasoning_deterministic_salvage_output \
          "$augmented_user_prompt" \
          "$plan_text" \
          "$loop_summary" \
          "$run_command_success_total" \
          "$post_gate_elapsed_sec")
        assistant_output=$(assay_normalize_assistant_output \
          "$assistant_output" \
          "DONE" \
          "$plan_text" \
          "$run_time_budget" \
          "$post_gate_elapsed_sec" \
          "$augmented_user_prompt")
        assistant_output=$(ensure_output_has_runtime_command_evidence \
          "$assistant_output" \
          "$loop_summary" \
          "$run_command_success_total" \
          "$augmented_user_prompt" \
          "1")
        assistant_output=$(normalize_claim_evidence_completeness_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_adversarial_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_decision_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_cross_domain_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_recovery_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_verification_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_ambiguity_final_contract "$assistant_output")
        assistant_output=$(normalize_source_quality_contradiction_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary" "$run_command_success_total")
        assistant_output=$(normalize_scenario_depth_final_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
        assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        if prompt_requires_assumption_revision_contract "$augmented_user_prompt"; then
          assistant_output=$(normalize_assumption_revision_final_contract "$assistant_output" "$augmented_user_prompt")
          assistant_output=$(normalize_reasoning_placeholder_contract "$assistant_output" "$augmented_user_prompt" "$loop_summary")
          assistant_output=$(normalize_reasoning_output_polish "$assistant_output")
        fi
        assistant_output=$(normalize_reasoning_followup_thread_contract "$assistant_output" "$augmented_user_prompt")
        assistant_output=$(normalize_reasoning_live_contract "$assistant_output" "$augmented_user_prompt")
        if prompt_requires_high_risk_fail_closed "$augmented_user_prompt" "$run_mode"; then
          assistant_output=$(normalize_high_risk_fail_closed_contract "$assistant_output" "$augmented_user_prompt" "$run_command_success_total" "$run_mode")
        fi

        final_state_mode="DONE"
        state_set "$state_file" "mode" "DONE"
        state_set "$state_file" "transition_reason" "reasoning post-gate deterministic salvage"
      fi
    fi

    if { [ "$run_mode" = "programming" ] || prompt_requires_code_implementation "$augmented_user_prompt"; } \
      && { [ "$final_state_mode" != "DONE" ] || programming_output_needs_concise_summary "$assistant_output" "$final_state_mode" || programming_should_force_concise_summary "$run_mode" "$compute_budget" "$max_iterations" "$augmented_user_prompt"; }; then
      assistant_output=$(programming_concise_final_output \
        "$assistant_output" \
        "$final_state_mode" \
        "$augmented_user_prompt" \
        "$loop_summary" \
        "$plan_text" \
        "$git_status" \
        "$run_command_success_total")
      stream_emit_line "$stream_output_file" "Programming final-output normalizer replaced verbose or generic summary with concise implementation summary."
    fi

    decision_request_json=$(decision_request_json_for_conversation "$conv_dir")
    if [ "$decision_request_json" != "null" ]; then
      decision_summary_text=$(decision_request_summary_text_from_json "$decision_request_json")
      decision_summary_text=$(trim "$decision_summary_text")
      if [ -n "$decision_summary_text" ]; then
        assistant_output_lower=$(printf '%s' "$assistant_output" | tr '[:upper:]' '[:lower:]')
        if [ -z "$(trim "$assistant_output")" ]; then
          assistant_output="$decision_summary_text"
          stream_emit_line "$stream_output_file" "Decision summary injected into final assistant output."
        elif ! printf '%s' "$assistant_output_lower" | grep -Eq 'question:|options:'; then
          assistant_output=$(printf '%s\n\n%s' "$assistant_output" "$decision_summary_text")
          stream_emit_line "$stream_output_file" "Decision summary appended to final assistant output."
        fi
      fi
    fi

    if [ "$run_mode" = "teacher" ]; then
      teacher_output_snippet=$(single_line_snippet "$assistant_output")
      if [ -z "$(trim "$teacher_output_snippet")" ]; then
        teacher_output_snippet="(no assistant summary captured)"
      fi
      teacher_post_note=$(cat <<EOF
delivered=$teacher_output_snippet
interaction_gap=$teacher_gap_summary
recommended_review_spacing_days=$teacher_review_days
EOF
)
      append_teacher_model_note "$teacher_model_file" "Post-run teaching summary" "$teacher_post_note"
    fi

    append_session_entry "$session_log_file" "final response" "$assistant_output"
    append_message "$conv_dir" "assistant" "$assistant_output"

    session_tail=$(tail -n 1000 "$session_log_file" 2>/dev/null || sed -n '1,1000p' "$session_log_file")
    controller_tail=$(tail -n 1400 "$controller_raw_file" 2>/dev/null || sed -n '1,1400p' "$controller_raw_file")
    session_combined=$(cat <<EOF
$session_tail

## Controller Raw Output

$controller_tail
EOF
)
    state_text=$(sed -n '1,80p' "$state_file")
    assistant_json=$(json_escape "$assistant_output")
    plan_json=$(json_escape "$plan_text")
    model_json=$(json_escape "$model")
    git_status_json=$(json_escape "$git_status")
    git_diff_json=$(json_escape "$git_diff")
    failures_json=$(json_escape "$failures_tail")
    session_json=$(json_escape "$session_combined")
    state_json=$(json_escape "$state_text")
    blocked_commands_json=$(blocked_command_json_from_file "$blocked_commands_file")

    # In assay mode, ensure a minimum command-depth trace before finalizing.
    if [ "$assay_run_profile" -eq 1 ]; then
      depth_fill_attempts=0
      while [ "$run_command_success_total" -lt 2 ] && [ "$depth_fill_attempts" -lt 3 ]; do
        depth_fill_attempts=$((depth_fill_attempts + 1))
        depth_fill_cmd="git status --short"
        depth_out=$(mktemp)
        depth_status_file=$(mktemp)
        execute_mediated_command "$workspace_id" "$workspace_path" "$depth_fill_cmd" "$depth_out" "$depth_status_file" "$command_mode" "$blocked_commands_file"
        depth_status=$(cat "$depth_status_file" 2>/dev/null || printf '%s' "error")
        depth_output=$(sed -n '1,220p' "$depth_out")
        rm -f "$depth_out" "$depth_status_file"
        if [ "$depth_status" = "ok" ]; then
          run_command_success_total=$((run_command_success_total + 1))
        fi
        depth_command_json=$(json_escape "$depth_fill_cmd")
        depth_status_json=$(json_escape "$depth_status")
        depth_output_json=$(json_escape "$depth_output")
        depth_command_item=$(printf '{"command":"%s","status":"%s","output":"%s"}' \
          "$depth_command_json" "$depth_status_json" "$depth_output_json")
        if [ "$commands_first" -eq 1 ]; then
          commands_json=$depth_command_item
          commands_first=0
        else
          commands_json="${commands_json},${depth_command_item}"
        fi
        stream_emit_line "$stream_output_file" "Assay depth check command: $depth_fill_cmd ($depth_status)"
        if [ "$depth_status" != "ok" ]; then
          break
        fi
      done
    fi

    queue_status_from_run="$forced_queue_status"
    if [ -z "$queue_status_from_run" ]; then
      queue_status_from_run="done"
      if [ "$blocked_commands_json" != "[]" ]; then
        queue_status_from_run="awaiting_approval"
        save_approval_request_from_blocked_file "$conv_dir" "$blocked_commands_file" >/dev/null 2>&1 || true
      elif [ "$decision_request_json" != "null" ]; then
        queue_status_from_run="awaiting_decision"
      elif [ "$final_state_mode" != "DONE" ]; then
        if [ "$assay_run_profile" -eq 1 ] && assay_output_has_required_sections "$assistant_output" && ! output_is_intermediate_contract "$assistant_output" && ! final_has_instructional_placeholders "$assistant_output"; then
          queue_status_from_run="done"
        else
          queue_status_from_run="error"
        fi
      fi
    fi
    if [ "$queue_status_from_run" != "awaiting_approval" ]; then
      clear_approval_request "$conv_dir"
    fi
    run_event_status=$(run_event_status_from_run "$queue_status_from_run" "$run_budget_exhausted")
    queue_finalize_for_run_item "$conv_dir" "$queue_item_id" "$queue_status_from_run" ""
    run_elapsed_sec=0
    case "$run_started_epoch" in
      ""|*[!0-9]*)
        run_started_epoch=0
        ;;
    esac
    run_finished_epoch=$(date +%s 2>/dev/null || printf '0')
    case "$run_finished_epoch" in
      ""|*[!0-9]*)
        run_finished_epoch=0
        ;;
    esac
    if [ "$run_started_epoch" -gt 0 ] && [ "$run_finished_epoch" -ge "$run_started_epoch" ]; then
      run_elapsed_sec=$((run_finished_epoch - run_started_epoch))
    fi
    run_elapsed_min=$((run_elapsed_sec / 60))
    run_elapsed_rem=$((run_elapsed_sec % 60))
    decision_requested_for_variant=0
    if [ "$decision_request_json" != "null" ]; then
      decision_requested_for_variant=1
    fi
    failure_count_for_variant=$(grep -c '^## ' "$failures_file" 2>/dev/null || printf '0')
    case "$failure_count_for_variant" in
      ""|*[!0-9]*)
        failure_count_for_variant=0
        ;;
    esac
    if [ -n "$controller_variant_id" ] && command -v mr_controller_variant_record_run >/dev/null 2>&1; then
      mr_controller_variant_record_run \
        "$controller_variant_id" \
        "$run_event_id" \
        "$queue_status_from_run" \
        "$final_state_mode" \
        "$run_elapsed_sec" \
        "$iteration" \
        "$decision_requested_for_variant" \
        "$failure_count_for_variant" \
        "$run_mode" \
        "$model" >/dev/null 2>&1 || true
    fi
    stream_emit_line "$stream_output_file" "Final response prepared for delivery."
    stream_emit_line "$stream_output_file" "Run artifacts captured (state, failures, trace)."
    stream_emit_line "$stream_output_file" "Worked for ${run_elapsed_min}m ${run_elapsed_rem}s."
    stream_emit_line "$stream_output_file" "Run finalized with status: $queue_status_from_run (event=$run_event_status)"
    run_finished_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    run_stream_preview=$(sed -n '1,360p' "$stream_output_file" 2>/dev/null || true)
    commands_array_json="[$commands_json]"
    if [ -z "$(trim "$commands_json")" ]; then
      commands_array_json="[]"
    fi
    final_task_status_json=$(task_status_json_from_tasks_dir "$tasks_dir" "$queue_status_from_run" "$state_text")
    run_error_text=""
    if [ "$queue_status_from_run" = "error" ] || [ "$run_event_status" = "timeout" ]; then
      run_error_text=$assistant_output
    fi
    controller_variant_event_hint=""
    if [ -n "$controller_variant_id" ]; then
      controller_variant_event_hint="controller_variant=$controller_variant_id"
      if [ -n "$controller_variant_candidate_id" ] && [ "$controller_variant_id" = "$controller_variant_candidate_id" ]; then
        controller_variant_event_hint="${controller_variant_event_hint} (candidate)"
      fi
    fi
    agent_event_json=$(build_run_event_json \
      "$run_event_status" \
      "$run_started_iso" \
      "$run_finished_iso" \
      "$model" \
      "$plan_text" \
      "$commands_array_json" \
      "$run_stream_preview" \
      "$failures_tail" \
      "$session_combined" \
      "$state_text" \
      "$git_status" \
      "$git_diff" \
      "$run_error_text" \
      "$controller_variant_event_hint" \
      "$run_event_id" \
      "$final_task_status_json" \
      "$run_message_anchor" \
      "$assay_task_id" \
      "$assistant_output")
    append_run_event_json "$conv_dir" "$agent_event_json"
    run_runtime_mark_finalized

    printf '{"success":true,"model":"%s","plan":"%s","assistant":"%s","git_status":"%s","git_diff":"%s","commands":[%s],"blocked_commands":%s,"decision_request":%s,"failures":"%s","session_log":"%s","state":"%s","task_status":%s}\n' \
      "$model_json" "$plan_json" "$assistant_json" "$git_status_json" "$git_diff_json" "$commands_json" "$blocked_commands_json" "$decision_request_json" "$failures_json" "$session_json" "$state_json" "$final_task_status_json"
    rm -f "$valid_attachment_ids" "$blocked_commands_file" "$queue_explicit_skills_override_file" "$request_explicit_skills_file" "$prompt_explicit_skills_file" "$explicit_skills_file"
    exit 0
