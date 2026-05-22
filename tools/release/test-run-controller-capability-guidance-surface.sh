#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"
self_improve_lib="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

if ! grep -Fq 'self_improve_capability_guidance_prompt_block "$run_mode" "$augmented_user_prompt"' "$run_part_file"; then
  printf '%s\n' "run controller is missing benchmark-aware capability guidance injection" >&2
  exit 1
fi

if ! grep -Fq 'compact_text_block "Runtime capability guidance"' "$run_part_file"; then
  printf '%s\n' "run controller is missing bounded compaction for capability guidance" >&2
  exit 1
fi

if ! grep -Fq 'Runtime capability guidance:' "$run_part_file"; then
  printf '%s\n' "run controller prompt is missing the runtime capability guidance section" >&2
  exit 1
fi

if ! grep -Fq 'self_improve_capability_guidance_prompt_block() {' "$self_improve_lib"; then
  printf '%s\n' "self-improvement runtime is missing the capability guidance helper" >&2
  exit 1
fi

if ! grep -Fq 'self_improve_capability_benchmark_summary_cached_json() {' "$self_improve_lib"; then
  printf '%s\n' "self-improvement runtime is missing cached capability benchmark summary access" >&2
  exit 1
fi

printf '%s\n' "ok run controller capability guidance surface: benchmark-aware helper, bounded compaction, and prompt section stay wired"
