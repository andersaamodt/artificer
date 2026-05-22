#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
workflow_file="$repo_root/.github/workflows/build-artificer.yml"
runner_script="tools/release/run-release-tests.sh"

if [ ! -f "$workflow_file" ]; then
  printf '%s\n' "missing workflow file: $workflow_file" >&2
  exit 1
fi

if [ ! -f "$repo_root/$runner_script" ]; then
  printf '%s\n' "missing release test runner: $runner_script" >&2
  exit 1
fi

runner_calls=$(grep -c "sh $runner_script" "$workflow_file" 2>/dev/null || printf '%s' "0")
if [ "$runner_calls" -lt 2 ]; then
  printf '%s\n' "workflow must invoke $runner_script in both build jobs (found $runner_calls)" >&2
  exit 1
fi

if grep -q "sh tools/release/test-" "$workflow_file"; then
  printf '%s\n' "workflow should call the centralized release test runner instead of hardcoded test entries" >&2
  exit 1
fi

printf '%s\n' "ok workflow runs centralized release test suite"
