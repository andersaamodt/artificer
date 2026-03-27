mr_skill_capabilities() {
  skill_id=$1
  meta_file=$(mr_skill_meta_file "$skill_id")
  mr_env_get "$meta_file" "capabilities" ""
}

mr_skill_artifact_targets_json() {
  skill_id=$1
  artifacts="policy.md,trigger.yaml,tools.json,output.schema.json"
  case "$skill_id" in
    shadow-documentation)
      artifacts="$artifacts,README.md,.architecture.md,.tasks/index.md"
      ;;
    dashboard-builder|panel-integrator)
      artifacts="$artifacts,dashboard/composites.md,telemetry/*.log"
      ;;
    proceduralization)
      artifacts="$artifacts,scripts/*.sh,runbook.md"
      ;;
    compliance-lookup|contract-analyzer)
      artifacts="$artifacts,compliance-notes.md"
      ;;
    codegen-infra-spin-up)
      artifacts="$artifacts,infrastructure/*,deployment-checklist.md"
      ;;
  esac
  mr_csv_to_json_array "$artifacts"
}

mr_skill_risk_gate() {
  input_text=$1
  input_lower=$(printf '%s' "$input_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$input_lower" | grep -Eq 'phish|malware|credential stuffing|ddos|ransomware|exploit( chain)?|spam campaign|bypass paywall|steal credentials|fraud'; then
    printf '%s' "blocked"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'contact real|email customers|cold outreach|post publicly|publish live|charge card|payment|register company|legal filing|file taxes|sign contract'; then
    printf '%s' "needs_auth"
    return 0
  fi
  printf '%s' "ok"
}

mr_skill_dynamic_step() {
  input_text=$1
  input_lower=$(printf '%s' "$input_text" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$input_lower" | grep -Eq 'deterministic|replay|checksum|regression|test'; then
    printf '%s' "Attach deterministic checks, replay criteria, and pass/fail thresholds"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'dashboard|panel|telemetry|metric'; then
    printf '%s' "Publish telemetry mapping and panel acceptance criteria"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'contract|legal|compliance|policy'; then
    printf '%s' "Capture obligations and map each to an enforceable control"
    return 0
  fi
  if printf '%s' "$input_lower" | grep -Eq 'market|customer|demand|competition|pricing'; then
    printf '%s' "Document evidence quality, confidence, and open uncertainty"
    return 0
  fi
  printf '%s' "Capture measurable acceptance criteria and explicit stop conditions"
}

mr_skill_actuator_output_json() {
  skill_id=$1
  mode_id=$2
  input_text=$3

  clean_input=$(mr_sanitize_inline "$input_text")
  [ -n "$clean_input" ] || clean_input="No explicit input provided."
  mode_focus=$(mr_mode_focus_text "$mode_id")
  risk_gate=$(mr_skill_risk_gate "$clean_input")
  governance_gate="none"
  status_value="ok"
  required_followup=false

  case "$risk_gate" in
    blocked)
      status_value="blocked"
      governance_gate="blocked"
      required_followup=true
      ;;
    needs_auth)
      status_value="needs_auth"
      governance_gate="approval_required"
      required_followup=true
      ;;
  esac

  actions=""
  case "$skill_id" in
    proceduralization)
      actions='Capture successful manual workflow; Normalize into reusable pipeline stages; Generate script/runbook template; Define regression guardrails for reuse'
      ;;
    grant-hunter)
      actions='Scan funding channels; Score opportunities by fit and effort; Draft submission skeleton with milestones; Generate dependency checklist'
      ;;
    negotiation-doppelganger)
      actions='Model counterpart positions; Build BATNA/threshold tree; Generate negotiation script variants; Identify concession boundaries'
      ;;
    devils-liquidity-provider)
      actions='Detect current stall point; Propose substitute execution path; Re-sequence queue to recover momentum; Define rollback route'
      ;;
    shadow-documentation)
      actions='Diff changed artifacts; Update README/ops notes; Refresh architecture map and task index; Add concise changelog entry'
      ;;
    latent-opportunity-harvester)
      actions='Run cross-domain scan; Surface complementarities and slack; Rank leverage opportunities; Emit shortlist with rationale'
      ;;
    dashboard-builder)
      actions='Define panel modules and contracts; Attach telemetry streams; Emit composable dashboard config; Add freshness/latency indicators'
      ;;
    agent-spawner)
      actions='Validate spawn scope and boundaries; Select agent template; Emit child-agent bootstrap contract; Define supervision and stop criteria'
      ;;
    panel-integrator)
      actions='Bind multi-agent feeds; Normalize metric taxonomy; Publish unified panel view; Add source lineage metadata'
      ;;
    compliance-lookup)
      actions='Locate governing constraints; Extract actionable obligations; Flag uncertainty and jurisdictional gaps; Propose control mapping'
      ;;
    report-synthesizer)
      actions='Collect distributed outputs; Build sectioned narrative; Emit concise recommendations; Add residual-risk and confidence section'
      ;;
    market-research)
      actions='Define market slice and hypotheses; Gather demand signals; Summarize competitor posture; Estimate confidence and unknowns'
      ;;
    contract-analyzer)
      actions='Parse contract clauses; Extract obligations and risk surfaces; Summarize red flags; Recommend mitigation follow-ups'
      ;;
    pitch-drafter)
      actions='Identify target audience; Tailor value narrative; Draft pitch variants; Align with likely objections'
      ;;
    data-etl)
      actions='Ingest source payload; Normalize schema and typing; Route transformed output; Emit data quality diagnostics'
      ;;
    web-scraper)
      actions='Fetch policy-approved sources; Extract target fields; Emit structured dataset; Log provenance and extraction quality'
      ;;
    simulation-runner)
      actions='Define scenario bounds and assumptions; Execute bounded simulations; Report outcome distributions; Highlight failure envelopes'
      ;;
    codegen-infra-spin-up)
      actions='Generate infrastructure scaffolds; Validate baseline configuration; Produce deployment checklist; Add rollback and observability stubs'
      ;;
    *)
      actions='Parse request; Execute bounded task; Emit structured output; Capture next-action handoff'
      ;;
  esac

  if [ "$risk_gate" = "blocked" ]; then
    actions='Refuse unsafe objective; Explain blocked safety category; Offer compliant alternatives; Request safe objective rewrite'
  fi
  if [ "$risk_gate" = "needs_auth" ]; then
    actions="$actions; Request explicit authorization before irreversible external actions"
  fi
  dynamic_step=$(mr_skill_dynamic_step "$clean_input")
  actions="$actions; $dynamic_step"
  actions_json=$(mr_csv_to_json_array "$(printf '%s' "$actions" | sed 's/;\s*/,/g')")

  bundle_health="complete"
  missing_files=""
  skill_dir=$(mr_skill_dir_for "$skill_id")
  for required_file in policy.md trigger.yaml tools.json output.schema.json; do
    if [ ! -f "$skill_dir/$required_file" ]; then
      bundle_health="partial"
      if [ -n "$missing_files" ]; then
        missing_files="$missing_files,$required_file"
      else
        missing_files="$required_file"
      fi
    fi
  done
  missing_json=$(mr_csv_to_json_array "$missing_files")

  confidence="0.82"
  if [ "$bundle_health" = "partial" ]; then
    confidence="0.68"
  fi
  if [ "$status_value" = "needs_auth" ]; then
    confidence="0.55"
  elif [ "$status_value" = "blocked" ]; then
    confidence="0.20"
  fi

  artifacts_json=$(mr_skill_artifact_targets_json "$skill_id")
  summary_text="Executed $skill_id under mode ${mode_id:-assistant} with focus on $mode_focus. Objective: $clean_input"
  if [ "$status_value" = "needs_auth" ]; then
    summary_text="Prepared bounded plan for $skill_id, but explicit authorization is required for irreversible external actions."
  elif [ "$status_value" = "blocked" ]; then
    summary_text="Blocked unsafe request for $skill_id and generated compliant alternatives."
  fi

  notes_text="Stateless run completed; scratch memory disposed. Governance gate=$governance_gate. Bundle health=$bundle_health."

  printf '{"skill_id":"%s","status":"%s","summary":"%s","actions":%s,"artifacts":%s,"mode_focus":"%s","governance_gate":"%s","bundle_health":"%s","missing_bundle_files":%s,"required_followup":%s,"confidence":"%s","notes":"%s"}' \
    "$(json_escape "$skill_id")" \
    "$(json_escape "$status_value")" \
    "$(json_escape "$summary_text")" \
    "$actions_json" \
    "$artifacts_json" \
    "$(json_escape "$mode_focus")" \
    "$(json_escape "$governance_gate")" \
    "$(json_escape "$bundle_health")" \
    "$missing_json" \
    "$required_followup" \
    "$(json_escape "$confidence")" \
    "$(json_escape "$notes_text")"
}

