#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
render_file="$repo_root/hosted-web/static/artificer-app-modules/03-ui-and-rendering.js"
handlers_file="$repo_root/hosted-web/static/artificer-app-modules/07b-settings-and-actions-tail.js"
style_file="$repo_root/hosted-web/static/style.css"

for file_path in "$render_file" "$handlers_file" "$style_file"; do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  }
done

if grep -q 'workspace-drag-handle' "$render_file"; then
  printf '%s\n' "workspace rows should not render explicit drag handle controls" >&2
  exit 1
fi

if grep -q 'conversation-drag-handle' "$render_file"; then
  printf '%s\n' "conversation rows should not render explicit drag handle controls" >&2
  exit 1
fi

if ! grep -q "draggable='true' data-drag-type='workspace'" "$render_file"; then
  printf '%s\n' "workspace rows should remain draggable for manual project ordering" >&2
  exit 1
fi

if grep -q "data-drag-type='conversation'" "$render_file"; then
  printf '%s\n' "conversation rows should not be draggable in workspace tree" >&2
  exit 1
fi

if ! grep -q 'if (dragType !== "workspace") {' "$handlers_file"; then
  printf '%s\n' "dragstart handler must explicitly restrict drag operations to workspace rows" >&2
  exit 1
fi

if ! grep -q "event.target.closest(\"button, a, input, select, textarea, label, \[role='button'\]\")" "$handlers_file"; then
  printf '%s\n' "dragstart handler must block drag initiation from interactive controls" >&2
  exit 1
fi

if ! grep -q "\.workspace-row\[data-drag-type='workspace'\]" "$style_file"; then
  printf '%s\n' "workspace drag cursor style selector missing" >&2
  exit 1
fi

if ! grep -q 'cursor: grab;' "$style_file"; then
  printf '%s\n' "workspace drag surface should use grab cursor" >&2
  exit 1
fi

if ! grep -q 'cursor: grabbing;' "$style_file"; then
  printf '%s\n' "workspace drag active state should use grabbing cursor" >&2
  exit 1
fi

printf '%s\n' "ok workspace drag behavior: row-surface project drag with interactive-control exclusions"
