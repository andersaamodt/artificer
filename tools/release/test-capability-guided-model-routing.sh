#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
routing_lib="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

trim() {
  printf '%s' "${1-}" | awk '{ sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }'
}

list_models_raw() {
  cat <<'EOF'
qwen2.5:32b
deepseek-coder-v2:16b
mistral:latest
nomic-embed-text
EOF
}

list_models_from_workspace_data() {
  return 0
}

. "$routing_lib"

research_trace='{"summary":"research_integration (external gap)","items":[{"id":"research_integration","reason":"external gap","guidance":"use a strong general reasoning model for multi-source synthesis"}],"count":1}'
coding_trace='{"summary":"coding_mutation (weak family)","items":[{"id":"coding_mutation","reason":"weak family","guidance":"favor the strongest code-specialist model"}],"count":1}'
teaching_trace='{"summary":"teaching_reassessment (persistent gap)","items":[{"id":"teaching_reassessment","reason":"persistent gap","guidance":"favor the clearest explanatory model"}],"count":1}'

assistant_routed=$(run_capability_autoroute_model "deepseek-coder-v2:16b" "assistant" "$research_trace")
[ "$assistant_routed" = "qwen2.5:32b" ] || fail "assistant routing should prefer qwen for research-focused capability guidance"

programming_routed=$(run_capability_autoroute_model "qwen2.5:32b" "programming" "$coding_trace")
[ "$programming_routed" = "deepseek-coder-v2:16b" ] || fail "programming routing should prefer deepseek-coder for coding-focused capability guidance"

teacher_routed=$(run_capability_autoroute_model "deepseek-coder-v2:16b" "teacher" "$teaching_trace")
[ "$teacher_routed" = "qwen2.5:32b" ] || fail "teacher routing should move off a coder model for teaching-focused capability guidance"

stable_route=$(run_capability_autoroute_model "qwen2.5:32b" "assistant" "$research_trace")
[ -z "$stable_route" ] || fail "already-optimal model should not be rerouted"

printf '%s\n' "ok capability-guided model routing: measured family guidance steers assistant, teacher, and programming model selection toward better-matched models"
