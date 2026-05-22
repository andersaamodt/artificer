#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
workflow_file="$repo_root/.github/workflows/lint-shell.yml"

if [ ! -f "$workflow_file" ]; then
  printf '%s\n' "missing shell lint workflow: $workflow_file" >&2
  exit 1
fi

if ! grep -q 'name: Shell Lint' "$workflow_file"; then
  printf '%s\n' "shell lint workflow name missing or incorrect" >&2
  exit 1
fi

if ! grep -q 'devscripts' "$workflow_file"; then
  printf '%s\n' "shell lint workflow must install checkbashisms dependency (devscripts)" >&2
  exit 1
fi

if ! grep -q 'sh tools/release/lint-shell.sh' "$workflow_file"; then
  printf '%s\n' "shell lint workflow must run tools/release/lint-shell.sh" >&2
  exit 1
fi

if ! grep -q 'sh tools/release/test-executable-shell-strict-mode.sh' "$workflow_file"; then
  printf '%s\n' "shell lint workflow must run shell safety checks" >&2
  exit 1
fi

printf '%s\n' "ok shell lint workflow: checkbashisms and safety checks are wired"
