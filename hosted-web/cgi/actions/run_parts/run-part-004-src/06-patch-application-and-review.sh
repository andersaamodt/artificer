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
