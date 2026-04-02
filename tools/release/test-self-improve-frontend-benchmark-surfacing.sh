#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
render_file="$repo_root/hosted-web/static/artificer-app-modules/06-queue-and-automation.js"
run_action_file="$repo_root/hosted-web/cgi/actions/self_improve_run.sh"

[ -f "$render_file" ] || {
  printf '%s\n' "missing self-improvement UI source: $render_file" >&2
  exit 1
}

[ -f "$run_action_file" ] || {
  printf '%s\n' "missing self-improvement run action: $run_action_file" >&2
  exit 1
}

if ! grep -q 'capability_benchmark: {' "$render_file"; then
  printf '%s\n' "self-improvement last-run normalization is missing capability benchmark state" >&2
  exit 1
fi

if ! grep -q 'promotionState !== "priority" && promotionState !== "candidate" && promotionState !== "hold"' "$render_file"; then
  printf '%s\n' "self-improvement plugin normalization is missing canonical promotion-state handling" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Capability benchmark: " + benchmarkSummary.latest_recommendation);' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing benchmark recommendation copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Latest compare: " + benchmarkSummary.compare_recommendation + (benchmarkSummary.candidate_promotable ? " (promotable)" : ""));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing benchmark compare recommendation copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Compare cycles: " + String(Number(benchmarkSummary.compare_count || 0)));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing compare-count copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Active plugins: " + String(pluginInventory.active_count));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing active-plugin inventory copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Archived stale plugins: " + String(pluginInventory.archived_auto_stale_count));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing archived stale-plugin copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Weak families: " + weakFamilies.join(" | "));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing weak-family copy" >&2
  exit 1
fi

if ! grep -q 'summaryParts.push("Recovered families: " + recoveredFamilies.join(" | "));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing recovered-family copy" >&2
  exit 1
fi

if ! grep -q "<strong>Benchmark families:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark family rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Active benchmark gaps:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing active benchmark gap rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Recovered compare hits:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing recovered compare-hit rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Weak compare hits:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing weak compare-hit rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Operator policy:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing operator-policy rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Automatic benchmark state:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing automatic benchmark-state rendering" >&2
  exit 1
fi

if ! grep -q "<strong>Benchmark history:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark history rendering" >&2
  exit 1
fi

if ! grep -q 'metadataBits.push("adoption " + plugin.adoption_state);' "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing adoption-state metadata" >&2
  exit 1
fi

if ! grep -q 'metadataBits.push("streak " + String(plugin.benchmark_success_streak));' "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark streak metadata" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-plugin-policy'" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing manual policy control" >&2
  exit 1
fi

if ! grep -q "data-action='self-improve-plugin-lock'" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing lock control" >&2
  exit 1
fi

if ! grep -q 'metadataBits.push("benchmark " + plugin.promotion_state);' "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark promotion-state metadata" >&2
  exit 1
fi

if ! grep -q 'metadataBits.push("alignment " + String(plugin.benchmark_alignment_score));' "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark alignment metadata" >&2
  exit 1
fi

if ! grep -q "<strong>Benchmark rationale:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing benchmark rationale copy" >&2
  exit 1
fi

if ! grep -q "<strong>Adoption rationale:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing adoption rationale copy" >&2
  exit 1
fi

if ! grep -q "<strong>Automatic benchmark rationale:</strong>" "$render_file"; then
  printf '%s\n' "self-improvement plugin cards are missing automatic benchmark rationale copy" >&2
  exit 1
fi

if ! grep -q 'state.selfImprovePluginInventory = normalizeSelfImprovePluginInventory(response.plugin_inventory);' "$render_file"; then
  printf '%s\n' "self-improvement settings load is missing plugin inventory hydration" >&2
  exit 1
fi

if ! grep -q '"plugin_inventory":%s' "$run_action_file"; then
  printf '%s\n' "self-improvement run action is missing plugin inventory in its response payload" >&2
  exit 1
fi

printf '%s\n' "ok self-improve frontend benchmark surfacing: summary and plugin cards expose benchmark recommendation, weak families, and plugin promotion metadata"
