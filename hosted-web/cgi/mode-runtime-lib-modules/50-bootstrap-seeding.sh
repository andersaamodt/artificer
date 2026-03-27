mr_controller_variant_bootstrap_default() {
  default_id=$(mr_controller_variant_default_id)
  if mr_controller_variant_exists "$default_id"; then
    return 0
  fi
  default_dir=$(mr_controller_variant_dir_for "$default_id")
  mkdir -p "$default_dir"
  now_iso=$(mr_now_iso)
  default_guidance=$(mr_sanitize_inline "Baseline typed-state controller policy: keep deterministic section formatting, safe mediated commands, small verifiable steps, and concise user-facing synthesis.")
  default_meta=$(mr_controller_variant_meta_file "$default_id")
  {
    printf 'id=%s\n' "$default_id"
    printf 'name=%s\n' "Default controller baseline"
    printf 'status=active\n'
    printf 'kind=baseline\n'
    printf 'parent_id=\n'
    printf 'source_proposal=\n'
    printf 'scope=controller-loop\n'
    printf 'risk_level=low\n'
    printf 'created_at=%s\n' "$now_iso"
    printf 'updated_at=%s\n' "$now_iso"
    printf 'last_seen_at=\n'
    printf 'instructions=%s\n' "$default_guidance"
    printf 'runs=0\n'
    printf 'successes=0\n'
    printf 'avg_quality=0.000\n'
  } > "$default_meta"
  default_notes=$(mr_controller_variant_notes_file "$default_id")
  {
    printf '# Controller Variant: %s\n\n' "$default_id"
    printf 'Created: %s\n\n' "$now_iso"
    printf '## Guidance\n- %s\n' "$default_guidance"
  } > "$default_notes"
}

mr_mode_seed_rows() {
  cat <<'EOF_ROWS'
mastermind-agency-composer|Mastermind / Agency-Composer|9|900|1|Allocates and composes agencies, dashboards, and cross-mode orchestration.|queue,git,run_events,mode_runtime|filesystem,network,agent_spawn|agent-spawner,panel-integrator,dashboard-builder
continuity-of-intention|Continuity-of-Intention|8|600|1|Maintains cross-session teleological alignment and corrects execution drift.|queue,run_events,mode_runtime,assumptions|filesystem|proceduralization,shadow-documentation,report-synthesizer
semantic-watchtower|Semantic Watchtower|7|1200|1|Monitors domains for semantic drift and emergent conceptual bifurcations.|queue,git,run_events,mode_runtime|network|market-research,report-synthesizer,latent-opportunity-harvester
ethical-statutory-compliance|Ethical / Statutory Compliance|10|900|1|Tracks legal and platform constraints and gates risky action chains.|queue,run_events,compliance,mode_runtime|network,filesystem|compliance-lookup,contract-analyzer,report-synthesizer
reputation-thermostat|Reputation Thermostat|6|1500|1|Models signal dilution and tunes costly-signal thresholds dynamically.|queue,run_events,mode_runtime|network|market-research,pitch-drafter,report-synthesizer
failure-mode-simulator|Failure-Mode Simulator|7|1200|1|Evolves collapse scenarios and stress-tests systemic resilience.|queue,git,run_events,mode_runtime|filesystem|simulation-runner,report-synthesizer,devils-liquidity-provider
epistemic-calibration|Epistemic Calibration|6|1800|0|Tracks forecast accuracy and updates strategic priors longitudinally.|run_events,mode_runtime,telemetry|filesystem|report-synthesizer,simulation-runner
adversarial-red-team-twin|Adversarial Red-Team Twin|9|900|1|Attempts to falsify system designs and surfaces exploit strategies.|queue,git,run_events,mode_runtime|filesystem,network|contract-analyzer,simulation-runner,proceduralization
narrative-coherence-engine|Narrative Coherence Engine|5|1800|0|Harmonizes symbolic and terminological consistency across artifacts.|run_events,mode_runtime|filesystem|shadow-documentation,pitch-drafter,report-synthesizer
chrono-budgeter|Chrono-Budgeter|5|900|0|Allocates cognitive labor based on lagged ROI and queue pressure.|queue,run_events,mode_runtime|filesystem|devils-liquidity-provider,proceduralization,report-synthesizer
EOF_ROWS
}

