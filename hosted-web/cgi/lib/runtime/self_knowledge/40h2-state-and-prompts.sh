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

  printf '{"site_data_dir":"%s","state_root":"%s","assay_reports_dir":"%s","assay_runs_dir":"%s","reflexive_knowledge":"%s","self_actuation":"%s"}' \
    "$(json_escape "$runtime_site_data")" \
    "$(json_escape "$runtime_state_root")" \
    "$(json_escape "$runtime_assay_reports")" \
    "$(json_escape "$runtime_assay_runs")" \
    "$(json_escape "$runtime_reflexive")" \
    "$(json_escape "$runtime_self_actuation")"
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
  selected_text=$(self_knowledge_topic_text "$requested_topic")
  summary_text=$(self_knowledge_summary_text)
  runtime_json=$(self_knowledge_runtime_snapshot_json)

  printf '{"success":true,"registry_version":"%s","summary":"%s","topics":%s,"requested_topic":"%s","selected_content":"%s","sections":{"overview":"%s","gui":"%s","architecture":"%s","llm_foundations":"%s","ollama_runtime":"%s","ollama_contributing":"%s"},"runtime":%s}' \
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

  printf '{"success":true,"registry_version":"%s","topic":"%s","summary":"%s","content":"%s"}' \
    "$(json_escape "$(self_knowledge_registry_version)")" \
    "$(json_escape "$requested_topic")" \
    "$(json_escape "$summary_text")" \
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

Self-knowledge behavior contract:
- explain UI using exact labels shown in the GUI (for example: Automations, Threads, Default permissions, Reflexive knowledge, Self-actuation).
- explain architecture with concrete paths (frontend modules, CGI actions, runtime libs, queue/automation state).
- for LLM/Ollama teaching requests, teach progressively from fundamentals to contributor-level practice tasks.
- whenever detail confidence is uncertain, explicitly mark it as inferred and suggest verification steps.

Introspection commands available when needed:
- artificer-appctl knowledge show
- artificer-appctl knowledge teach --topic <overview|gui|architecture|llm-foundations|ollama-runtime|ollama-contributing>
EOF
}
