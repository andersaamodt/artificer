#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

appctl_file="$repo_root/hosted-web/scripts/artificer-appctl"
allow_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"

for file_path in "$appctl_file" "$allow_file" "$run_part_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing self-actuation surface file: $file_path" >&2
    exit 1
  fi
done

for command_snippet in \
  'project list' \
  'project rename' \
  'project delete' \
  'thread list' \
  'thread archive' \
  'automation list' \
  'automation toggle' \
  'automation run-now' \
  'automation delete' \
  'self-actuation preview' \
  'self-actuation apply' \
  'self-actuation policy-get' \
  'self-actuation policy-set' \
  'self-actuation audit'
do
  if ! grep -q "$command_snippet" "$appctl_file"; then
    printf '%s\n' "artificer-appctl missing command surface: $command_snippet" >&2
    exit 1
  fi
done

for allow_snippet in \
  'project:add' \
  'project:list' \
  'project:rename' \
  'project:delete' \
  'thread:new' \
  'thread:list' \
  'thread:archive' \
  'automation:upsert' \
  'automation:list' \
  'automation:toggle' \
  'automation:run-now' \
  'automation:delete' \
  'self-actuation:preview' \
  'self-actuation:apply' \
  'self-actuation:policy-get' \
  'self-actuation:policy-set' \
  'self-actuation:audit'
do
  if ! grep -q "$allow_snippet" "$allow_file"; then
    printf '%s\n' "allowlist missing expanded self-actuation command branch: $allow_snippet" >&2
    exit 1
  fi
done

for workflow_snippet in \
  'project list --json' \
  'automation list --json' \
  'thread list --workspace-id <id> --json' \
  'self-actuation preview --operation <operation>' \
  'self-actuation apply --operation <operation> --confirm-token <token>' \
  'self-actuation policy-get' \
  'self-actuation policy-set --action <operation> --enabled <0|1>' \
  'self-actuation audit --limit <n>' \
  'project add|rename|delete' \
  'thread new|archive' \
  'automation upsert|toggle|run-now|delete'
do
  if ! grep -q "$workflow_snippet" "$run_part_file"; then
    printf '%s\n' "run prompt guidance missing self-actuation workflow line: $workflow_snippet" >&2
    exit 1
  fi
done

if ! grep -q 'self_actuation_gate' "$allow_file"; then
  printf '%s\n' "expanded self-actuation allowlist is not gated by self_actuation_gate" >&2
  exit 1
fi

for parse_target in "$appctl_file" "$allow_file"; do
  if ! sh -n "$parse_target"; then
    printf '%s\n' "shell parse failed for self-actuation surface file: $parse_target" >&2
    exit 1
  fi
done

printf '%s\n' "ok self-actuation command surface: list+mutate appctl commands, allowlist coverage, and guidance workflow are wired"
