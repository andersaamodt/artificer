#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

found=0

while IFS= read -r file_path; do
  [ -n "$file_path" ] || continue
  found=1
  if ! grep -q '^set -eu$' "$file_path"; then
    printf '%s\n' "missing set -eu in executable shell script: $file_path" >&2
    exit 1
  fi
done <<EOF_FILES
$(find "$repo_root" -path "$repo_root/.git" -prune -o -type f -perm -u+x -print | sort | while IFS= read -r candidate; do
  if head -n 1 "$candidate" | grep -q '^#!/bin/sh'; then
    printf '%s\n' "$candidate"
  fi
done)
EOF_FILES

if [ "$found" -ne 1 ]; then
  printf '%s\n' "no executable /bin/sh scripts found in repository" >&2
  exit 1
fi

printf '%s\n' "ok executable shell scripts enforce set -eu"
