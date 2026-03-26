# action: decision_surface_preview
    prompt_text=$(trim "$(param "prompt")")
    question_text=$(trim "$(param "question")")
    run_mode_raw=$(trim "$(param "run_mode")")
    commands_text=$(trim "$(param "commands")")

    run_mode_name=$(normalize_run_mode_name "$run_mode_raw")
    category=$(decision_request_category_for_prompt "$prompt_text" "$question_text" "$run_mode_name" "$commands_text")
    allow=0
    if should_allow_model_decision_request "$prompt_text" "$question_text" "$run_mode_name" "$commands_text"; then
      allow=1
    fi
    allow_json=false
    if [ "$allow" -eq 1 ]; then
      allow_json=true
    fi
    explicit_choice=0
    if decision_prompt_requests_explicit_choice "$prompt_text"; then
      explicit_choice=1
    fi
    missing_required=0
    if decision_prompt_has_missing_required_inputs "$prompt_text"; then
      missing_required=1
    fi
    risk_gate=0
    if decision_question_looks_risk_gate "$question_text"; then
      risk_gate=1
    fi
    external_gate=0
    if decision_commands_trigger_external_gate "$commands_text"; then
      external_gate=1
    fi
    destructive_gate=0
    if decision_commands_trigger_destructive_gate "$commands_text"; then
      destructive_gate=1
    fi

    printf '{"success":true,"allow_decision_request":%s,"category":"%s","signals":{"explicit_choice":%s,"missing_required_inputs":%s,"risk_gate_question":%s,"external_commands":%s,"destructive_commands":%s}}\n' \
      "$allow_json" \
      "$(json_escape "$category")" \
      "$explicit_choice" \
      "$missing_required" \
      "$risk_gate" \
      "$external_gate" \
      "$destructive_gate"
    exit 0
