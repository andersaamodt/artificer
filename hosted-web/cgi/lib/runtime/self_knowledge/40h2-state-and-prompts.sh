#!/bin/sh
set -eu

self_knowledge_gate_norm() {
  gate_value=$1
  default_value=$2

  if command -v normalize_reflexive_knowledge_value >/dev/null 2>&1; then
    normalized=$(normalize_reflexive_knowledge_value "$gate_value" 2>/dev/null || true)
    if [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
  fi
  if command -v normalize_self_actuation_value >/dev/null 2>&1; then
    normalized=$(normalize_self_actuation_value "$gate_value" 2>/dev/null || true)
    if [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
  fi

  case "$(printf '%s' "$gate_value" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on|enabled)
      printf '%s' "1"
      return 0
      ;;
    0|false|no|off|disabled)
      printf '%s' "0"
      return 0
      ;;
  esac

  printf '%s' "$default_value"
}

self_knowledge_runtime_snapshot_json() {
  runtime_site_data=$(get-site-data-dir "artificer")
  runtime_state_root=${ARTIFICER_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/artificer}
  runtime_assay_reports=${ARTIFICER_ASSAY_REPORTS_DIR:-$runtime_state_root/assay-reports}
  runtime_assay_runs=${ARTIFICER_ASSAY_RUNS_DIR:-$runtime_state_root/assay-runs}
  runtime_reflexive=$(self_knowledge_gate_norm "${REFLEXIVE_KNOWLEDGE:-0}" "0")
  runtime_self_actuation=$(self_knowledge_gate_norm "${SELF_ACTUATION:-0}" "0")
  runtime_workspace_count=0
  runtime_conversation_count=0
  runtime_automation_count=0
  runtime_model_count=0
  runtime_active_run_mode=${ARTIFICER_ACTIVE_RUN_MODE:-auto}

  if [ -d "$workspaces_dir" ]; then
    runtime_workspace_count=$(find "$workspaces_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    runtime_conversation_count=$(find "$workspaces_dir" -mindepth 3 -maxdepth 3 -type d -name '*' -path '*/conversations/*' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ -d "$automations_root" ]; then
    runtime_automation_count=$(find "$automations_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
  if command -v list_models_raw >/dev/null 2>&1; then
    runtime_model_count=$(list_models_raw 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  fi

  case "$runtime_workspace_count" in ""|*[!0-9]*) runtime_workspace_count=0 ;; esac
  case "$runtime_conversation_count" in ""|*[!0-9]*) runtime_conversation_count=0 ;; esac
  case "$runtime_automation_count" in ""|*[!0-9]*) runtime_automation_count=0 ;; esac
  case "$runtime_model_count" in ""|*[!0-9]*) runtime_model_count=0 ;; esac

  printf '{"site_data_dir":"%s","state_root":"%s","assay_reports_dir":"%s","assay_runs_dir":"%s","reflexive_knowledge":"%s","self_actuation":"%s","workspace_count":"%s","conversation_count":"%s","automation_count":"%s","model_count":"%s","active_run_mode":"%s"}' \
    "$(json_escape "$runtime_site_data")" \
    "$(json_escape "$runtime_state_root")" \
    "$(json_escape "$runtime_assay_reports")" \
    "$(json_escape "$runtime_assay_runs")" \
    "$(json_escape "$runtime_reflexive")" \
    "$(json_escape "$runtime_self_actuation")" \
    "$(json_escape "$runtime_workspace_count")" \
    "$(json_escape "$runtime_conversation_count")" \
    "$(json_escape "$runtime_automation_count")" \
    "$(json_escape "$runtime_model_count")" \
    "$(json_escape "$runtime_active_run_mode")"
}

