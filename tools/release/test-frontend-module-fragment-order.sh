#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

modules_dir="$repo_root/hosted-web/static/artificer-app-modules"
bundle_file="$repo_root/hosted-web/static/artificer-app.js"
runtime_entry="$repo_root/hosted-web/pages/index.html"
expected_max_lines=2600

if [ ! -d "$modules_dir" ]; then
  printf '%s\n' "missing modules directory: $modules_dir" >&2
  exit 1
fi

module_list_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-modules.XXXXXX")
declared_list_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-declared-modules.XXXXXX")
bundle_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-bundle-check.XXXXXX")
trap 'rm -f "$module_list_tmp" "$declared_list_tmp" "$bundle_tmp"' EXIT INT TERM

find "$modules_dir" -maxdepth 1 -type f -name '*.js' | sort > "$module_list_tmp"
awk '
  /var modules = \[/ { in_modules=1; next }
  in_modules && /\];/ { in_modules=0; next }
  in_modules {
    line=$0
    gsub(/^[[:space:]]+/, "", line)
    gsub(/[[:space:]]+$/, "", line)
    sub(/,$/, "", line)
    if (line ~ /^".*"$/) {
      sub(/^"/, "", line)
      sub(/"$/, "", line)
      print line
    }
  }
' "$runtime_entry" | sort > "$declared_list_tmp"

if [ ! -s "$module_list_tmp" ]; then
  printf '%s\n' "no frontend modules found in $modules_dir" >&2
  exit 1
fi
if [ ! -s "$declared_list_tmp" ]; then
  printf '%s\n' "no frontend runtime module declarations found in $runtime_entry" >&2
  exit 1
fi

fragment_count=$(grep -c '/0[1-8]b-' "$module_list_tmp" || true)
if [ "$fragment_count" -lt 8 ]; then
  printf '%s\n' "expected split continuation fragments for 01..08 modules" >&2
  exit 1
fi

runtime_paths_tmp=$(mktemp "${TMPDIR:-/tmp}/artificer-runtime-module-paths.XXXXXX")
trap 'rm -f "$module_list_tmp" "$declared_list_tmp" "$bundle_tmp" "$runtime_paths_tmp"' EXIT INT TERM
awk -v dir="$modules_dir" '{ print dir "/" $0 }' "$declared_list_tmp" > "$runtime_paths_tmp"
if ! cmp -s "$runtime_paths_tmp" "$module_list_tmp"; then
  printf '%s\n' "declared runtime module list in $runtime_entry does not match modules on disk" >&2
  printf '%s\n' "declared:" >&2
  cat "$runtime_paths_tmp" >&2
  printf '%s\n' "actual:" >&2
  cat "$module_list_tmp" >&2
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
