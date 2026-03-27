mr_mode_update_json() {
  mode_id=$(trim "$(param "mode_id")")
  if ! valid_id "$mode_id"; then
    printf '{"success":false,"error":"invalid mode_id"}'
    return 0
  fi
  if ! mr_mode_exists "$mode_id"; then
    printf '{"success":false,"error":"mode not found"}'
    return 0
  fi

  state_file=$(mr_mode_state_file "$mode_id")

  enabled_raw=$(trim "$(param "enabled")")
  cadence_raw=$(trim "$(param "cadence_sec")")
  priority_raw=$(trim "$(param "priority")")
  interrupt_raw=$(trim "$(param "interrupt_rights")")
  queue_injection_raw=$(trim "$(param "allow_queue_injection")")
  goal_raw=$(param "goal_state")
  subscriptions_raw=$(param "subscriptions")

  if [ -n "$enabled_raw" ]; then
    mr_env_set "$state_file" "enabled" "$(mr_bool_norm "$enabled_raw")"
  fi
  if [ -n "$cadence_raw" ]; then
    mr_env_set "$state_file" "cadence_sec" "$(mr_positive_int_or "$cadence_raw" "900")"
  fi
  if [ -n "$priority_raw" ]; then
    mr_env_set "$state_file" "priority" "$(mr_positive_int_or "$priority_raw" "5")"
  fi
  if [ -n "$interrupt_raw" ]; then
    mr_env_set "$state_file" "interrupt_rights" "$(mr_bool_norm "$interrupt_raw")"
  fi
  if [ -n "$queue_injection_raw" ]; then
    mr_env_set "$state_file" "allow_queue_injection" "$(mr_bool_norm "$queue_injection_raw")"
  fi
  if [ -n "$(trim "$goal_raw")" ]; then
    clean_goal=$(mr_sanitize_inline "$goal_raw")
    mr_env_set "$state_file" "goal_state" "$clean_goal"
    printf '# Goal State\n\n- %s\n' "$clean_goal" > "$(mr_mode_goal_file "$mode_id")"
  fi
  if [ -n "$(trim "$subscriptions_raw")" ]; then
    printf '%s\n' "$(mr_csv_normalize "$subscriptions_raw")" > "$(mr_mode_subscriptions_file "$mode_id")"
  fi

  printf '{"success":true,"mode_id":"%s","mode_runtime":%s}' "$(json_escape "$mode_id")" "$(mode_runtime_state_json)"
}

mr_mode_runtime_state_response() {
  printf '{"success":true,"mode_runtime":%s}\n' "$(mode_runtime_state_json)"
}

mr_mode_runtime_tick_response() {
  workspace_id=$(trim "$(param "workspace_id")")
  conversation_id=$(trim "$(param "conversation_id")")
  if [ -n "$workspace_id" ] && ! valid_id "$workspace_id"; then
    printf '{"success":false,"error":"invalid workspace_id"}\n'
    return 0
  fi
  if [ -n "$conversation_id" ] && ! valid_id "$conversation_id"; then
    printf '{"success":false,"error":"invalid conversation_id"}\n'
    return 0
  fi

  tick_json=$(mr_mode_scheduler_tick_json "$workspace_id" "$conversation_id")
  printf '{"success":true,"tick":%s,"mode_runtime":%s}\n' "$tick_json" "$(mode_runtime_state_json)"
}

mr_failure_taxonomy_state_response() {
  printf '{"success":true,"failure_taxonomy":%s}\n' "$(mr_failure_taxonomy_state_json)"
}

mr_failure_taxonomy_query_response() {
  category_filter=$(trim "$(param "category")")
  severity_filter=$(trim "$(param "severity")")
  surface_filter=$(trim "$(param "surface")")
  mode_filter=$(trim "$(param "mode")")
  since_epoch=$(trim "$(param "since_epoch")")
  limit_value=$(trim "$(param "limit")")
  printf '{"success":true,"failure_taxonomy_query":%s}\n' \
    "$(mr_failure_taxonomy_query_json "$category_filter" "$severity_filter" "$surface_filter" "$mode_filter" "$since_epoch" "$limit_value")"
}

mr_improvement_proposals_state_response() {
  printf '{"success":true,"improvement_proposals":%s}\n' "$(mr_improvement_proposals_state_json)"
}

mr_controller_variants_state_response() {
  printf '{"success":true,"controller_variants":%s,"mode_runtime":%s}\n' \
    "$(mr_controller_variants_state_json)" \
    "$(mode_runtime_state_json)"
}

mr_quality_scorecard_state_response() {
  printf '{"success":true,"quality_scorecard":%s,"mode_runtime":%s}\n' \
    "$(mr_quality_scorecard_state_json)" \
    "$(mode_runtime_state_json)"
}

