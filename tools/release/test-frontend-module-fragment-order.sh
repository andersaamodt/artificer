#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

modules_dir="$repo_root/hosted-web/static/artificer-app-modules"
bundle_file="$repo_root/hosted-web/static/artificer-app.js"
expected_max_lines=2600

if [ ! -d "$modules_dir" ]; then
  printf '%s\n' "missing modules directory: $modules_dir" >&2
  exit 1
fi

module_list_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-modules.XXXXXX")
bundle_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-bundle-check.XXXXXX")
trap 'rm -f "$module_list_tmp" "$bundle_tmp"' EXIT INT TERM

find "$modules_dir" -maxdepth 1 -type f -name '*.js' | sort > "$module_list_tmp"

if [ ! -s "$module_list_tmp" ]; then
  printf '%s\n' "no frontend modules found in $modules_dir" >&2
  exit 1
fi

fragment_count=$(grep -c '/0[1-8]b-' "$module_list_tmp" || true)
if [ "$fragment_count" -lt 8 ]; then
  printf '%s\n' "expected split continuation fragments for 01..08 modules" >&2
  exit 1
fi

for module in $(cat "$module_list_tmp"); do
  lines=$(wc -l < "$module" | tr -d ' ')
  if [ "$lines" -gt "$expected_max_lines" ]; then
    printf '%s\n' "frontend module exceeds max line threshold ($expected_max_lines): $module ($lines)" >&2
    exit 1
  fi
  cat "$module" >> "$bundle_tmp"
done

sh "$repo_root/tools/build-artificer-app.sh" >/dev/null

if [ ! -s "$bundle_file" ]; then
  printf '%s\n' "frontend bundle missing after build: $bundle_file" >&2
  exit 1
fi

if ! cmp -s "$bundle_tmp" "$bundle_file"; then
  printf '%s\n' "frontend bundle content does not match sorted module concatenation" >&2
  exit 1
fi

printf '%s\n' "ok frontend module fragments: bounded file size and deterministic bundle order validated"
