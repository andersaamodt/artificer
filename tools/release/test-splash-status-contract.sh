#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
index_file="$repo_root/index.html"

[ -f "$index_file" ] || {
  printf '%s\n' "missing startup page: $index_file" >&2
  exit 1
}

if ! grep -q '<p class="boot-subtitle">Preparing local runtime</p>' "$index_file"; then
  printf '%s\n' "splash boot subtitle is missing expected stable text" >&2
  exit 1
fi

if grep -q 'Still preparing local runtime' "$index_file"; then
  printf '%s\n' "splash should not switch to delayed "'"'Still preparing local runtime'"'" status" >&2
  exit 1
fi

if grep -q 'bootRevealTimer' "$index_file"; then
  printf '%s\n' "legacy delayed splash status timer should be removed" >&2
  exit 1
fi

if ! grep -q 'setTimeout(boot, 20);' "$index_file"; then
  printf '%s\n' "startup boot kickoff timer missing" >&2
  exit 1
fi

printf '%s\n' "ok splash status contract: stable preparing message with no delayed swap text"