mr_skill_invoke_json() {
  mode_id=$1
  skill_id=$2
  input_text=$3
  requested_caps=$4

  if [ -z "$(trim "$mode_id")" ]; then
    mode_id="assistant"
  fi

  if ! mr_skill_exists "$skill_id"; then
    printf '{"success":false,"error":"skill not found"}'
    return 0
  fi

  skill_caps=$(mr_skill_capabilities "$skill_id")
  caps_to_check=$skill_caps
  if [ -n "$(trim "$requested_caps")" ]; then
    caps_to_check=$(mr_csv_normalize "$requested_caps")
  fi

  sensitive_caps=""
  old_ifs=$IFS
  IFS=','
  for cap in $caps_to_check; do
    clean=$(trim "$cap")
    [ -n "$clean" ] || continue
    case "$clean" in
      filesystem|network|agent_spawn)
        if [ -z "$sensitive_caps" ]; then
          sensitive_caps="$clean"
        else
          sensitive_caps="$sensitive_caps,$clean"
        fi
        ;;
    esac
  done
  IFS=$old_ifs

  if [ -n "$(trim "$sensitive_caps")" ]; then
    if [ "$mode_id" = "assistant" ]; then
      printf '{"success":false,"error":"mode authorization required for requested capabilities","required_capabilities":%s}' "$(mr_csv_to_json_array "$sensitive_caps")"
      return 0
    fi
    if ! mr_mode_exists "$mode_id"; then
      printf '{"success":false,"error":"mode not found for authorization"}'
      return 0
    fi
    if ! mr_mode_authorizes_capabilities "$mode_id" "$sensitive_caps"; then
      printf '{"success":false,"error":"mode policy does not authorize requested capabilities","requested_capabilities":%s,"allowed_capabilities":%s}' \
        "$(mr_csv_to_json_array "$sensitive_caps")" "$(mr_csv_to_json_array "$(mr_mode_allowed_capabilities "$mode_id")")"
      return 0
    fi
  fi

  invocation_id=$(new_id)
  invocation_dir="$(mr_bus_dir)/$invocation_id"
  scratch_dir="$invocation_dir/scratch"
  mkdir -p "$scratch_dir"

  request_file="$invocation_dir/request.txt"
  result_file="$invocation_dir/result.json"
  metadata_file="$invocation_dir/metadata.env"
  started_iso=$(mr_now_iso)

  {
    printf 'mode_id=%s\n' "$mode_id"
    printf 'skill_id=%s\n' "$skill_id"
    printf 'requested_capabilities=%s\n' "$(mr_csv_normalize "$caps_to_check")"
    printf 'started=%s\n' "$started_iso"
  } > "$metadata_file"

  printf '%s\n' "$input_text" > "$request_file"

  result_json=$(mr_skill_actuator_output_json "$skill_id" "$mode_id" "$input_text")
  printf '%s\n' "$result_json" > "$result_file"
  result_status=$(json_extract_string_field "status" "$result_json" || true)
  [ -n "$(trim "$result_status")" ] || result_status="ok"
  result_gate=$(json_extract_string_field "governance_gate" "$result_json" || true)
  [ -n "$(trim "$result_gate")" ] || result_gate="none"

  rm -rf "$scratch_dir"

  finished_iso=$(mr_now_iso)
  mr_env_set "$metadata_file" "finished" "$finished_iso"
  mr_env_set "$metadata_file" "scratch_disposed" "1"

  if [ "$mode_id" != "assistant" ] && mr_mode_exists "$mode_id"; then
    mode_events_file=$(mr_mode_event_queue_file "$mode_id")
    printf '%s\tinvocation=%s\tskill=%s\tstatus=%s\tgate=%s\n' "$finished_iso" "$invocation_id" "$skill_id" "$result_status" "$result_gate" >> "$mode_events_file"
  fi

  printf '{"success":true,"invocation":{"id":"%s","mode_id":"%s","skill_id":"%s","requested_capabilities":%s,"scratch_persistent":false,"started":"%s","finished":"%s"},"result":%s}' \
    "$(json_escape "$invocation_id")" \
    "$(json_escape "$mode_id")" \
    "$(json_escape "$skill_id")" \
    "$(mr_csv_to_json_array "$caps_to_check")" \
    "$(json_escape "$started_iso")" \
    "$(json_escape "$finished_iso")" \
    "$result_json"
}

