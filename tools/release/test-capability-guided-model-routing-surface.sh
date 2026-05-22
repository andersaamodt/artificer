#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
routing_lib="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-001.sh"

if ! grep -Fq 'run_capability_autoroute_model() {' "$routing_lib"; then
  printf '%s\n' "routing library is missing capability-guided autoroute helper" >&2
  exit 1
fi

if ! grep -Fq 'model_preference_score_for_mode_with_capability_guidance() {' "$routing_lib"; then
  printf '%s\n' "routing library is missing capability-guided score helper" >&2
  exit 1
fi

if ! grep -Fq 'best_model_for_mode_with_capability_guidance() {' "$routing_lib"; then
  printf '%s\n' "routing library is missing capability-guided best-model selector" >&2
  exit 1
fi

if ! grep -Fq 'self_improve_capability_guidance_prompt_block "$run_mode" "$user_prompt"' "$run_part_file"; then
  printf '%s\n' "run bootstrap is missing capability guidance seeding before model routing" >&2
  exit 1
fi

if ! grep -Fq 'run_capability_autoroute_model "$model" "$run_mode" "$run_capability_guidance_seed_trace_json"' "$run_part_file"; then
  printf '%s\n' "run bootstrap is missing capability-guided model routing call" >&2
  exit 1
fi

if ! grep -Fq 'Auto-selected model for capability focus' "$run_part_file"; then
  printf '%s\n' "run bootstrap is missing capability-guided routing stream status" >&2
  exit 1
fi

printf '%s\n' "ok capability-guided model routing surface: benchmark guidance is seeded before run startup, used for model selection, and surfaced in stream status"