mr_skill_seed_rows() {
  cat <<'EOF_ROWS'
proceduralization|Proceduralization|when manual success patterns repeat|filesystem|Observes repeatable workflows and codifies reusable scripts and runbooks.
grant-hunter|Grant-Hunter|when funding search is requested|network|Tracks funding opportunities and drafts submission-ready packages.
negotiation-doppelganger|Negotiation Doppelganger|when negotiation strategy is requested|filesystem|Simulates counterparties and generates BATNA trees.
devils-liquidity-provider|Devils Liquidity Provider|when execution stalls|filesystem|Injects substitute actions to unblock delivery.
shadow-documentation|Shadow Documentation|when implementation changes frequently|filesystem|Continuously maintains READMEs and architecture diagrams.
latent-opportunity-harvester|Latent Opportunity Harvester|when cross-domain synthesis is valuable|network|Scans for complementarities and latent slack opportunities.
dashboard-builder|Dashboard Builder|when telemetry needs visualization|filesystem|Builds modular synoptic dashboard definitions.
agent-spawner|Agent Spawner|when sub-agents are needed|agent_spawn,filesystem|Instantiates scoped child agents from templates.
panel-integrator|Panel Integrator|when multi-agent telemetry should unify|filesystem|Binds multi-agent telemetry streams into unified panels.
compliance-lookup|Compliance Lookup|when legal or policy checks are needed|network|Retrieves statutory and platform-policy constraints on demand.
report-synthesizer|Report Synthesizer|when structured reporting is needed|filesystem|Produces concise structured summaries from multi-agent outputs.
market-research|Market Research|when demand or competition scans are requested|network|Runs bounded demand and competitor analyses.
contract-analyzer|Contract Analyzer|when agreement risk review is needed|filesystem|Parses agreements for obligations and risk surfaces.
pitch-drafter|Pitch Drafter|when stakeholder narrative is needed|filesystem|Drafts tailored pitches for specific audiences.
data-etl|Data ETL|when data routing or ingestion is needed|filesystem,network|Ingests, normalizes, and routes structured or unstructured data.
web-scraper|Web-Scraper|when external stream extraction is needed|network|Extracts web data under policy constraints.
simulation-runner|Simulation Runner|when scenario analysis is requested|filesystem|Executes bounded scenario and stress simulations.
codegen-infra-spin-up|Codegen / Infra Spin-Up|when infrastructure artifacts are requested|filesystem,network,agent_spawn|Generates infrastructure code and deployment scaffolds.
EOF_ROWS
}

mr_mode_policy_template() {
  mode_name=$1
  mode_desc=$2
  cat <<EOF_POLICY
# $mode_name Policy

## Intent
$mode_desc

## Governance
- This Mode is stateful and acts as a governor.
- It may orchestrate Skills under explicit policy constraints.
- It maintains persistent goal-state and long-horizon memory in its namespace.
- It may emit interrupt requests when interrupt rights are enabled.

## Constraints
- Respect legal, ethical, and platform policy boundaries.
- Prefer reversible actions unless explicit authorization is present.
- Record every scheduler iteration in governance logs.
EOF_POLICY
}

mr_skill_policy_template() {
  skill_name=$1
  skill_desc=$2
  cat <<EOF_POLICY
# $skill_name

## Purpose
$skill_desc

## Skill Contract
- Stateless actuator: no long-term memory persistence.
- No interrupt authority.
- Bounded execution within declared tools and mode policy constraints.
- Inputs and outputs must conform to the declared schema.
EOF_POLICY
}

