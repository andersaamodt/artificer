#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="current-ops-guidance-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"
DEFAULT_DOC_URL="https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for current-ops-guidance probe." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for current-ops-guidance probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: current-ops-guidance-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH] [--doc-url URL]

Runs a live bounded ops-guidance probe against a demo workspace and checks
whether Artificer can combine local state with current official operational
guidance into one concrete decision without editing files.
EOF_USAGE
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

post_api_json() {
  body=$1
  len=$(printf '%s' "$body" | wc -c | tr -d ' ')
  REQUEST_METHOD=POST CONTENT_LENGTH="$len" sh "$API_SCRIPT" <<EOF_BODY | tr -d '\r' | awk 'seen{print} /^$/{seen=1}'
$body
EOF_BODY
}

post_api_json_with_timeout() {
  body=$1
  timeout_sec=$2
  python3 - "$API_SCRIPT" "$timeout_sec" "$body" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
timeout_sec = float(sys.argv[2])
body = sys.argv[3]
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))

try:
    proc = subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout_sec,
        check=False,
    )
    raw = proc.stdout.decode().replace("\r", "")
    parts = raw.split("\n\n", 1)
    payload = parts[1] if len(parts) > 1 else raw
    payload = payload.strip()
    if payload:
      print(payload)
    else:
      print('{"__timed_out":false}')
except subprocess.TimeoutExpired:
    print('{"__timed_out":true}')
PY
}

delete_workspace_best_effort() {
  workspace_id=$1
  [ -n "$workspace_id" ] || return 0
  workspace_id_uri=$(uri "$workspace_id")
  python3 - "$API_SCRIPT" "$workspace_id_uri" <<'PY'
import os
import subprocess
import sys

api_script = sys.argv[1]
workspace_id_uri = sys.argv[2]
body = f"action=delete_workspace&workspace_id={workspace_id_uri}"
env = os.environ.copy()
env["REQUEST_METHOD"] = "POST"
env["CONTENT_LENGTH"] = str(len(body.encode()))
try:
    subprocess.run(
        ["sh", api_script],
        input=body.encode(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        timeout=12,
        check=False,
    )
except Exception:
    pass
PY
}

create_workspace_for_scenario() {
  scenario=$1
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/deploy"
  case "$scenario" in
    slow-start-api)
      cat > "$workspace_dir/deploy/api-deployment.yaml" <<'EOF_YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
        - name: api
          image: demo/api:latest
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
EOF_YAML
      cat > "$workspace_dir/bin/state-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'state_file=deploy/api-deployment.yaml'
printf '%s\n' 'state_issue=slow_start_liveness_kills'
printf '%s\n' 'state_startup_probe=missing'
printf '%s\n' 'state_liveness_initial_delay_seconds=5'
printf '%s\n' 'state_startup_p95_seconds=75'
printf '%s\n' 'state_shared_probe_path=/healthz'
EOF_SH
      ;;
    dependency-overload-api)
      cat > "$workspace_dir/deploy/api-deployment.yaml" <<'EOF_YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
        - name: api
          image: demo/api:latest
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
EOF_YAML
      cat > "$workspace_dir/bin/state-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'state_file=deploy/api-deployment.yaml'
printf '%s\n' 'state_issue=temporary_dependency_overload'
printf '%s\n' 'state_same_probe_path=1'
printf '%s\n' 'state_dependency=db-warmup'
printf '%s\n' 'state_symptom=liveness_restarts_under_overload'
printf '%s\n' 'state_shared_probe_path=/healthz'
EOF_SH
      ;;
    cache-warm-worker)
      cat > "$workspace_dir/deploy/worker-deployment.yaml" <<'EOF_YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
spec:
  template:
    spec:
      containers:
        - name: worker
          image: demo/worker:latest
          livenessProbe:
            httpGet:
              path: /ready
              port: 9090
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /ready
              port: 9090
            initialDelaySeconds: 5
EOF_YAML
      cat > "$workspace_dir/bin/state-check.sh" <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' 'state_file=deploy/worker-deployment.yaml'
printf '%s\n' 'state_issue=cache_warmup_slow_start'
printf '%s\n' 'state_startup_probe=missing'
printf '%s\n' 'state_liveness_initial_delay_seconds=5'
printf '%s\n' 'state_startup_p95_seconds=90'
printf '%s\n' 'state_shared_probe_path=/ready'
EOF_SH
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac
  chmod +x "$workspace_dir/bin/state-check.sh"
  cat > "$workspace_dir/README.md" <<EOF_README
# Current Ops Guidance Demo

Scenario: $scenario
Use ./bin/state-check.sh for local state and the current official guidance URL for grounding. Do not edit files.
EOF_README
}

label=$DEFAULT_LABEL
scenario="slow-start-api"
prompt_override=""
prompt_file=""
doc_url=$DEFAULT_DOC_URL
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --scenario)
      scenario=$2
      shift 2
      ;;
    --prompt)
      prompt_override=$2
      shift 2
      ;;
    --prompt-file)
      prompt_file=$2
      shift 2
      ;;
    --doc-url)
      doc_url=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("qwen2.5-coder:7b")) then "qwen2.5-coder:7b"
  elif ($m | index("mistral:7b")) then "mistral:7b"
  else ($m[0] // empty)
  end
')
[ -n "$model" ] || { echo "No installed models available; current-ops-guidance probe cannot run." >&2; exit 1; }

tmp_ws=$(mktemp -d)
baseline_dir=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws" "$baseline_dir"
}
trap cleanup EXIT INT TERM