self_knowledge_state_json() {
  requested_topic_raw=${1:-}
  requested_topic=$(self_knowledge_normalize_topic "$requested_topic_raw" 2>/dev/null || true)
  if [ -z "$requested_topic" ]; then
    requested_topic="overview"
  fi

  overview_text=$(self_knowledge_overview_text)
  gui_text=$(self_knowledge_gui_text)
  architecture_text=$(self_knowledge_architecture_text)
  llm_foundations_text=$(self_knowledge_llm_foundations_text)
  ollama_runtime_text=$(self_knowledge_ollama_runtime_text)
  ollama_contributing_text=$(self_knowledge_ollama_contributing_text)
  self_actuation_text=$(self_knowledge_self_actuation_text)
  selected_text=$(self_knowledge_topic_text "$requested_topic")
  summary_text=$(self_knowledge_summary_text)
  runtime_json=$(self_knowledge_runtime_snapshot_json)

  printf '{"success":true,"registry_version":"%s","summary":"%s","topics":%s,"requested_topic":"%s","selected_content":"%s","sections":{"overview":"%s","gui":"%s","architecture":"%s","llm_foundations":"%s","ollama_runtime":"%s","ollama_contributing":"%s","self_actuation":"%s"},"runtime":%s}' \
    "$(json_escape "$(self_knowledge_registry_version)")" \
    "$(json_escape "$summary_text")" \
    "$(self_knowledge_topics_json)" \
    "$(json_escape "$requested_topic")" \
    "$(json_escape "$selected_text")" \
    "$(json_escape "$overview_text")" \
    "$(json_escape "$gui_text")" \
    "$(json_escape "$architecture_text")" \
    "$(json_escape "$llm_foundations_text")" \
    "$(json_escape "$ollama_runtime_text")" \
    "$(json_escape "$ollama_contributing_text")" \
    "$(json_escape "$self_actuation_text")" \
    "$runtime_json"
}

self_knowledge_teach_json() {
  requested_topic_raw=${1:-}
  requested_topic=$(self_knowledge_normalize_topic "$requested_topic_raw" 2>/dev/null || true)
  if [ -z "$requested_topic" ]; then
    requested_topic="overview"
  fi
  topic_text=$(self_knowledge_topic_text "$requested_topic")
  summary_text=$(self_knowledge_summary_text)
  learning_goals_text=$(self_knowledge_topic_learning_goals_text "$requested_topic")
  misconceptions_text=$(self_knowledge_topic_misconceptions_text "$requested_topic")
  assessment_checks_text=$(self_knowledge_topic_assessment_checks_text "$requested_topic")
  practice_tasks_text=$(self_knowledge_topic_practice_tasks_text "$requested_topic")
  reference_paths_json=$(self_knowledge_topic_reference_paths_json "$requested_topic")

  printf '{"success":true,"registry_version":"%s","topic":"%s","summary":"%s","learning_goals":"%s","common_misconceptions":"%s","assessment_checks":"%s","practice_tasks":"%s","reference_paths":%s,"content":"%s"}' \
    "$(json_escape "$(self_knowledge_registry_version)")" \
    "$(json_escape "$requested_topic")" \
    "$(json_escape "$summary_text")" \
    "$(json_escape "$learning_goals_text")" \
    "$(json_escape "$misconceptions_text")" \
    "$(json_escape "$assessment_checks_text")" \
    "$(json_escape "$practice_tasks_text")" \
    "$reference_paths_json" \
    "$(json_escape "$topic_text")"
}

self_knowledge_reflexive_prompt_block() {
  cat <<'EOF'
Artificer reflexive knowledge is enabled.

Grounded knowledge topics (use these exact names):
- overview
- gui
- architecture
- llm-foundations
- ollama-runtime
- ollama-contributing
- self-actuation

Self-knowledge behavior contract:
- explain UI using exact labels shown in the GUI (for example: Automations, Threads, Default permissions, Reflexive knowledge, Self-actuation).
- explain architecture with concrete paths (frontend modules, CGI actions, runtime libs, queue/automation state).
- for LLM/Ollama teaching requests, teach progressively from fundamentals to contributor-level practice tasks.
- include learning goals, misconceptions, assessment checks, and practice tasks when teaching.
- for self-actuation teaching requests, explain preview/apply confirmation, policy scope, idempotency behavior, and audit interpretation.
- whenever detail confidence is uncertain, explicitly mark it as inferred and suggest verification steps.

Introspection commands available when needed:
- artificer-appctl knowledge show
- artificer-appctl knowledge teach --topic <overview|gui|architecture|llm-foundations|ollama-runtime|ollama-contributing|self-actuation>

Self-actuation command workflow:
1. read current state first:
   - artificer-appctl project list --json
   - artificer-appctl automation list --json
   - artificer-appctl thread list --workspace-id <id> --json
2. prefer orchestrated mutation planning:
   - artificer-appctl self-actuation preview --operation <operation> ... --json
3. apply only with returned confirmation token:
   - artificer-appctl self-actuation apply --operation <operation> --confirm-token <token> ... --json
4. inspect policy and audit trails when diagnosing blocked or unexpected mutations:
   - artificer-appctl self-actuation policy-get --json
   - artificer-appctl self-actuation audit --limit <n> --json
5. re-list and verify before further mutations.
EOF
}
