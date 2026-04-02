#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"
event_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
boot_file="$repo_root/hosted-web/static/artificer-app-modules/01-boot-and-storage.js"
merge_file="$repo_root/hosted-web/static/artificer-app-modules/02b-runtime-core-tail.js"
render_file="$repo_root/hosted-web/static/artificer-app-modules/03-ui-and-rendering.js"
api_sync_file="$repo_root/hosted-web/static/artificer-app-modules/05b-api-and-state-sync-tail.js"

if ! grep -Fq 'self_improve_capability_guidance_trace_json_from_block' "$run_part_file"; then
  printf '%s\n' "run pipeline is missing structured capability-guidance trace generation" >&2
  exit 1
fi

if ! grep -Fq 'Step $iteration capability focus:' "$run_part_file"; then
  printf '%s\n' "run stream is missing capability focus status copy" >&2
  exit 1
fi

if ! grep -Fq 'append_session_entry "$session_log_file" "capability guidance iteration $iteration"' "$run_part_file"; then
  printf '%s\n' "run session log is missing capability guidance entries" >&2
  exit 1
fi

if ! grep -Fq '"capability_guidance":%s' "$event_file"; then
  printf '%s\n' "run event JSON is missing capability_guidance field" >&2
  exit 1
fi

if ! grep -Fq 'normalizeCapabilityGuidanceTrace(event.capability_guidance)' "$boot_file"; then
  printf '%s\n' "frontend run-event normalization is missing capability guidance trace preservation" >&2
  exit 1
fi

if ! grep -Fq 'if (!merged.capability_guidance && fallback.capability_guidance) {' "$merge_file"; then
  printf '%s\n' "frontend run-event merge is missing capability guidance fallback preservation" >&2
  exit 1
fi

if ! grep -Fq "Capability Guidance" "$render_file"; then
  printf '%s\n' "run advanced trace rendering is missing capability guidance section" >&2
  exit 1
fi

if ! grep -Fq 'pendingEvent.capability_guidance = normalizeCapabilityGuidanceTrace(response.capability_guidance);' "$api_sync_file"; then
  printf '%s\n' "API sync is missing immediate capability guidance trace hydration" >&2
  exit 1
fi

printf '%s\n' "ok run event capability guidance surface: backend, state normalization, merge, API sync, and advanced trace rendering preserve benchmark-guidance traces"
