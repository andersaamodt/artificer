#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

policy_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e4-policy-doc-vision-reasoning.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"

for file_path in "$policy_file" "$run_part_file"; do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing run-mode domain parity dependency: $file_path" >&2
    exit 1
  }
done

required_modes="
programming
pentest
security-audit
report
text-perfecter
gui-testing
assistant
auto
teacher
chat
instant
"

for mode_name in $required_modes; do
  if ! grep -Fq "    $mode_name)" "$policy_file"; then
    printf '%s\n' "run_mode_policy_instructions missing mode branch: $mode_name" >&2
    exit 1
  fi
done

policy_mode_list=$(awk '
  $0 ~ /^run_mode_policy_instructions\(\)/ { in_fn=1; next }
  in_fn && $0 ~ /^  esac$/ { exit }
  in_fn && $0 ~ /^    [a-z][a-z-]*\)/ {
    mode = $0
    sub(/^    /, "", mode)
    sub(/\).*/, "", mode)
    print mode
  }
' "$policy_file")
[ -n "$policy_mode_list" ] || {
  printf '%s\n' "failed to discover run mode branches in policy file" >&2
  exit 1
}

for mode_name in $policy_mode_list; do
  if ! grep -Fq "      $mode_name)" "$run_part_file"; then
    printf '%s\n' "run-part-004 missing run_mode_instruction branch: $mode_name" >&2
    exit 1
  fi
done

if ! grep -Fq 'programming|teacher|report|text-perfecter|assistant|auto|gui-testing|security-audit|pentest' "$run_part_file"; then
  printf '%s\n' "run-part-004 context budget parity missing adaptive/security expansion" >&2
  exit 1
fi

if ! grep -Fq 'security-audit|pentest)' "$run_part_file"; then
  printf '%s\n' "run-part-004 minimum context budget branch missing security-audit|pentest case" >&2
  exit 1
fi

if ! grep -Fq 'programming|teacher|assistant|auto|gui-testing)' "$run_part_file"; then
  printf '%s\n' "run-part-004 minimum context budget branch missing adaptive auto case" >&2
  exit 1
fi

for parse_target in "$policy_file" "$run_part_file"; do
  if ! sh -n "$parse_target"; then
    printf '%s\n' "shell parse failed for run-mode parity file: $parse_target" >&2
    exit 1
  fi
done

printf '%s\n' "ok run-mode domain parity: policy branches, run directives, and adaptive/security context budgets are synchronized"