mr_seed_mode_bundle() {
  mode_id=$1
  mode_name=$2
  mode_priority=$3
  mode_cadence=$4
  mode_interrupt=$5
  mode_desc=$6
  mode_subscriptions=$7
  mode_caps=$8
  mode_skills=$9

  mode_dir=$(mr_mode_dir_for "$mode_id")
  manifest_file=$(mr_mode_manifest_file "$mode_id")
  state_file=$(mr_mode_state_file "$mode_id")
  policy_file=$(mr_mode_policy_file "$mode_id")
  memory_dir=$(mr_mode_memory_dir "$mode_id")

  mkdir -p "$mode_dir"
  mkdir -p "$memory_dir"

  if [ ! -f "$manifest_file" ]; then
    {
      printf 'id=%s\n' "$mode_id"
      printf 'name=%s\n' "$(mr_sanitize_inline "$mode_name")"
      printf 'description=%s\n' "$(mr_sanitize_inline "$mode_desc")"
      printf 'default_priority=%s\n' "$(mr_positive_int_or "$mode_priority" "5")"
      printf 'default_cadence_sec=%s\n' "$(mr_positive_int_or "$mode_cadence" "900")"
      printf 'default_interrupt_rights=%s\n' "$(mr_bool_norm "$mode_interrupt")"
      printf 'default_subscriptions=%s\n' "$(mr_csv_normalize "$mode_subscriptions")"
      printf 'allowed_capabilities=%s\n' "$(mr_csv_normalize "$mode_caps")"
      printf 'recommended_skills=%s\n' "$(mr_csv_normalize "$mode_skills")"
      printf 'memory_namespace=%s\n' "$mode_id"
    } > "$manifest_file"
  fi

  if [ ! -f "$state_file" ]; then
    enabled_default=0
    case "$mode_id" in
      continuity-of-intention|ethical-statutory-compliance)
        enabled_default=1
        ;;
    esac
    {
      printf 'enabled=%s\n' "$enabled_default"
      printf 'priority=%s\n' "$(mr_env_get "$manifest_file" "default_priority" "5")"
      printf 'cadence_sec=%s\n' "$(mr_env_get "$manifest_file" "default_cadence_sec" "900")"
      printf 'interrupt_rights=%s\n' "$(mr_env_get "$manifest_file" "default_interrupt_rights" "0")"
      printf 'allow_queue_injection=0\n'
      printf 'goal_state=\n'
      printf 'status=idle\n'
      printf 'drift_score=0.00\n'
      printf 'last_tick=0\n'
      printf 'next_tick=0\n'
      printf 'last_skill_plan=\n'
      printf 'last_directive_count=0\n'
      printf 'last_directive_emits=0\n'
      printf 'last_directive_summary=none\n'
    } > "$state_file"
  fi

  if [ ! -f "$policy_file" ]; then
    mr_mode_policy_template "$mode_name" "$mode_desc" > "$policy_file"
  fi

  goal_file=$(mr_mode_goal_file "$mode_id")
  if [ ! -f "$goal_file" ]; then
    cat > "$goal_file" <<'EOF_GOAL'
# Goal State

- Pending explicit objective.
EOF_GOAL
  fi

  long_horizon_file=$(mr_mode_long_horizon_file "$mode_id")
  if [ ! -f "$long_horizon_file" ]; then
    cat > "$long_horizon_file" <<'EOF_LONG'
# Long-Horizon Memory

EOF_LONG
  fi

  mode_log_file=$(mr_mode_log_file "$mode_id")
  if [ ! -f "$mode_log_file" ]; then
    cat > "$mode_log_file" <<'EOF_LOG'
# Mode Log

EOF_LOG
  fi

  subscriptions_file=$(mr_mode_subscriptions_file "$mode_id")
  if [ ! -f "$subscriptions_file" ]; then
    printf '%s\n' "$(mr_env_get "$manifest_file" "default_subscriptions" "queue,run_events,mode_runtime")" > "$subscriptions_file"
  fi

  governance_file=$(mr_mode_ledgers_file "$mode_id")
  if [ ! -f "$governance_file" ]; then
    cat > "$governance_file" <<'EOF_GOV'
# Governance Ledger

EOF_GOV
  fi

  mode_events=$(mr_mode_event_queue_file "$mode_id")
  if [ ! -f "$mode_events" ]; then
    : > "$mode_events"
  fi

  mode_inbox_file=$(mr_mode_directive_inbox_file "$mode_id")
  if [ ! -f "$mode_inbox_file" ]; then
    : > "$mode_inbox_file"
  fi
  mode_cursor_file=$(mr_mode_directive_cursor_file "$mode_id")
  if [ ! -f "$mode_cursor_file" ]; then
    printf '0\n' > "$mode_cursor_file"
  fi
}

