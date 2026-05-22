#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

shell_targets() {
  printf '%s\n' "$repo_root/artificer"
  find "$repo_root/hosted-web/cgi" "$repo_root/tools" "$repo_root/scripts" -type f -name '*.sh' | sort
}

if ! command -v checkbashisms >/dev/null 2>&1; then
  printf '%s\n' "checkbashisms is required but not installed" >&2
  exit 1
fi

file_list=$(mktemp "${TMPDIR:-/tmp}/artificer-shell-lint.XXXXXX")
trap 'rm -f "$file_list"' EXIT INT HUP TERM
shell_targets > "$file_list"
if [ ! -s "$file_list" ]; then
  printf '%s\n' "no shell files found for linting" >&2
  exit 1
fi

while IFS= read -r file_path; do
  [ -f "$file_path" ] || continue
  sh -n "$file_path"
  if head -n 1 "$file_path" | grep -q '^#!/bin/sh'; then
    checkbashisms -f -x "$file_path"
  fi
done < "$file_list"

printf '%s\n' "ok shell lint passed (sh -n + checkbashisms)"
