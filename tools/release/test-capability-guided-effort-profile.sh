#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
self_improve_lib="$repo_root/hosted-web/cgi/lib/10-self-improve.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

ARTIFICER_SCRIPT_DIR="$repo_root/hosted-web/cgi" \
. "$self_improve_lib"

report_trace='{"summary":"research_integration (sustained worsening external-baseline gap; critical)","items":[{"id":"research_integration","reason":"sustained worsening external-baseline gap; critical","guidance":"Separate evidence from inference."}],"count":1}'
report_profile=$(self_improve_capability_guidance_execution_profile_json "$report_trace" "report")
report_reasoning=$(ARTIFICER_GUIDANCE_JSON=$report_profile python3 - <<'PY'
import json
import os
payload = json.loads(os.environ["ARTIFICER_GUIDANCE_JSON"])
print(payload.get("reasoning_effort_floor", ""))
print(payload.get("min_iterations", 0))
print(payload.get("summary", ""))
PY
)
report_reasoning_floor=$(printf '%s\n' "$report_reasoning" | sed -n '1p')
report_min_iterations=$(printf '%s\n' "$report_reasoning" | sed -n '2p')
report_summary=$(printf '%s\n' "$report_reasoning" | sed -n '3p')
[ "$report_reasoning_floor" = "extra-high" ] || fail "report profile should escalate sustained worsening research gaps to extra-high reasoning"
[ "$report_min_iterations" = "11" ] || fail "report profile should raise sustained worsening critical research gaps to 11 iterations"
printf '%s\n' "$report_summary" | grep -Fq "research_integration" || fail "report profile summary should mention research_integration"

programming_trace='{"summary":"coding_mutation (measured weak family; critical)","items":[{"id":"coding_mutation","reason":"measured weak family; critical","guidance":"Work in bounded verifiable slices."}],"count":1}'
programming_profile=$(self_improve_capability_guidance_execution_profile_json "$programming_trace" "programming")
programming_values=$(ARTIFICER_GUIDANCE_JSON=$programming_profile python3 - <<'PY'
import json
import os
payload = json.loads(os.environ["ARTIFICER_GUIDANCE_JSON"])
print(payload.get("reasoning_effort_floor", ""))
print(payload.get("min_iterations", 0))
PY
)
programming_reasoning_floor=$(printf '%s\n' "$programming_values" | sed -n '1p')
programming_min_iterations=$(printf '%s\n' "$programming_values" | sed -n '2p')
[ "$programming_reasoning_floor" = "high" ] || fail "programming profile should keep coding mutation at least high reasoning"
[ "$programming_min_iterations" = "7" ] || fail "programming profile should raise critical coding mutation work to 7 iterations"

chat_profile=$(self_improve_capability_guidance_execution_profile_json "$report_trace" "chat")
chat_values=$(ARTIFICER_GUIDANCE_JSON=$chat_profile python3 - <<'PY'
import json
import os
payload = json.loads(os.environ["ARTIFICER_GUIDANCE_JSON"])
print(payload.get("reasoning_effort_floor", ""))
print(payload.get("min_iterations", 0))
PY
)
chat_reasoning_floor=$(printf '%s\n' "$chat_values" | sed -n '1p')
chat_min_iterations=$(printf '%s\n' "$chat_values" | sed -n '2p')
[ -z "$chat_reasoning_floor" ] || fail "chat profile should stay empty to avoid blowing up lightweight conversational runs"
[ "$chat_min_iterations" = "0" ] || fail "chat profile should not request extra iterations"

printf '%s\n' "ok capability-guided effort profile: measured weak-family traces can raise reasoning floor and iteration minima for substantive runs without inflating lightweight chat"
