#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
benchmark_script="$repo_root/hosted-web/scripts/capability-benchmark-cycle.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

json_query() {
  payload=$1
  query=$2
  JSON_PAYLOAD=$payload JSON_QUERY=$query python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("JSON_PAYLOAD", ""))
query = os.environ.get("JSON_QUERY", "")
value = eval(query, {"__builtins__": {"len": len, "sorted": sorted, "sum": sum}}, {"data": payload})
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
elif value is None:
    print("")
else:
    print(str(value))
PY
}

require_contains() {
  haystack=$1
  needle=$2
  label=$3
  if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
    fail "$label (missing: $needle)"
  fi
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-capability-external-run.XXXXXX")
reports_dir="$tmp_root/reports"
mkdir -p "$reports_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

adapters_json=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" external-adapters)
[ "$(json_query "$adapters_json" 'data.get("adapter_count") >= 1')" = "true" ] || fail "external adapter registry should expose at least one adapter"
[ "$(json_query "$adapters_json" 'data["adapters"][0].get("adapter_id")')" = "mock-frontier" ] || fail "external adapter registry should expose mock-frontier"

plan_json=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" external-plan --adapter mock-frontier --label frontier-ref)
[ "$(json_query "$plan_json" 'data.get("adapter", {}).get("name")')" = "Mock Frontier Reference" ] || fail "external plan should expose adapter metadata"
[ "$(json_query "$plan_json" 'data.get("artifacts", {}).get("out_json", "").endswith("frontier-ref-mock-frontier-capability-benchmark-external-scorecard.json")')" = "true" ] || fail "external plan should expose default scorecard artifact path"
require_contains "$plan_json" "mock-capability-external-adapter.sh" "external plan should expose runner command"

run_paths=$(ARTIFICER_ASSAY_REPORTS_DIR="$reports_dir" sh "$benchmark_script" external-run --adapter mock-frontier --label frontier-ref)
run_json=$(printf '%s\n' "$run_paths" | sed -n '1p')
run_md=$(printf '%s\n' "$run_paths" | sed -n '2p')
[ -f "$run_json" ] || fail "external run scorecard json missing"
[ -f "$run_md" ] || fail "external run scorecard markdown missing"
run_payload=$(cat "$run_json")

[ "$(json_query "$run_payload" 'data.get("label")')" = "frontier-ref" ] || fail "external run should preserve adapter label"
[ "$(json_query "$run_payload" 'data.get("family_count")')" = "6" ] || fail "external run should emit a complete scorecard"
[ "$(json_query "$run_payload" 'data.get("recommendation")')" = "promote" ] || fail "external run should emit a promotable reference scorecard"
[ "$(json_query "$run_payload" 'data.get("totals", {}).get("overall_score")')" = "90.5" ] || fail "external run should emit the expected fixture score"

printf '%s\n' "ok capability benchmark external adapter run: registry-backed adapters can be listed, planned, and executed into valid external scorecards"
