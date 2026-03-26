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
