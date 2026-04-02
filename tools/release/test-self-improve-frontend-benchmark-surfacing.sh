#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
render_file="$repo_root/hosted-web/static/artificer-app-modules/06-queue-and-automation.js"

[ -f "$render_file" ] || {
  printf '%s\n' "missing self-improvement UI source: $render_file" >&2
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

if ! grep -q 'summaryParts.push("Weak families: " + weakFamilies.join(" | "));' "$render_file"; then
  printf '%s\n' "self-improvement summary is missing weak-family copy" >&2
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

printf '%s\n' "ok self-improve frontend benchmark surfacing: summary and plugin cards expose benchmark recommendation, weak families, and plugin promotion metadata"
