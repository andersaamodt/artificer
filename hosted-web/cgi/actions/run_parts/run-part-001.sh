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

