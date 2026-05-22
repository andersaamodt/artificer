run_part_modules_dir="${ARTIFICER_SCRIPT_DIR}/actions/run_parts/run-part-004-modules"

for run_part_module in "$run_part_modules_dir"/[0-9][0-9]-*.sh; do
  [ -f "$run_part_module" ] || continue
  # shellcheck disable=SC1090
  . "$run_part_module"
done
