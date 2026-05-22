#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

found=0
for test_script in "$script_dir"/test-*.sh; do
  [ -f "$test_script" ] || continue
  found=1
  printf '%s\n' "==> $(basename "$test_script")"
  sh "$test_script"
done

if [ "$found" -ne 1 ]; then
  printf '%s\n' "no release tests found in $script_dir" >&2
  exit 1
fi

printf '%s\n' "ok release test suite passed"
