#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

index_file="$repo_root/hosted-web/pages/index.md"
render_file="$repo_root/hosted-web/static/artificer-app-src/04-dictation-wave.js"
tree_file="$repo_root/hosted-web/static/artificer-app-src/03-ui-and-rendering.js"
events_file="$repo_root/hosted-web/static/artificer-app-src/08-event-bindings-and-boot.js"
style_file="$repo_root/hosted-web/static/style.css"

for file_path in "$index_file" "$render_file" "$tree_file" "$events_file" "$style_file"; do
  if [ ! -f "$file_path" ]; then
    printf '%s\n' "missing required file: $file_path" >&2
    exit 1
  fi
done

if ! grep -q 'id="sidebar-nav-automations-item"' "$index_file"; then
  printf '%s\n' "automations nav item missing from hosted-web/pages/index.md" >&2
  exit 1
fi

if grep -q 'id="sidebar-section-switch"' "$index_file"; then
  printf '%s\n' "legacy automations/threads pill switch still present in hosted-web/pages/index.md" >&2
  exit 1
fi

if ! grep -q "state.sidebarSection === \"automations\"" "$render_file"; then
  printf '%s\n' "automations sidebar branch missing from render logic" >&2
  exit 1
fi

if ! grep -q "automations-main-view" "$render_file"; then
  printf '%s\n' "automations right-pane view markup missing from render logic" >&2
  exit 1
fi

if grep -q "function renderAutomationsTree" "$tree_file"; then
  printf '%s\n' "legacy automations-in-workspace-tree renderer still present" >&2
  exit 1
fi

if ! grep -q "on(el.sidebarNavAutomationsItem, \"click\"" "$events_file"; then
  printf '%s\n' "automations nav click binding missing" >&2
  exit 1
fi

if ! grep -q "data-action='open-threads'" "$events_file"; then
  printf '%s\n' "chat log automations action routing missing open-threads" >&2
  exit 1
fi

if ! grep -q '^\s*\.sidebar-nav-item' "$style_file"; then
  printf '%s\n' "sidebar nav item styles missing" >&2
  exit 1
fi

printf '%s\n' "ok automations pane layout: left nav item drives right-pane automations view"
