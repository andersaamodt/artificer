#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
action_file="$repo_root/hosted-web/cgi/actions/add_workspace.sh"
index_file="$repo_root/hosted-web/pages/index.md"
browse_file="$repo_root/hosted-web/static/artificer-app-modules/07b-settings-and-actions-tail.js"

for file_path in "$action_file" "$index_file" "$browse_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  fi
done

if ! grep -q 'case "$expanded_path" in' "$action_file"; then
  printf '%s\n' "add_workspace action missing expanded path normalization block" >&2
  exit 1
fi

if ! grep -q '"~/"\*)' "$action_file"; then
  printf '%s\n' "add_workspace action missing ~/ expansion case" >&2
  exit 1
fi

if ! grep -q 'expanded_path=$HOME/${expanded_path#~/}' "$action_file"; then
  printf '%s\n' "add_workspace action missing HOME-based ~/ expansion" >&2
  exit 1
fi

if ! grep -q 'if \[ ! -d "$expanded_path" \]; then' "$action_file"; then
  printf '%s\n' "add_workspace action still validates raw path instead of expanded path" >&2
  exit 1
fi

if ! grep -q 'canonical_path=$(cd "$expanded_path" && pwd -P)' "$action_file"; then
  printf '%s\n' "add_workspace action must canonicalize expanded path" >&2
  exit 1
fi

cancel_line=$(grep -n 'id="workspace-cancel-btn"' "$index_file" | sed -n '1p' | cut -d: -f1)
add_line=$(grep -n 'id="workspace-add-submit"' "$index_file" | sed -n '1p' | cut -d: -f1)
if [ -z "$cancel_line" ] || [ -z "$add_line" ]; then
  printf '%s\n' "workspace modal actions missing required buttons" >&2
  exit 1
fi
if [ "$cancel_line" -ge "$add_line" ]; then
  printf '%s\n' "workspace modal action order should be Cancel then Add Project" >&2
  exit 1
fi

if ! grep -q 'apiGet("pick_workspace", {}, { timeoutMs: 900000 })' "$browse_file"; then
  printf '%s\n' "workspace browse picker should use an extended timeout for native folder selection" >&2
  exit 1
fi

if ! grep -q 'picked.path || picked.workspace_path || picked.selected_path' "$browse_file"; then
  printf '%s\n' "workspace browse picker should accept canonical and alias path keys from picker response" >&2
  exit 1
fi

printf '%s\n' "ok add workspace supports ~/ paths and modal action order is cancel then add"
