#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
self_improve_lib="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-001.sh"
stream_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-003.sh"

if ! grep -Fq 'self_improve_capability_guidance_execution_profile_json() {' "$self_improve_lib"; then
  printf '%s\n' "self-improvement runtime is missing capability-guided execution profile helper" >&2
  exit 1
fi

if ! grep -Fq 'self_improve_capability_guidance_execution_profile_json "$run_capability_guidance_seed_trace_json" "$run_mode"' "$run_part_file"; then
  printf '%s\n' "run startup is missing capability-guided execution profile call" >&2
  exit 1
fi

if ! grep -Fq 'capability_execution_profile_summary' "$run_part_file"; then
  printf '%s\n' "run startup is missing capability-guided execution profile summary state" >&2
  exit 1
fi

if ! grep -Fq 'Benchmark-aware effort profile:' "$stream_part_file"; then
  printf '%s\n' "stream lifecycle is missing benchmark-aware effort profile status line" >&2
  exit 1
fi

printf '%s\n' "ok capability-guided effort profile surface: startup consumes execution profile guidance and stream lifecycle reports the resulting benchmark-aware effort profile"
