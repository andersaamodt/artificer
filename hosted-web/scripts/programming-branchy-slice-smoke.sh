#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_FIXTURES="$SITE_ROOT/tests/fixtures/artificer-programming-branchy-slice-smoke.tsv"
DEFAULT_LABEL="programming-branchy-slice-smoke"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for programming branchy slice smoke." >&2
  exit 1
fi

usage() {
  cat <<EOF_USAGE
Usage: programming-branchy-slice-smoke.sh [--label NAME] [--fixtures FILE]

Runs a live CGI smoke against quick multi-step programming runs and checks branch-aware slice narrowing.
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

line_count_non_empty() {
  printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

file_changed_flag() {
  baseline_dir=$1
  workspace_dir=$2
  rel_path=$3
  if [ ! -e "$baseline_dir/$rel_path" ] && [ -e "$workspace_dir/$rel_path" ]; then
    printf '%s' "1"
    return 0
  fi
  if [ -e "$baseline_dir/$rel_path" ] && [ -e "$workspace_dir/$rel_path" ] && ! cmp -s "$baseline_dir/$rel_path" "$workspace_dir/$rel_path"; then
    printf '%s' "1"
    return 0
  fi
  printf '%s' "0"
}

append_non_empty_line() {
  existing_text=$1
  next_line=$2
  if [ -z "$next_line" ]; then
    printf '%s' "$existing_text"
  elif [ -z "$existing_text" ]; then
    printf '%s' "$next_line"
  else
    printf '%s\n%s' "$existing_text" "$next_line"
  fi
}

clone_workspace_snapshot() {
  source_dir=$1
  target_dir=$2
  mkdir -p "$target_dir"
  cp -R "$source_dir/." "$target_dir/"
}

replace_workspace_prompt_placeholders() {
  prompt_text=$1
  source_workspace_id=$2
  source_workspace_name=$3
  source_workspace_path=$4
  current_workspace_id=$5
  current_workspace_name=$6
  current_workspace_path=$7
  python3 - "$prompt_text" "$source_workspace_id" "$source_workspace_name" "$source_workspace_path" "$current_workspace_id" "$current_workspace_name" "$current_workspace_path" <<'PY'
import sys

text = sys.argv[1]
replacements = {
    "__SOURCE_WORKSPACE_ID__": sys.argv[2],
    "__SOURCE_WORKSPACE_NAME__": sys.argv[3],
    "__SOURCE_WORKSPACE_PATH__": sys.argv[4],
    "__CURRENT_WORKSPACE_ID__": sys.argv[5],
    "__CURRENT_WORKSPACE_NAME__": sys.argv[6],
    "__CURRENT_WORKSPACE_PATH__": sys.argv[7],
}
for key, value in replacements.items():
    text = text.replace(key, value)
print(text, end="")
PY
}

create_fixture_workspace() {
  workspace_shape=$(printf '%s' "${1-js}" | tr '[:upper:]' '[:lower:]')
  workspace_dir=$2
  mkdir -p "$workspace_dir/bin" "$workspace_dir/tests"
  case "$workspace_shape" in
    python)
      cat > "$workspace_dir/calc.py" <<'EOF_APP'
def greet(name):
    return "hello " + name
EOF_APP
      cat > "$workspace_dir/bin/calc.py" <<'EOF_APP'
#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from calc import greet

print(greet(sys.argv[1] if len(sys.argv) > 1 else "world"))
EOF_APP
      cat > "$workspace_dir/tests/calc_test.sh" <<'EOF_APP'
#!/bin/sh
set -eu
python3 - <<'PY'
from calc import greet
if greet('sam') != 'hello sam':
    raise SystemExit(1)
PY
EOF_APP
      cat > "$workspace_dir/README.md" <<'EOF_APP'
# Calc Tool

Small Python greeting helper for quick local experiments.
EOF_APP
      ;;
    shell)
      cat > "$workspace_dir/greet.sh" <<'EOF_APP'
#!/bin/sh
name=${1:-world}
printf '%s\n' "hello $name"
EOF_APP
      cat > "$workspace_dir/bin/greet.sh" <<'EOF_APP'
#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
exec sh "$ROOT_DIR/greet.sh" "$@"
EOF_APP
      cat > "$workspace_dir/tests/greet_test.sh" <<'EOF_APP'
#!/bin/sh
set -eu
default_output=$(sh "./bin/greet.sh")
[ "$default_output" = "hello world" ]
EOF_APP
      cat > "$workspace_dir/README.md" <<'EOF_APP'
# Greet Tool

Small shell greeting helper for quick local experiments.
EOF_APP
      ;;
    *)
      cat > "$workspace_dir/app.js" <<'EOF_APP'
function greet(name) {
  return 'hello ' + name;
}
module.exports = { greet };
EOF_APP
      cat > "$workspace_dir/bin/cli.js" <<'EOF_APP'
