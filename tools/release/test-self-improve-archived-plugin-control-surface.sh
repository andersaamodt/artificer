#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
render_file="$repo_root/hosted-web/static/artificer-app-modules/06-queue-and-automation.js"
events_file="$repo_root/hosted-web/static/artificer-app-modules/08-event-bindings-and-boot.js"
run_action_file="$repo_root/hosted-web/cgi/actions/self_improve_run.sh"
restore_action_file="$repo_root/hosted-web/cgi/actions/self_improve_archived_plugin_restore.sh"
delete_action_file="$repo_root/hosted-web/cgi/actions/self_improve_archived_plugin_delete.sh"
lib_file="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

if ! grep -q "function normalizeSelfImproveArchivedPlugins(value)" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived plugin normalization" >&2
  exit 1
fi

if ! grep -q "Archived plugins" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived plugin section copy" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-archived-plugin-restore'" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived restore control" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-archived-plugin-delete'" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived delete control" >&2
  exit 1
fi

if ! grep -q 'state.selfImproveArchivedPlugins = normalizeSelfImproveArchivedPlugins(response.archived_plugins);' "$render_file"; then
  printf '%s\n' "self-improvement settings load is missing archived plugin hydration" >&2
  exit 1
fi

if ! grep -q 'state.selfImproveArchivedPlugins = normalizeSelfImproveArchivedPlugins(response.archived_plugins || state.selfImproveArchivedPlugins);' "$render_file"; then
  printf '%s\n' "self-improvement run response handling is missing archived plugin hydration" >&2
  exit 1
fi

if ! grep -q "function restoreSelfImproveArchivedPlugin(archiveEntryId)" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived plugin restore helper" >&2
  exit 1
fi

if ! grep -q "function deleteSelfImproveArchivedPlugin(archiveEntryId)" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing archived plugin delete helper" >&2
  exit 1
fi

if ! grep -q "self-improve-archived-plugin-restore" "$events_file"; then
  printf '%s\n' "settings modal click handler is missing archived restore events" >&2
  exit 1
fi

if ! grep -q "self-improve-archived-plugin-delete" "$events_file"; then
  printf '%s\n' "settings modal click handler is missing archived delete events" >&2
  exit 1
fi

if ! grep -q "archive_entry_id=\$(trim \"\$(param \"archive_entry_id\")\")" "$restore_action_file"; then
  printf '%s\n' "archived restore action is missing archive_entry_id parameter handling" >&2
  exit 1
fi

if ! grep -q "archive_entry_id=\$(trim \"\$(param \"archive_entry_id\")\")" "$delete_action_file"; then
  printf '%s\n' "archived delete action is missing archive_entry_id parameter handling" >&2
  exit 1
fi

if ! grep -q "self_improve_archived_plugins_json()" "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing archived plugin listing helper" >&2
  exit 1
fi

if ! grep -q "self_improve_archived_plugin_restore_json()" "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing archived plugin restore helper" >&2
  exit 1
fi

if ! grep -q "self_improve_archived_plugin_delete_json()" "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing archived plugin delete helper" >&2
  exit 1
fi

if ! grep -q '"archived_plugins":%s' "$run_action_file"; then
  printf '%s\n' "self-improvement run action is missing archived plugin payload" >&2
  exit 1
fi

if ! grep -q '"archived_plugins":%s' "$lib_file"; then
  printf '%s\n' "self-improvement settings payload is missing archived plugin data" >&2
  exit 1
fi

printf '%s\n' "ok self-improve archived plugin control surface: archived plugin list, restore/delete controls, actions, event handlers, and backend helpers are wired"