mr_seed_skill_bundle() {
  skill_id=$1
  skill_name=$2
  trigger_text=$3
  capabilities=$4
  description_text=$5

  skill_dir=$(mr_skill_dir_for "$skill_id")
  mkdir -p "$skill_dir"

  policy_file="$skill_dir/policy.md"
  trigger_file="$skill_dir/trigger.yaml"
  tools_file="$skill_dir/tools.json"
  schema_file="$skill_dir/output.schema.json"
  meta_file=$(mr_skill_meta_file "$skill_id")

  if [ ! -f "$policy_file" ]; then
    mr_skill_policy_template "$skill_name" "$description_text" > "$policy_file"
  fi

  if [ ! -f "$trigger_file" ]; then
    cat > "$trigger_file" <<EOF_TRIGGER
id: $skill_id
name: "$skill_name"
trigger:
  - "$trigger_text"
mode_required: true
stateless: true
interrupt_authority: false
EOF_TRIGGER
  fi

  if [ ! -f "$tools_file" ]; then
    tools_json=$(mr_csv_to_json_array "$capabilities")
    cat > "$tools_file" <<EOF_TOOLS
{
  "tools": $tools_json,
  "requires_mode_authorization": true,
  "stateless": true,
  "interrupt_authority": false,
  "persistent_memory": false
}
EOF_TOOLS
  fi

  if [ ! -f "$schema_file" ]; then
    cat > "$schema_file" <<EOF_SCHEMA
{
  "\$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "$skill_name output",
  "type": "object",
  "required": ["skill_id", "status", "summary", "actions"],
  "properties": {
    "skill_id": { "type": "string", "const": "$skill_id" },
    "status": { "type": "string", "enum": ["ok", "blocked", "needs_auth"] },
    "summary": { "type": "string" },
    "actions": { "type": "array", "items": { "type": "string" } },
    "artifacts": { "type": "array", "items": { "type": "string" } },
    "notes": { "type": "string" }
  },
  "additionalProperties": true
}
EOF_SCHEMA
  fi

  if [ ! -f "$meta_file" ]; then
    {
      printf 'id=%s\n' "$skill_id"
      printf 'name=%s\n' "$(mr_sanitize_inline "$skill_name")"
      printf 'trigger=%s\n' "$(mr_sanitize_inline "$trigger_text")"
      printf 'capabilities=%s\n' "$(mr_csv_normalize "$capabilities")"
      printf 'description=%s\n' "$(mr_sanitize_inline "$description_text")"
      printf 'stateless=1\n'
      printf 'interrupt_authority=0\n'
    } > "$meta_file"
  fi
}

mr_seed_dashboards() {
  dashboard_root=$(mr_dashboard_dir)
  mkdir -p "$dashboard_root"
  composites_file="$dashboard_root/composites.md"
  if [ ! -f "$composites_file" ]; then
    cat > "$composites_file" <<'EOF_COMP'
# Composite Dashboards

- Reputation Monitoring Panel
- Grant / Income Panel
- Oracle / Intel Panel
- Global Dashboard
EOF_COMP
  fi
}

