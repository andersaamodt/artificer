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
