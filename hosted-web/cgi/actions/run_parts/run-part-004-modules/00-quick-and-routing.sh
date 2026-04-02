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
        "$assistant_output" \
        "")
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
