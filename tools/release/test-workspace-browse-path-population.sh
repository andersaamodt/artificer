#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
handlers_file="$repo_root/hosted-web/static/artificer-app-modules/07b-settings-and-actions-tail.js"
events_file="$repo_root/hosted-web/static/artificer-app-modules/08-event-bindings-and-boot.js"

for file_path in "$handlers_file" "$events_file"; do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  }
done

if ! grep -q 'apiGet("pick_workspace", {}, { timeoutMs: 900000 })' "$handlers_file"; then
  printf '%s\n' "workspace browse API call must use extended timeout for native picker interactions" >&2
  exit 1
fi

if ! grep -q 'picked.path || picked.workspace_path || picked.selected_path' "$handlers_file"; then
  printf '%s\n' "workspace browse response should accept canonical and alias path keys" >&2
  exit 1
fi

if ! grep -q 'el.workspacePath.value = pickedPath;' "$handlers_file"; then
  printf '%s\n' "browse flow no longer writes chosen path into folder path field" >&2
  exit 1
fi

if ! grep -q 'updateWorkspaceNamePlaceholderFromPath(pickedPath);' "$handlers_file"; then
  printf '%s\n' "browse flow no longer updates project label placeholder from chosen folder" >&2
  exit 1
fi

if ! grep -q 'pickedPath = dirname(firstFile.path);' "$handlers_file"; then
  printf '%s\n' "directory picker fallback must derive folder path from selected file path" >&2
  exit 1
fi

if ! grep -q 'on(el.workspaceBrowseBtn, "click"' "$events_file"; then
  printf '%s\n' "workspace browse button click binding missing" >&2
  exit 1
fi

if ! grep -q 'on(el.workspaceDirPicker, "change"' "$events_file"; then
  printf '%s\n' "workspace directory picker change binding missing" >&2
  exit 1
fi

printf '%s\n' "ok workspace browse flow populates folder path and placeholder across picker paths"