#!/usr/bin/env node
const { greet } = require('../app');
const name = process.argv[2] || 'world';
console.log(greet(name));
EOF_APP
      cat > "$workspace_dir/tests/greet.test.sh" <<'EOF_APP'
#!/bin/sh
set -eu
node -e "const { greet } = require('./app'); if (greet('sam') !== 'hello sam') process.exit(1)"
EOF_APP
      cat > "$workspace_dir/README.md" <<'EOF_APP'
# Greeting Tool

Small greeting helper for quick local experiments.
EOF_APP
      ;;
  esac
}

label=$DEFAULT_LABEL
fixtures_file=$DEFAULT_FIXTURES
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --fixtures)
      fixtures_file=$2
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

[ -f "$fixtures_file" ] || { echo "Fixture file not found: $fixtures_file" >&2; exit 1; }

if [ "${ARTIFICER_PROGRAMMING_BRANCHY_SMOKE_SINGLE:-0}" != "1" ]; then
  mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
  tsv_file="$OUT_DIR/$label.tsv"
  json_file="$OUT_DIR/$label.json"
  md_file="$OUT_DIR/$label.md"
  tab=$(printf '\t')
  printf 'task_id\tstatus\ttimed_out\tline_count\thas_outcome\thas_files\thas_verify\thas_risks\thas_next\thas_required_phrase\thas_required_risk_phrase\thas_required_next_phrase\thas_required_file_change\thas_required_secondary_change\thas_required_tertiary_change\thas_required_quaternary_change\thas_required_quinary_change\trequired_content_present\tforbidden_pattern_absent\tno_filler\tstream_line_count\tstream_clean\tstream_useful\tstream_fast_start\tstream_has_narrowing\tstream_has_patch_ok\tclean_verify_finish\tverify_command_anchor_present\tfirst_progress_line\tassistant_excerpt\n' > "$tsv_file"

  total=0
  passes=0
  results_json=""
  first_json=1
  header_line=$(sed -n '1p' "$fixtures_file")

  while IFS= read -r fixture_row <&3 || [ -n "$fixture_row" ]; do
    [ -n "$fixture_row" ] || continue
    [ "$fixture_row" = "$header_line" ] && continue
    task_id=$(printf '%s\n' "$fixture_row" | awk -F '\t' '{print $1}')
    task_id=$(printf '%s' "$task_id" | tr -d '\r')
    [ -n "$task_id" ] || continue
    total=$((total + 1))

    row_fixture=$(mktemp)
    printf '%s\n%s\n' "$header_line" "$fixture_row" > "$row_fixture"
    child_label="${label}-${task_id}"
    child_exit_code=0
    if ! ARTIFICER_PROGRAMMING_BRANCHY_SMOKE_SINGLE=1 sh "$0" --label "$child_label" --fixtures "$row_fixture" </dev/null >/dev/null; then
      child_exit_code=$?
    fi
    rm -f "$row_fixture"

    child_json="$OUT_DIR/$child_label.json"
    if [ ! -f "$child_json" ]; then
      child_excerpt="missing child report (exit=$child_exit_code)"
      child_tsv_line=$(printf '%s\tfail\t1\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t0\t0\t0\t0\t0\t0\t999\t%s' "$task_id" "$child_excerpt")
      printf '%s\n' "$child_tsv_line" >> "$tsv_file"
      child_result_json=$(jq -nc \
        --arg task_id "$task_id" \
        --arg excerpt "$child_excerpt" \
        --argjson exit_code "$child_exit_code" \
        '{
          task_id: $task_id,
          status: "fail",
          timed_out: 1,
          line_count: 0,
          has_outcome: 0,
          has_files: 0,
          has_verify: 0,
          has_risks: 0,
          has_next: 0,
          has_required_phrase: 0,
          has_required_risk_phrase: 0,
          has_required_next_phrase: 0,
          has_required_file_change: 0,
          has_required_secondary_change: 0,
          has_required_tertiary_change: 0,
          has_required_quaternary_change: 0,
          has_required_quinary_change: 0,
          required_content_present: 0,
          forbidden_pattern_absent: 1,
          no_filler: 1,
          stream_line_count: 0,
          stream_clean: 0,
          stream_useful: 0,
          stream_fast_start: 0,
          stream_has_narrowing: 0,
          stream_has_patch_ok: 0,
          clean_verify_finish: 0,
          verify_command_anchor_present: 0,
          first_progress_line: 999,
          assistant_excerpt: $excerpt,
          child_exit_code: $exit_code
        }')
      if [ "$first_json" -eq 0 ]; then
        results_json="$results_json,"
      fi
      first_json=0
      results_json="${results_json}${child_result_json}"
      continue
    fi

    child_tsv_line=$(python3 - "$child_json" <<'PY'
import json
import sys

obj = json.load(open(sys.argv[1]))
row = (obj.get("results") or [{}])[0]
fields = [
    "task_id", "status", "timed_out", "line_count", "has_outcome", "has_files", "has_verify",
    "has_risks", "has_next", "has_required_phrase", "has_required_risk_phrase", "has_required_next_phrase", "has_required_file_change",
    "has_required_secondary_change", "has_required_tertiary_change",
    "has_required_quaternary_change", "has_required_quinary_change", "required_content_present", "forbidden_pattern_absent", "no_filler",
    "stream_line_count", "stream_clean", "stream_useful", "stream_fast_start",
    "stream_has_narrowing", "stream_has_patch_ok", "clean_verify_finish", "verify_command_anchor_present", "first_progress_line",
    "assistant_excerpt",
]
print("\t".join(str(row.get(field, "")) for field in fields))
PY
)
    printf '%s\n' "$child_tsv_line" >> "$tsv_file"
    child_status=$(printf '%s\n' "$child_tsv_line" | awk -F '\t' '{print $2}')
    if [ "$child_status" = "pass" ]; then
      passes=$((passes + 1))
    fi
    child_result_json=$(python3 - "$child_json" <<'PY'
import json
import sys
obj = json.load(open(sys.argv[1]))
row = (obj.get("results") or [{}])[0]
print(json.dumps(row, separators=(",", ":")))
PY
)
    if [ "$first_json" -eq 0 ]; then
      results_json="$results_json,"
    fi
    first_json=0
    results_json="${results_json}${child_result_json}"
  done 3< "$fixtures_file"

  failures=$((total - passes))
  printf '{"label":"%s","total":%s,"passes":%s,"failures":%s,"results":[%s]}\n' \
    "$label" "$total" "$passes" "$failures" "$results_json" > "$json_file"

  {
    printf '# Programming Branchy Slice Smoke: %s\n\n' "$label"
    printf -- '- Fixtures: %s\n' "$fixtures_file"
    printf -- '- Mode: aggregated single-row runs\n'
    printf -- '- Passes: %s/%s\n\n' "$passes" "$total"
    printf '| Task | Status | Timed Out | Lines | Outcome | Files | Verify | Risks | Next | Phrase | Risk Phrase | Next Phrase | File | Second File | Third File | Fourth File | Fifth File | Required Content | Forbidden Clean | Clean | Stream Lines | Stream Clean | Stream Useful | Fast Start | Slice Narrowing | Patch OK | Clean Verify | Verify Command | First Progress Line |\n'
    printf '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n'
    tail -n +2 "$tsv_file" | while IFS=$tab read -r task_id status timed_out line_count has_outcome has_files has_verify has_risks has_next has_required_phrase has_required_risk_phrase has_required_next_phrase has_required_file_change has_required_secondary_change has_required_tertiary_change has_required_quaternary_change has_required_quinary_change required_content_present forbidden_pattern_absent no_filler stream_line_count stream_clean stream_useful stream_fast_start stream_has_narrowing stream_has_patch_ok clean_verify_finish verify_command_anchor_present first_progress_line assistant_excerpt; do
      printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
        "$task_id" "$status" "$timed_out" "$line_count" "$has_outcome" "$has_files" "$has_verify" "$has_risks" "$has_next" "$has_required_phrase" "$has_required_risk_phrase" "$has_required_next_phrase" "$has_required_file_change" "$has_required_secondary_change" "$has_required_tertiary_change" "$has_required_quaternary_change" "$has_required_quinary_change" "$required_content_present" "$forbidden_pattern_absent" "$no_filler" "$stream_line_count" "$stream_clean" "$stream_useful" "$stream_fast_start" "$stream_has_narrowing" "$stream_has_patch_ok" "$clean_verify_finish" "$verify_command_anchor_present" "$first_progress_line"
    done
  } > "$md_file"

  echo "$md_file"
  [ "$failures" -eq 0 ]
  exit 0
