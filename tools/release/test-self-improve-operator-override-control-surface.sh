#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
render_file="$repo_root/hosted-web/static/artificer-app-modules/06-queue-and-automation.js"
events_file="$repo_root/hosted-web/static/artificer-app-modules/08-event-bindings-and-boot.js"
action_file="$repo_root/hosted-web/cgi/actions/self_improve_plugin_set.sh"
lib_file="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

if ! grep -q "function saveSelfImprovePluginOverride(pluginId, operatorPolicy, operatorLock)" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing the operator override save helper" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-plugin-policy'" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing the manual policy control surface" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-plugin-lock'" "$render_file"; then
  printf '%s\n' "self-improvement UI is missing the lock control surface" >&2
  exit 1
fi

if ! grep -q "self-improve-plugin-policy" "$events_file"; then
  printf '%s\n' "settings modal change handler is missing self-improvement policy events" >&2
  exit 1
fi

if ! grep -q "self-improve-plugin-lock" "$events_file"; then
  printf '%s\n' "settings modal change handler is missing self-improvement lock events" >&2
  exit 1
fi

if ! grep -q 'operator_policy=$(trim "$(param "operator_policy")")' "$action_file"; then
  printf '%s\n' "self-improve plugin action is missing operator_policy parameter handling" >&2
  exit 1
fi

if ! grep -q 'operator_lock=$(trim "$(param "operator_lock")")' "$action_file"; then
  printf '%s\n' "self-improve plugin action is missing operator_lock parameter handling" >&2
  exit 1
fi

if ! grep -q "self_improve_plugin_set_json()" "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing the consolidated plugin-set helper" >&2
  exit 1
fi

if ! grep -q 'payload\["operator_policy"\] = normalize_operator_policy' "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing operator policy normalization" >&2
  exit 1
fi

if ! grep -q 'payload\["operator_lock"\] = bool(prior_payload.get("operator_lock", False))' "$lib_file"; then
  printf '%s\n' "self-improvement backend is missing lock carry-forward behavior" >&2
  exit 1
fi

printf '%s\n' "ok self-improve operator override control surface: UI controls, event handlers, action params, and backend override helper are wired"
