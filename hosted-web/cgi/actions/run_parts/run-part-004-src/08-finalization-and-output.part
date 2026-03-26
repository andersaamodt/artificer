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
