#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

runtime_loader="$repo_root/hosted-web/cgi/lib/runtime/40h-self-knowledge.sh"
registry_module="$repo_root/hosted-web/cgi/lib/runtime/self_knowledge/40h1-registry.sh"
state_module="$repo_root/hosted-web/cgi/lib/runtime/self_knowledge/40h2-state-and-prompts.sh"
workspace_runtime_loader="$repo_root/hosted-web/cgi/lib/40-workspace-runtime.sh"
action_file="$repo_root/hosted-web/cgi/actions/self_knowledge_state.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"
allow_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
appctl_file="$repo_root/hosted-web/scripts/artificer-appctl"

for file_path in "$runtime_loader" "$registry_module" "$state_module" "$workspace_runtime_loader" "$action_file" "$run_part_file" "$allow_file" "$appctl_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing self-knowledge runtime file: $file_path" >&2
    exit 1
  fi
done

if ! grep -q '40h-self-knowledge.sh' "$workspace_runtime_loader"; then
  printf '%s\n' "workspace runtime loader does not source self-knowledge runtime module" >&2
  exit 1
fi

if ! grep -q 'self_knowledge_reflexive_prompt_block' "$run_part_file"; then
  printf '%s\n' "run pipeline does not use self_knowledge_reflexive_prompt_block" >&2
  exit 1
fi

if ! grep -q 'artificer-appctl knowledge show' "$run_part_file"; then
  printf '%s\n' "run prompt guidance missing reflexive command: knowledge show" >&2
  exit 1
fi

if ! grep -q 'artificer-appctl knowledge teach --topic' "$run_part_file"; then
  printf '%s\n' "run prompt guidance missing reflexive command: knowledge teach" >&2
  exit 1
fi

if ! grep -q 'knowledge show' "$appctl_file"; then
  printf '%s\n' "artificer-appctl usage surface missing knowledge show" >&2
  exit 1
fi

if ! grep -q 'knowledge teach' "$appctl_file"; then
  printf '%s\n' "artificer-appctl usage surface missing knowledge teach" >&2
  exit 1
fi

if ! grep -q 'requested_topic' "$appctl_file"; then
  printf '%s\n' "artificer-appctl knowledge parsing is missing requested_topic handling" >&2
  exit 1
fi

if ! grep -q 'knowledge)' "$allow_file"; then
  printf '%s\n' "command allowlist missing artificer-appctl knowledge branch" >&2
  exit 1
fi

if ! grep -q 'REFLEXIVE_KNOWLEDGE' "$allow_file"; then
  printf '%s\n' "artificer-appctl knowledge branch is not gated by REFLEXIVE_KNOWLEDGE" >&2
  exit 1
fi

if ! grep -q 'self_knowledge_state_json' "$action_file"; then
  printf '%s\n' "self_knowledge_state action missing state response path" >&2
  exit 1
fi

if ! grep -q 'self_knowledge_teach_json' "$action_file"; then
  printf '%s\n' "self_knowledge_state action missing teach response path" >&2
  exit 1
fi

if ! grep -q 'llm-foundations' "$registry_module" || ! grep -q 'ollama-contributing' "$registry_module"; then
  printf '%s\n' "self-knowledge registry topics missing LLM/Ollama teaching tracks" >&2
  exit 1
fi

for parse_target in "$runtime_loader" "$registry_module" "$state_module" "$action_file"; do
  if ! sh -n "$parse_target"; then
    printf '%s\n' "shell parse failed for self-knowledge file: $parse_target" >&2
    exit 1
  fi
done

printf '%s\n' "ok self-knowledge introspection surface: runtime loader, API action, appctl commands, and reflexive gating are wired"
