#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

mode_loader="$repo_root/hosted-web/cgi/mode-runtime-lib.sh"
mode_modules_dir="$repo_root/hosted-web/cgi/mode-runtime-lib-modules"
reasoning_loader="$repo_root/hosted-web/cgi/lib/reasoning/30c-reasoning-contracts.sh"
reasoning_modules_dir="$repo_root/hosted-web/cgi/lib/reasoning/30c-reasoning-contracts-modules"
run_part_loader="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004.sh"
run_part_modules_dir="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules"

for path in "$mode_loader" "$reasoning_loader" "$run_part_loader" "$mode_modules_dir" "$reasoning_modules_dir" "$run_part_modules_dir"; do
  if [ ! -e "$path" ]; then
    printf '%s\n' "missing backend modular runtime path: $path" >&2
    exit 1
  fi
done

if ! grep -q 'mode-runtime-lib-modules' "$mode_loader"; then
  printf '%s\n' "mode runtime loader does not source modular directory" >&2
  exit 1
fi
if ! grep -q '30c-reasoning-contracts-modules' "$reasoning_loader"; then
  printf '%s\n' "reasoning contracts loader does not source modular directory" >&2
  exit 1
fi
if ! grep -q 'run-part-004-modules' "$run_part_loader"; then
  printf '%s\n' "run-part-004 loader does not source modular directory" >&2
  exit 1
fi

count_numbered_modules() {
  find "$1" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | wc -l | tr -d ' '
}

mode_count=$(count_numbered_modules "$mode_modules_dir")
reasoning_count=$(count_numbered_modules "$reasoning_modules_dir")
run_part_count=$(count_numbered_modules "$run_part_modules_dir")

if [ "$mode_count" -lt 2 ] || [ "$reasoning_count" -lt 2 ] || [ "$run_part_count" -lt 2 ]; then
  printf '%s\n' "expected modular backend splits (mode=$mode_count reasoning=$reasoning_count run_part=$run_part_count)" >&2
  exit 1
fi

for module in \
  "$mode_loader" \
  "$reasoning_loader" \
  "$run_part_loader" \
  "$mode_modules_dir"/[0-9][0-9]-*.sh \
  "$reasoning_modules_dir"/[0-9][0-9]-*.sh \
  "$run_part_modules_dir"/[0-9][0-9]-*.sh
do
  [ -f "$module" ] || continue
  if ! sh -n "$module"; then
    printf '%s\n' "shell parse failed for modular runtime file: $module" >&2
    exit 1
  fi
done

if ! ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" sh -c '
  . "$1"
  mode_runtime_root="/tmp/mode-runtime-root"
  [ "$(mr_runtime_root)" = "/tmp/mode-runtime-root" ]
' _ "$mode_loader"; then
  printf '%s\n' "mode runtime loader did not expose expected core helpers" >&2
  exit 1
fi

if ! ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" sh -c '
  . "$1"
  sample=$(printf "%s\n%s\n%s\n%s\n" "Outcome:" "Verification Evidence:" "Risks:" "Next Improvement:")
  assay_output_has_required_sections "$sample"
' _ "$reasoning_loader"; then
  printf '%s\n' "reasoning loader did not expose contract helper functions" >&2
  exit 1
fi

printf '%s\n' "ok backend modular loaders: canonical loaders, numbered modules, and helper exposure validated"