mr_controller_variant_promote_response() {
  variant_id=$(trim "$(param "variant_id")")
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  if ! valid_id "$variant_id"; then
    printf '{"success":false,"error":"invalid variant_id"}\n'
    return 0
  fi
  if [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for promote"}\n'
    return 0
  fi
  if ! mr_controller_variant_promote "$variant_id"; then
    printf '{"success":false,"error":"variant not found"}\n'
    return 0
  fi
  printf '{"success":true,"variant_id":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$variant_id")" \
    "$(mode_runtime_state_json)"
}

mr_controller_variant_rollback_response() {
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  if [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for rollback"}\n'
    return 0
  fi
  if ! mr_controller_variant_rollback; then
    printf '{"success":false,"error":"rollback target unavailable"}\n'
    return 0
  fi
  printf '{"success":true,"mode_runtime":%s}\n' "$(mode_runtime_state_json)"
}

mr_improvement_proposal_create_response() {
  title_text=$(trim "$(param "title")")
  rationale_text=$(trim "$(param "rationale")")
  proposed_change_text=$(trim "$(param "proposed_change")")
  scope_text=$(trim "$(param "scope")")
  risk_level_text=$(trim "$(param "risk_level")")

  if [ -z "$title_text" ]; then
    printf '{"success":false,"error":"title is required"}\n'
    return 0
  fi
  proposal_id=$(mr_improvement_proposal_create "$title_text" "$rationale_text" "$proposed_change_text" "$scope_text" "$risk_level_text" "manual")
  printf '{"success":true,"proposal_id":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$proposal_id")" \
    "$(mode_runtime_state_json)"
}

mr_improvement_proposal_generate_response() {
  generated_json=$(mr_improvement_proposal_generate_from_taxonomy_json)
  printf '{"success":true,"result":%s,"mode_runtime":%s}\n' "$generated_json" "$(mode_runtime_state_json)"
}

mr_improvement_proposal_decide_response() {
  proposal_id=$(trim "$(param "proposal_id")")
  decision_raw=$(trim "$(param "decision")")
  decision_note=$(param "note")
  manual_confirm=$(mr_bool_norm "$(param "manual_confirm")")
  decision_value="accepted"

  if ! valid_id "$proposal_id"; then
    printf '{"success":false,"error":"invalid proposal_id"}\n'
    return 0
  fi

  case "$decision_raw" in
    accept|accepted)
      decision_value="accepted"
      ;;
    apply|applied)
      decision_value="applied"
      ;;
    reject|rejected|dismiss|dismissed)
      decision_value="rejected"
      ;;
    *)
      printf '{"success":false,"error":"invalid decision"}\n'
      return 0
      ;;
  esac

  if [ "$decision_value" = "applied" ] && [ "$manual_confirm" != "1" ]; then
    printf '{"success":false,"error":"manual_confirm=1 is required for apply"}\n'
    return 0
  fi

  if ! mr_improvement_proposal_set_status "$proposal_id" "$decision_value" "$decision_note"; then
    printf '{"success":false,"error":"proposal not found"}\n'
    return 0
  fi

  printf '{"success":true,"proposal_id":"%s","decision":"%s","mode_runtime":%s}\n' \
    "$(json_escape "$proposal_id")" \
    "$(json_escape "$decision_value")" \
    "$(mode_runtime_state_json)"
}

mr_mode_runtime_skill_invoke_response() {
  mode_id=$(trim "$(param "mode_id")")
  skill_id=$(trim "$(param "skill_id")")
  input_text=$(param "input")
  requested_caps=$(param "capabilities")

  if [ -z "$skill_id" ]; then
    printf '{"success":false,"error":"skill_id is required"}\n'
    return 0
  fi

  mr_skill_invoke_json "$mode_id" "$skill_id" "$input_text" "$requested_caps"
  printf '\n'
}