fi

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

tsv_file="$OUT_DIR/$label.tsv"
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
[ -n "$model" ] || { echo "No installed models available; smoke cannot run." >&2; exit 1; }

printf 'task_id\tstatus\ttimed_out\tline_count\thas_outcome\thas_files\thas_verify\thas_risks\thas_next\thas_required_phrase\thas_required_risk_phrase\thas_required_next_phrase\thas_required_file_change\thas_required_secondary_change\thas_required_tertiary_change\thas_required_quaternary_change\thas_required_quinary_change\trequired_content_present\tforbidden_pattern_absent\tno_filler\tstream_line_count\tstream_clean\tstream_useful\tstream_fast_start\tstream_has_narrowing\tstream_has_patch_ok\tclean_verify_finish\tverify_command_anchor_present\tfirst_progress_line\tassistant_excerpt\n' > "$tsv_file"
tab=$(printf '\t')

total=0
passes=0
results_json=""
first_json=1

while IFS=$tab read -r task_id prompt_text required_phrase required_stream_phrase required_file_phrase required_secondary_file_phrase required_tertiary_file_phrase required_quaternary_file_phrase required_quinary_file_phrase forbidden_file_path forbidden_file_pattern max_lines max_stream_lines max_iterations run_time_budget_sec compute_budget api_timeout_sec workspace_shape required_content_path required_content_pattern required_risk_phrase required_next_phrase followup_prompt second_followup_prompt expect_patch_ok followup_new_conversation second_followup_new_conversation followup_new_workspace second_followup_new_workspace <&3; do
  [ "$task_id" != "task_id" ] || continue
  [ -n "$task_id" ] || continue
  total=$((total + 1))
  case "$required_secondary_file_phrase" in NONE|none|-) required_secondary_file_phrase="" ;; esac
  case "$required_tertiary_file_phrase" in NONE|none|-) required_tertiary_file_phrase="" ;; esac
  case "$required_quaternary_file_phrase" in NONE|none|-) required_quaternary_file_phrase="" ;; esac
  case "$required_quinary_file_phrase" in NONE|none|-) required_quinary_file_phrase="" ;; esac
  case "$forbidden_file_path" in NONE|none|-) forbidden_file_path="" ;; esac
  case "$forbidden_file_pattern" in NONE|none|-) forbidden_file_pattern="" ;; esac
  case "${workspace_shape-}" in ""|NONE|none|-) workspace_shape="js" ;; esac
  case "${required_content_path-}" in ""|NONE|none|-) required_content_path="" ;; esac
  case "${required_content_pattern-}" in ""|NONE|none|-) required_content_pattern="" ;; esac
  case "${required_risk_phrase-}" in ""|NONE|none|-) required_risk_phrase="" ;; esac
  case "${required_next_phrase-}" in ""|NONE|none|-) required_next_phrase="" ;; esac
  case "${followup_prompt-}" in ""|NONE|none|-) followup_prompt="" ;; esac
  case "${second_followup_prompt-}" in ""|NONE|none|-) second_followup_prompt="" ;; esac
  case "${expect_patch_ok-}" in ""|NONE|none|-) expect_patch_ok=1 ;; esac
  case "${followup_new_conversation-}" in ""|NONE|none|-) followup_new_conversation=0 ;; esac
  case "${second_followup_new_conversation-}" in ""|NONE|none|-) second_followup_new_conversation=0 ;; esac
  case "${followup_new_workspace-}" in ""|NONE|none|-) followup_new_workspace=0 ;; esac
  case "${second_followup_new_workspace-}" in ""|NONE|none|-) second_followup_new_workspace=0 ;; esac
  case "$expect_patch_ok" in
    0|1) ;;
    *) expect_patch_ok=1 ;;
  esac
  case "$followup_new_conversation" in
    0|1) ;;
    *) followup_new_conversation=0 ;;
  esac
  case "$second_followup_new_conversation" in
    0|1) ;;
    *) second_followup_new_conversation=0 ;;
  esac
  case "$followup_new_workspace" in
    0|1) ;;
    *) followup_new_workspace=0 ;;
  esac
  case "$second_followup_new_workspace" in
    0|1) ;;
    *) second_followup_new_workspace=0 ;;
  esac

  tmp_ws=$(mktemp -d)
  create_fixture_workspace "$workspace_shape" "$tmp_ws"
  baseline_dir=$(mktemp -d)
  cp -R "$tmp_ws/." "$baseline_dir/"
  workspace_dirs_cleanup=$tmp_ws

  ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$task_id")")
  workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
  workspace_name=$(printf '%s' "$ws_json" | jq -r '.workspace.name // ""')
  conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$task_id")")
  conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
  post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
  workspace_ids_cleanup=$workspace_id
  current_workspace_path=$tmp_ws
  current_workspace_name=$workspace_name
  source_workspace_id=$workspace_id
  source_workspace_name=$workspace_name
  source_workspace_path=$tmp_ws
  stream_session="${task_id}-stream"
  if [ -z "$max_iterations" ]; then
    max_iterations=2
  fi
  if [ -z "$max_stream_lines" ]; then
    max_stream_lines=20
  fi
  if [ -z "$run_time_budget_sec" ]; then
    run_time_budget_sec=55
  fi
  if [ -z "$compute_budget" ]; then
    compute_budget=quick
  fi
  prompt_text_resolved=$(replace_workspace_prompt_placeholders "$prompt_text" "$source_workspace_id" "$source_workspace_name" "$source_workspace_path" "$workspace_id" "$current_workspace_name" "$current_workspace_path")
  run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text_resolved")&run_mode=programming&compute_budget=$(uri "$compute_budget")&advanced_loop=1&max_iterations=$(uri "$max_iterations")&assay_task_id=$(uri "$task_id")&stream_session=$(uri "$stream_session")"
  if [ -n "$api_timeout_sec" ]; then
    run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json_with_timeout "$run_body" "$api_timeout_sec")
  else
    run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json "$run_body")
  fi
  printf '%s\n' "$run_json" > "$raw_dir/$task_id-run.json"
  timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
  assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
  printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant.txt"
  stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
  printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream.json"
  stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
  printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream.txt"
  if [ -n "$followup_prompt" ] && [ "$timed_out" -eq 0 ] && [ -n "$assistant_text" ]; then
    printf '%s\n' "$run_json" > "$raw_dir/$task_id-run-initial.json"
    printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant-initial.txt"
    printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream-initial.json"
    printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream-initial.txt"
    if [ "$followup_new_workspace" -eq 1 ]; then
      followup_workspace_dir=$(mktemp -d)
      clone_workspace_snapshot "$current_workspace_path" "$followup_workspace_dir"
      workspace_dirs_cleanup=$(append_non_empty_line "$workspace_dirs_cleanup" "$followup_workspace_dir")
      source_workspace_id=$workspace_id
      source_workspace_name=$current_workspace_name
      source_workspace_path=$current_workspace_path
      followup_workspace_name="${task_id}-followup-workspace"
      ws_json=$(post_api_json "action=add_workspace&path=$(uri "$followup_workspace_dir")&name=$(uri "$followup_workspace_name")")
      workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
      workspace_name=$(printf '%s' "$ws_json" | jq -r '.workspace.name // ""')
      workspace_ids_cleanup=$(append_non_empty_line "$workspace_ids_cleanup" "$workspace_id")
      current_workspace_path=$followup_workspace_dir
      current_workspace_name=$workspace_name
      tmp_ws=$current_workspace_path
      conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "${task_id}-followup")")
      conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
      post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
    elif [ "$followup_new_conversation" -eq 1 ]; then
      conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "${task_id}-followup")")
      conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
      post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
    fi
    stream_session="${task_id}-followup-stream"
    followup_prompt_resolved=$(replace_workspace_prompt_placeholders "$followup_prompt" "$source_workspace_id" "$source_workspace_name" "$source_workspace_path" "$workspace_id" "$current_workspace_name" "$current_workspace_path")
    run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$followup_prompt_resolved")&run_mode=programming&compute_budget=$(uri "$compute_budget")&advanced_loop=1&max_iterations=$(uri "$max_iterations")&assay_task_id=$(uri "$task_id")&stream_session=$(uri "$stream_session")"
    if [ -n "$api_timeout_sec" ]; then
      run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json_with_timeout "$run_body" "$api_timeout_sec")
    else
      run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json "$run_body")
    fi
    printf '%s\n' "$run_json" > "$raw_dir/$task_id-run.json"
    timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
    assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
    printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant.txt"
    stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
    printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream.json"
    stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
    printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream.txt"
  fi
  if [ -n "$second_followup_prompt" ] && [ "$timed_out" -eq 0 ] && [ -n "$assistant_text" ]; then
    printf '%s\n' "$run_json" > "$raw_dir/$task_id-run-followup1.json"
    printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant-followup1.txt"
    printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream-followup1.json"
    printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream-followup1.txt"
    if [ "$second_followup_new_workspace" -eq 1 ]; then
      second_followup_workspace_dir=$(mktemp -d)
      clone_workspace_snapshot "$current_workspace_path" "$second_followup_workspace_dir"
      workspace_dirs_cleanup=$(append_non_empty_line "$workspace_dirs_cleanup" "$second_followup_workspace_dir")
      source_workspace_id=$workspace_id
      source_workspace_name=$current_workspace_name
      source_workspace_path=$current_workspace_path
      second_followup_workspace_name="${task_id}-followup2-workspace"
      ws_json=$(post_api_json "action=add_workspace&path=$(uri "$second_followup_workspace_dir")&name=$(uri "$second_followup_workspace_name")")
      workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
      workspace_name=$(printf '%s' "$ws_json" | jq -r '.workspace.name // ""')
      workspace_ids_cleanup=$(append_non_empty_line "$workspace_ids_cleanup" "$workspace_id")
      current_workspace_path=$second_followup_workspace_dir
      current_workspace_name=$workspace_name
      tmp_ws=$current_workspace_path
      conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "${task_id}-followup2")")
      conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
      post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
    elif [ "$second_followup_new_conversation" -eq 1 ]; then
      conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "${task_id}-followup2")")
      conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
      post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
    fi
    stream_session="${task_id}-followup2-stream"
    second_followup_prompt_resolved=$(replace_workspace_prompt_placeholders "$second_followup_prompt" "$source_workspace_id" "$source_workspace_name" "$source_workspace_path" "$workspace_id" "$current_workspace_name" "$current_workspace_path")
    run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$second_followup_prompt_resolved")&run_mode=programming&compute_budget=$(uri "$compute_budget")&advanced_loop=1&max_iterations=$(uri "$max_iterations")&assay_task_id=$(uri "$task_id")&stream_session=$(uri "$stream_session")"
    if [ -n "$api_timeout_sec" ]; then
      run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json_with_timeout "$run_body" "$api_timeout_sec")
    else
      run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC="$run_time_budget_sec" post_api_json "$run_body")
    fi
    printf '%s\n' "$run_json" > "$raw_dir/$task_id-run.json"
    timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
    assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
    printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant.txt"
    stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
    printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream.json"
    stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
    printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream.txt"
  fi

  line_count=$(line_count_non_empty "$assistant_text")
  has_outcome=0
  has_files=0
  has_verify=0
  has_risks=0
  has_next=0
  has_required_phrase=0
  has_required_risk_phrase=1
  has_required_next_phrase=1
  has_required_file_change=0
  has_required_secondary_change=1
  has_required_tertiary_change=1
  has_required_quaternary_change=1
  has_required_quinary_change=1
  required_content_present=1
  forbidden_pattern_absent=1
  no_filler=1
  stream_clean=1
  stream_useful=0
  stream_fast_start=0
  stream_has_narrowing=0
  stream_has_patch_ok=0
  clean_verify_finish=0
  verify_command_anchor_present=1
  if [ -z "$timed_out" ]; then
    timed_out=0
  fi
  if printf '%s\n' "$assistant_text" | grep -q '^Outcome:'; then has_outcome=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Files Changed:'; then has_files=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:'; then has_verify=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Risks:'; then has_risks=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:'; then has_next=1; fi
  if printf '%s\n' "$assistant_text" | grep -Fqi "$required_phrase"; then has_required_phrase=1; fi
  if [ -n "$required_risk_phrase" ]; then
    has_required_risk_phrase=0
    if printf '%s\n' "$assistant_text" | awk '/^Risks:/{print; exit}' | grep -Fqi "$required_risk_phrase"; then
      has_required_risk_phrase=1
    fi
  fi
  if [ -n "$required_next_phrase" ]; then
    has_required_next_phrase=0
    if printf '%s\n' "$assistant_text" | awk '/^Next Improvement:/{print; exit}' | grep -Fqi "$required_next_phrase"; then
      has_required_next_phrase=1
    fi
  fi
  required_file_changed=0
  if [ -n "$required_file_phrase" ]; then
    required_file_changed=$(file_changed_flag "$baseline_dir" "$tmp_ws" "$required_file_phrase")
  fi
  if printf '%s\n' "$assistant_text" | grep -Eq '^Files Changed:' && printf '%s\n' "$assistant_text" | grep -Fqi "$required_file_phrase" && [ "$required_file_changed" -eq 1 ] && ! printf '%s\n' "$assistant_text" | grep -Fq 'No workspace file changes were confirmed.'; then
    has_required_file_change=1
  fi
  if [ -n "$required_secondary_file_phrase" ]; then
    required_secondary_changed=$(file_changed_flag "$baseline_dir" "$tmp_ws" "$required_secondary_file_phrase")
    if ! { printf '%s\n' "$assistant_text" | grep -Eq '^Files Changed:' && printf '%s\n' "$assistant_text" | grep -Fqi "$required_secondary_file_phrase" && [ "$required_secondary_changed" -eq 1 ]; }; then
      has_required_secondary_change=0
    fi
  fi
  if [ -n "$required_tertiary_file_phrase" ]; then
    required_tertiary_changed=$(file_changed_flag "$baseline_dir" "$tmp_ws" "$required_tertiary_file_phrase")
    if ! { printf '%s\n' "$assistant_text" | grep -Eq '^Files Changed:' && printf '%s\n' "$assistant_text" | grep -Fqi "$required_tertiary_file_phrase" && [ "$required_tertiary_changed" -eq 1 ]; }; then
      has_required_tertiary_change=0
    fi
  fi
  if [ -n "$required_quaternary_file_phrase" ]; then
    required_quaternary_changed=$(file_changed_flag "$baseline_dir" "$tmp_ws" "$required_quaternary_file_phrase")
    if ! { printf '%s\n' "$assistant_text" | grep -Eq '^Files Changed:' && printf '%s\n' "$assistant_text" | grep -Fqi "$required_quaternary_file_phrase" && [ "$required_quaternary_changed" -eq 1 ]; }; then
      has_required_quaternary_change=0
    fi
  fi
  if [ -n "$required_quinary_file_phrase" ]; then
    required_quinary_changed=$(file_changed_flag "$baseline_dir" "$tmp_ws" "$required_quinary_file_phrase")
    if ! { printf '%s\n' "$assistant_text" | grep -Eq '^Files Changed:' && printf '%s\n' "$assistant_text" | grep -Fqi "$required_quinary_file_phrase" && [ "$required_quinary_changed" -eq 1 ]; }; then
      has_required_quinary_change=0
    fi
  fi
  if [ -n "$required_content_path" ] && [ -n "$required_content_pattern" ]; then
    if [ ! -f "$tmp_ws/$required_content_path" ] || ! grep -Eq "$required_content_pattern" "$tmp_ws/$required_content_path"; then
      required_content_present=0
    fi
  fi
  if [ -n "$forbidden_file_path" ] && [ -n "$forbidden_file_pattern" ] && [ -f "$tmp_ws/$forbidden_file_path" ]; then
    if grep -Eq "$forbidden_file_pattern" "$tmp_ws/$forbidden_file_path"; then
      forbidden_pattern_absent=0
    fi
  fi
  if printf '%s\n' "$assistant_text" | grep -Eiq 'how may i assist you further|have a great day|let me know if you have any more questions|failure ledger|current mode:|next best step:|action:|hypothesis:|next attempt:'; then
    no_filler=0
  fi
  stream_line_count=$(line_count_non_empty "$stream_text")
  if printf '%s\n' "$stream_text" | grep -Eiq 'controller prompt assembled|controller call started|controller response captured|current mode:|control sections parsed|completion check:|run orchestration initialized|initial checkpoints seeded|command [0-9]+ started|command [0-9]+ status|step [0-9]+ next:|step [0-9]+ checkpoint:|confidence updated|format retry'; then
    stream_clean=0
  fi
  if printf '%s\n' "$stream_text" | grep -Eiq 'Preparing workspace and implementation plan|Preparing a bounded first pass|Programming run started|planning the next move|inspecting the workspace and gathering evidence|applying code changes|running verification checks|switching from|preparing a partial summary|preparing a best-effort summary|Final answer ready|Run finished|Paused for a required user decision|Preparing a required user decision'; then
    stream_useful=1
  fi
  if printf '%s\n' "$stream_text" | grep -Fqi "$required_stream_phrase"; then
    stream_has_narrowing=1
  fi
  if printf '%s\n' "$stream_text" | grep -Fqi 'patch gate status: ok'; then
    stream_has_patch_ok=1
  fi
  if printf '%s\n' "$assistant_text" | grep -Eqi 'Outcome: Completed a scoped implementation pass|Outcome: Completed phase [0-9]+' && ! printf '%s\n' "$assistant_text" | grep -Fqi 'final check path did not pass cleanly'; then
    clean_verify_finish=1
  fi
  if [ -n "$required_quaternary_file_phrase" ]; then
    if ! printf '%s\n' "$assistant_text" | grep -Fqi "./$required_quaternary_file_phrase"; then
      verify_command_anchor_present=0
    fi
  fi
  first_progress_line=$(printf '%s\n' "$stream_text" | awk '
    BEGIN { IGNORECASE=1; line_no=0; found=0 }
    /^[[:space:]]*$/ { next }
    {
      line_no++
      if (!found && $0 ~ /starting immediate workspace discovery|inspecting the workspace and gathering evidence|narrowing to one verified slice|applying code changes|running verification checks|preparing a best-effort summary|preparing a partial summary|preserving the current landed slices and deferred queue|using deterministic phase stop\/go fast path/) {
        print line_no
        found=1
        exit
      }
    }
    END {
      if (!found) print 999
    }
  ')
  if [ "$first_progress_line" -le 7 ] 2>/dev/null; then
    stream_fast_start=1
  fi

  if [ "${ARTIFICER_PROGRAMMING_SMOKE_DELETE_WORKSPACE:-0}" = "1" ]; then
    printf '%s\n' "$workspace_ids_cleanup" | awk '!seen[$0]++' | while IFS= read -r cleanup_workspace_id; do
      [ -n "$cleanup_workspace_id" ] || continue
      delete_workspace_best_effort "$cleanup_workspace_id"
    done
  fi
  printf '%s\n' "$workspace_dirs_cleanup" | awk '!seen[$0]++' | while IFS= read -r cleanup_workspace_dir; do
    [ -n "$cleanup_workspace_dir" ] || continue
    rm -rf "$cleanup_workspace_dir"
  done
  rm -rf "$baseline_dir"

  status="pass"
  if [ "$timed_out" -ne 0 ] || [ "$line_count" -gt "$max_lines" ] || [ "$has_outcome" -ne 1 ] || [ "$has_files" -ne 1 ] || [ "$has_verify" -ne 1 ] || [ "$has_risks" -ne 1 ] || [ "$has_next" -ne 1 ] || [ "$has_required_phrase" -ne 1 ] || [ "$has_required_risk_phrase" -ne 1 ] || [ "$has_required_next_phrase" -ne 1 ] || [ "$has_required_file_change" -ne 1 ] || [ "$has_required_secondary_change" -ne 1 ] || [ "$has_required_tertiary_change" -ne 1 ] || [ "$has_required_quaternary_change" -ne 1 ] || [ "$has_required_quinary_change" -ne 1 ] || [ "$required_content_present" -ne 1 ] || [ "$forbidden_pattern_absent" -ne 1 ] || [ "$no_filler" -ne 1 ] || [ "$stream_clean" -ne 1 ] || [ "$stream_useful" -ne 1 ] || [ "$stream_fast_start" -ne 1 ] || [ "$stream_has_narrowing" -ne 1 ] || [ "$stream_has_patch_ok" -ne "$expect_patch_ok" ] || [ "$clean_verify_finish" -ne 1 ] || [ "$verify_command_anchor_present" -ne 1 ] || [ "$stream_line_count" -gt "$max_stream_lines" ]; then
    status="fail"
  else
    passes=$((passes + 1))
  fi

  assistant_excerpt=$(printf '%s' "$assistant_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-220)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$task_id" "$status" "$timed_out" "$line_count" "$has_outcome" "$has_files" "$has_verify" "$has_risks" "$has_next" "$has_required_phrase" "$has_required_risk_phrase" "$has_required_next_phrase" "$has_required_file_change" "$has_required_secondary_change" "$has_required_tertiary_change" "$has_required_quaternary_change" "$has_required_quinary_change" "$required_content_present" "$forbidden_pattern_absent" "$no_filler" "$stream_line_count" "$stream_clean" "$stream_useful" "$stream_fast_start" "$stream_has_narrowing" "$stream_has_patch_ok" "$clean_verify_finish" "$verify_command_anchor_present" "$first_progress_line" "$assistant_excerpt" >> "$tsv_file"

  task_id_json=$(printf '%s' "$task_id" | jq -Rs .)
  status_json=$(printf '%s' "$status" | jq -Rs .)
  excerpt_json=$(printf '%s' "$assistant_excerpt" | jq -Rs .)
  if [ "$first_json" -eq 0 ]; then
    results_json="$results_json,"
  fi
  first_json=0
  results_json="${results_json}{\"task_id\":$task_id_json,\"status\":$status_json,\"timed_out\":$timed_out,\"line_count\":$line_count,\"has_outcome\":$has_outcome,\"has_files\":$has_files,\"has_verify\":$has_verify,\"has_risks\":$has_risks,\"has_next\":$has_next,\"has_required_phrase\":$has_required_phrase,\"has_required_risk_phrase\":$has_required_risk_phrase,\"has_required_next_phrase\":$has_required_next_phrase,\"has_required_file_change\":$has_required_file_change,\"has_required_secondary_change\":$has_required_secondary_change,\"has_required_tertiary_change\":$has_required_tertiary_change,\"has_required_quaternary_change\":$has_required_quaternary_change,\"has_required_quinary_change\":$has_required_quinary_change,\"required_content_present\":$required_content_present,\"forbidden_pattern_absent\":$forbidden_pattern_absent,\"no_filler\":$no_filler,\"stream_line_count\":$stream_line_count,\"stream_clean\":$stream_clean,\"stream_useful\":$stream_useful,\"stream_fast_start\":$stream_fast_start,\"stream_has_narrowing\":$stream_has_narrowing,\"stream_has_patch_ok\":$stream_has_patch_ok,\"clean_verify_finish\":$clean_verify_finish,\"verify_command_anchor_present\":$verify_command_anchor_present,\"first_progress_line\":$first_progress_line,\"assistant_excerpt\":$excerpt_json}"
done 3< "$fixtures_file"

failures=$((total - passes))
printf '{"label":"%s","total":%s,"passes":%s,"failures":%s,"results":[%s]}\n' \
  "$label" "$total" "$passes" "$failures" "$results_json" > "$json_file"

{
  printf '# Programming Branchy Slice Smoke: %s\n\n' "$label"
  printf -- '- Fixtures: %s\n' "$fixtures_file"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Passes: %s/%s\n\n' "$passes" "$total"
  printf '| Task | Status | Timed Out | Lines | Outcome | Files | Verify | Risks | Next | Phrase | Risk Phrase | Next Phrase | File | Second File | Third File | Fourth File | Fifth File | Required Content | Forbidden Clean | Clean | Stream Lines | Stream Clean | Stream Useful | Fast Start | Slice Narrowing | Patch OK | Clean Verify | Verify Command | First Progress Line |\n'
  printf '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n'
  tail -n +2 "$tsv_file" | while IFS=$tab read -r task_id status timed_out line_count has_outcome has_files has_verify has_risks has_next has_required_phrase has_required_risk_phrase has_required_next_phrase has_required_file_change has_required_secondary_change has_required_tertiary_change has_required_quaternary_change has_required_quinary_change required_content_present forbidden_pattern_absent no_filler stream_line_count stream_clean stream_useful stream_fast_start stream_has_narrowing stream_has_patch_ok clean_verify_finish verify_command_anchor_present first_progress_line assistant_excerpt; do
    printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$task_id" "$status" "$timed_out" "$line_count" "$has_outcome" "$has_files" "$has_verify" "$has_risks" "$has_next" "$has_required_phrase" "$has_required_risk_phrase" "$has_required_next_phrase" "$has_required_file_change" "$has_required_secondary_change" "$has_required_tertiary_change" "$has_required_quaternary_change" "$has_required_quinary_change" "$required_content_present" "$forbidden_pattern_absent" "$no_filler" "$stream_line_count" "$stream_clean" "$stream_useful" "$stream_fast_start" "$stream_has_narrowing" "$stream_has_patch_ok" "$clean_verify_finish" "$verify_command_anchor_present" "$first_progress_line"
  done
} > "$md_file"

echo "$md_file"
[ "$failures" -eq 0 ]
