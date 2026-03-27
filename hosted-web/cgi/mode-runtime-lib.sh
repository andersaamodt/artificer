#!/bin/sh

mode_runtime_modules_dir="${ARTIFICER_SCRIPT_DIR}/mode-runtime-lib-modules"

for mode_runtime_module in "$mode_runtime_modules_dir"/[0-9][0-9]-*.sh; do
  [ -f "$mode_runtime_module" ] || continue
  # shellcheck disable=SC1090
  . "$mode_runtime_module"
done