mr_skill_name_from_trigger_file() {
  trigger_file=$1
  if [ ! -f "$trigger_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(sed -n 's/^name:[[:space:]]*"\{0,1\}\(.*\)"\{0,1\}[[:space:]]*$/\1/p' "$trigger_file" | sed -n '1p')
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_skill_trigger_from_trigger_file() {
  trigger_file=$1
  if [ ! -f "$trigger_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(sed -n 's/^[[:space:]]*-[[:space:]]*"\{0,1\}\(.*\)"\{0,1\}[[:space:]]*$/\1/p' "$trigger_file" | sed -n '1p')
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_skill_caps_from_tools_file() {
  tools_file=$1
  if [ ! -f "$tools_file" ]; then
    printf '%s' ""
    return 0
  fi
  raw=$(tr -d '\n\r' < "$tools_file" | sed -n 's/.*"tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | sed -n '1p')
  if [ -z "$(trim "$raw")" ]; then
    printf '%s' ""
    return 0
  fi
  normalized=$(printf '%s' "$raw" | tr '"' ' ' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | paste -sd, -)
  printf '%s' "$(mr_csv_normalize "$normalized")"
}

mr_skill_description_from_policy_file() {
  policy_file=$1
  if [ ! -f "$policy_file" ]; then
    printf '%s' ""
    return 0
  fi
  parsed=$(awk 'NF { if ($0 ~ /^#/) next; print; exit }' "$policy_file")
  parsed=$(trim "$parsed")
  printf '%s' "$(mr_sanitize_inline "$parsed")"
}

mr_mode_runtime_skill_create_response() {
  skill_id=$(trim "$(param "skill_id")")
  skill_name=$(trim "$(param "name")")
  trigger_text=$(trim "$(param "trigger")")
  capabilities=$(trim "$(param "capabilities")")
  description_text=$(trim "$(param "description")")

  skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
  if ! valid_id "$skill_id"; then
    printf '{"success":false,"error":"invalid skill_id"}\n'
    return 0
  fi
  if mr_skill_exists "$skill_id"; then
    printf '{"success":false,"error":"skill already exists"}\n'
    return 0
  fi
  if [ -z "$skill_name" ]; then
    skill_name=$skill_id
  fi
  if [ -z "$trigger_text" ]; then
    trigger_text="when manually invoked"
  fi
  if [ -z "$capabilities" ]; then
    capabilities="filesystem"
  fi
  if [ -z "$description_text" ]; then
    description_text="Custom skill bundle created from the Artificer skill manager."
  fi

  mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  printf '{"success":true,"skill_id":"%s","mode_runtime":%s}\n' "$(json_escape "$skill_id")" "$(mode_runtime_state_json)"
}

mr_mode_runtime_skill_install_response() {
  source_path=$(trim "$(param "source_path")")
  skill_id_raw=$(trim "$(param "skill_id")")
  replace_raw=$(trim "$(param "replace")")
  replace_existing=$(mr_bool_norm "$replace_raw")

  if [ -z "$source_path" ]; then
    printf '{"success":false,"error":"source_path is required"}\n'
    return 0
  fi
  if [ ! -d "$source_path" ]; then
    printf '{"success":false,"error":"source_path is not a directory"}\n'
    return 0
  fi

  skill_id=$skill_id_raw
  if [ -z "$skill_id" ]; then
    skill_id=$(basename "$source_path")
  fi
  skill_id=$(printf '%s' "$skill_id" | tr '[:upper:]' '[:lower:]')
  if ! valid_id "$skill_id"; then
    printf '{"success":false,"error":"invalid skill_id"}\n'
    return 0
  fi

  target_dir=$(mr_skill_dir_for "$skill_id")
  if mr_skill_exists "$skill_id" && [ "$replace_existing" != "1" ]; then
    printf '{"success":false,"error":"skill already exists (set replace=1 to overwrite)"}\n'
    return 0
  fi

  missing=""
  for required_file in policy.md trigger.yaml tools.json output.schema.json; do
    if [ ! -f "$source_path/$required_file" ]; then
      if [ -n "$missing" ]; then
        missing="$missing,$required_file"
      else
        missing="$required_file"
      fi
    fi
  done
  if [ -n "$missing" ]; then
    printf '{"success":false,"error":"source bundle is missing required files","missing":%s}\n' "$(mr_csv_to_json_array "$missing")"
    return 0
  fi

  source_policy="$source_path/policy.md"
  source_trigger="$source_path/trigger.yaml"
  source_tools="$source_path/tools.json"
  source_schema="$source_path/output.schema.json"

  skill_name=$(mr_skill_name_from_trigger_file "$source_trigger")
  trigger_text=$(mr_skill_trigger_from_trigger_file "$source_trigger")
  capabilities=$(mr_skill_caps_from_tools_file "$source_tools")
  description_text=$(mr_skill_description_from_policy_file "$source_policy")

  if [ -z "$skill_name" ]; then
    skill_name=$skill_id
  fi
  if [ -z "$trigger_text" ]; then
    trigger_text="when manually invoked"
  fi
  if [ -z "$capabilities" ]; then
    capabilities="filesystem"
  fi
  if [ -z "$description_text" ]; then
    description_text="Installed external skill bundle."
  fi

  if [ "$replace_existing" = "1" ] && [ -d "$target_dir" ]; then
    rm -rf "$target_dir"
  fi

  mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  cp "$source_policy" "$target_dir/policy.md"
  cp "$source_trigger" "$target_dir/trigger.yaml"
  cp "$source_tools" "$target_dir/tools.json"
  cp "$source_schema" "$target_dir/output.schema.json"

  meta_file=$(mr_skill_meta_file "$skill_id")
  {
    printf 'id=%s\n' "$skill_id"
    printf 'name=%s\n' "$(mr_sanitize_inline "$skill_name")"
    printf 'trigger=%s\n' "$(mr_sanitize_inline "$trigger_text")"
    printf 'capabilities=%s\n' "$(mr_csv_normalize "$capabilities")"
    printf 'description=%s\n' "$(mr_sanitize_inline "$description_text")"
    printf 'stateless=1\n'
    printf 'interrupt_authority=0\n'
  } > "$meta_file"

  printf '{"success":true,"skill_id":"%s","replaced":%s,"mode_runtime":%s}\n' \
    "$(json_escape "$skill_id")" \
    "$( [ "$replace_existing" = "1" ] && printf 'true' || printf 'false' )" \
    "$(mode_runtime_state_json)"
}