create_workspace_for_scenario "$scenario" "$tmp_ws"
cp -R "$tmp_ws/." "$baseline_dir/"

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

default_prompt_text=$(cat <<'EOF_PROMPT'
Investigate this bounded current ops guidance question in the workspace. Use `./bin/state-check.sh` for local state and the current official guidance at __DOC_URL__. Do not edit files. Return exactly five lines starting with: Local State, Current Guidance, Operational Decision, Root Cause, Next Change.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
prompt_text=$(printf '%s' "$prompt_text" | sed "s|__DOC_URL__|$doc_url|g")

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=assistant&compute_budget=long&advanced_loop=1&max_iterations=6&stream_session=$(uri "$stream_session")"
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=170 post_api_json_with_timeout "$run_body" 95)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

state_check_ran=$(printf '%s' "$run_json" | jq -r '[.commands[]?.command // ""] | any(contains("bin/state-check.sh")) | if . then 1 else 0 end')
web_fetch_emitted=$(printf '%s\n' "$stream_text" | grep -q 'Quick-mode web fetch:' && printf '%s' "1" || printf '%s' "0")
workspace_unchanged=$(diff -qr "$baseline_dir" "$tmp_ws" >/dev/null 2>&1 && printf '%s' "1" || printf '%s' "0")
has_local_state=$(printf '%s\n' "$assistant_text" | grep -q '^Local State:' && printf '%s' "1" || printf '%s' "0")
has_current_guidance=$(printf '%s\n' "$assistant_text" | grep -q '^Current Guidance:' && printf '%s' "1" || printf '%s' "0")
has_operational_decision=$(printf '%s\n' "$assistant_text" | grep -q '^Operational Decision:' && printf '%s' "1" || printf '%s' "0")
has_root_cause=$(printf '%s\n' "$assistant_text" | grep -q '^Root Cause:' && printf '%s' "1" || printf '%s' "0")
has_next_change=$(printf '%s\n' "$assistant_text" | grep -q '^Next Change:' && printf '%s' "1" || printf '%s' "0")
mentions_repo_file=0
mentions_expected_one=0
mentions_expected_two=0

case "$scenario" in
  slow-start-api)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'deploy/api-deployment.yaml' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'startupProbe' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -qi 'liveness and readiness' && printf '%s' "1" || printf '%s' "0")
    ;;
  dependency-overload-api)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'deploy/api-deployment.yaml' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'readinessProbe' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -qi 'service endpoints' && printf '%s' "1" || printf '%s' "0")
    ;;
  cache-warm-worker)
    mentions_repo_file=$(printf '%s\n' "$assistant_text" | grep -q 'deploy/worker-deployment.yaml' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_one=$(printf '%s\n' "$assistant_text" | grep -q 'startupProbe' && printf '%s' "1" || printf '%s' "0")
    mentions_expected_two=$(printf '%s\n' "$assistant_text" | grep -qi 'slow starting containers' && printf '%s' "1" || printf '%s' "0")
    ;;
esac

stream_line_count=$(printf '%s\n' "$stream_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

status="fail"
if [ "$timed_out" -eq 0 ] && [ "$state_check_ran" -eq 1 ] && [ "$web_fetch_emitted" -eq 1 ] && [ "$workspace_unchanged" -eq 1 ] && [ "$has_local_state" -eq 1 ] && [ "$has_current_guidance" -eq 1 ] && [ "$has_operational_decision" -eq 1 ] && [ "$has_root_cause" -eq 1 ] && [ "$has_next_change" -eq 1 ] && [ "$mentions_repo_file" -eq 1 ] && [ "$mentions_expected_one" -eq 1 ] && [ "$mentions_expected_two" -eq 1 ]; then
  status="pass"
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"state_check_ran":%s,"web_fetch_emitted":%s,"workspace_unchanged":%s,"has_local_state":%s,"has_current_guidance":%s,"has_operational_decision":%s,"has_root_cause":%s,"has_next_change":%s,"mentions_repo_file":%s,"mentions_expected_one":%s,"mentions_expected_two":%s,"stream_line_count":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$state_check_ran" "$web_fetch_emitted" "$workspace_unchanged" "$has_local_state" "$has_current_guidance" "$has_operational_decision" "$has_root_cause" "$has_next_change" "$mentions_repo_file" "$mentions_expected_one" "$mentions_expected_two" "$stream_line_count" > "$json_file"

{
  printf '# Current Ops Guidance Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- `state-check.sh` ran: %s\n' "$state_check_ran"
  printf -- '- Web fetch emitted: %s\n' "$web_fetch_emitted"
  printf -- '- Workspace unchanged: %s\n' "$workspace_unchanged"
  printf -- '- Local State section: %s\n' "$has_local_state"
  printf -- '- Current Guidance section: %s\n' "$has_current_guidance"
  printf -- '- Operational Decision section: %s\n' "$has_operational_decision"
  printf -- '- Root Cause section: %s\n' "$has_root_cause"
  printf -- '- Next Change section: %s\n' "$has_next_change"
  printf -- '- Mentions state file: %s\n' "$mentions_repo_file"
  printf -- '- Mentions expected guidance one: %s\n' "$mentions_expected_one"
  printf -- '- Mentions expected guidance two: %s\n' "$mentions_expected_two"
  printf -- '- Stream lines: %s\n' "$stream_line_count"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = "pass" ]