mode_runtime_bootstrap() {
  mkdir -p "$(mr_modes_dir)"
  mkdir -p "$(mr_skills_dir)"
  mkdir -p "$(mr_bus_dir)"
  mkdir -p "$(mr_directives_dir)"
  mkdir -p "$(mr_dashboard_dir)"
  mkdir -p "$(mr_scheduler_dir)"
  mkdir -p "$(mr_telemetry_dir)"
  mkdir -p "$(mr_interrupts_dir)"
  mkdir -p "$(mr_failure_taxonomy_dir)"
  mkdir -p "$(mr_improvement_proposals_dir)"
  mkdir -p "$(mr_controller_variants_root)"
  mkdir -p "$(mr_controller_variants_dir)"
  mkdir -p "$(mr_quality_scorecard_dir)"

  scheduler_state=$(mr_scheduler_state_file)
  if [ ! -f "$scheduler_state" ]; then
    {
      printf 'last_tick=0\n'
      printf 'last_tick_iso=\n'
      printf 'ticks=0\n'
      printf 'last_due_modes=0\n'
      printf 'last_injections=0\n'
      printf 'last_directives_received=0\n'
      printf 'last_directives_emitted=0\n'
      printf 'last_summary=Scheduler initialized\n'
    } > "$scheduler_state"
  fi

  cooperation_log=$(mr_cooperation_log_file)
  if [ ! -f "$cooperation_log" ]; then
    : > "$cooperation_log"
  fi

  failure_events_file=$(mr_failure_taxonomy_events_file)
  if [ ! -f "$failure_events_file" ]; then
    : > "$failure_events_file"
  fi

  failure_readme_file="$(mr_failure_taxonomy_dir)/README.md"
  if [ ! -f "$failure_readme_file" ]; then
    cat > "$failure_readme_file" <<'EOF_FAIL'
# Failure Taxonomy Store

- `events.tsv` stores normalized failure records from run loops.
- Rows are tab-separated: epoch, timestamp, category, surface, severity, mode, action, error, hypothesis, next-attempt.
- This store is read-only from the user UI and used to derive improvement proposals.
EOF_FAIL
  fi

  proposals_readme_file="$(mr_improvement_proposals_dir)/README.md"
  if [ ! -f "$proposals_readme_file" ]; then
    cat > "$proposals_readme_file" <<'EOF_PROP'
# Improvement Proposals Store

- Each proposal lives in `<proposal-id>/` with `meta.env` and `proposal.md`.
- Proposals are manually reviewed and manually applied from the UI.
- This subsystem does not auto-edit execution pipelines.
EOF_PROP
  fi

  controller_state_file=$(mr_controller_variants_state_file)
  if [ ! -f "$controller_state_file" ]; then
    {
      printf 'active_variant_id=%s\n' "$(mr_controller_variant_default_id)"
      printf 'previous_active_variant_id=\n'
      printf 'sample_rate_percent=35\n'
      printf 'max_sample_size=40\n'
      printf 'sample_min_runs_for_promotion=6\n'
      printf 'updated_at=%s\n' "$(mr_now_iso)"
    } > "$controller_state_file"
  fi

  controller_telemetry_file=$(mr_controller_variants_telemetry_file)
  if [ ! -f "$controller_telemetry_file" ]; then
    : > "$controller_telemetry_file"
  fi

  controller_readme_file="$(mr_controller_variants_root)/README.md"
  if [ ! -f "$controller_readme_file" ]; then
    cat > "$controller_readme_file" <<'EOF_CTRL'
# Controller Variants Store

- `variants/<variant-id>/meta.env` stores versioned controller prompt-variant metadata and quality aggregates.
- `variants/<variant-id>/guidance.md` stores human-readable variant intent.
- `state.env` stores active/previous variant ids plus A/B sampling configuration.
- `telemetry.tsv` stores run-level quality telemetry for before/after comparison.
EOF_CTRL
  fi

  quality_entries_file=$(mr_quality_scorecard_entries_file)
  if [ ! -f "$quality_entries_file" ]; then
    : > "$quality_entries_file"
  fi
  quality_cooldowns_file=$(mr_quality_scorecard_regression_cooldowns_file)
  if [ ! -f "$quality_cooldowns_file" ]; then
    : > "$quality_cooldowns_file"
  fi

  quality_readme_file="$(mr_quality_scorecard_dir)/README.md"
  if [ ! -f "$quality_readme_file" ]; then
    cat > "$quality_readme_file" <<'EOF_SCORE'
# Quality Scorecard Store

- `entries.tsv` stores run-level intelligence quality snapshots and deltas.
- `scorecard.md` stores a human-readable summary of trends and recent runs.
- `regression-proposal-cooldowns.tsv` stores per-mode cooldown state that prevents repeated proposal spam.
- Regressions can trigger manually-reviewable improvement proposals tagged to recent failure categories.
EOF_SCORE
  fi

  mr_controller_variant_bootstrap_default
  mr_quality_scorecard_refresh_markdown >/dev/null 2>&1 || true

  mr_mode_seed_rows | while IFS='|' read -r mode_id mode_name mode_priority mode_cadence mode_interrupt mode_desc mode_subscriptions mode_caps mode_skills; do
    [ -n "$mode_id" ] || continue
    mr_seed_mode_bundle "$mode_id" "$mode_name" "$mode_priority" "$mode_cadence" "$mode_interrupt" "$mode_desc" "$mode_subscriptions" "$mode_caps" "$mode_skills"
  done

  mr_skill_seed_rows | while IFS='|' read -r skill_id skill_name trigger_text capabilities description_text; do
    [ -n "$skill_id" ] || continue
    mr_seed_skill_bundle "$skill_id" "$skill_name" "$trigger_text" "$capabilities" "$description_text"
  done

  mr_seed_dashboards
}

