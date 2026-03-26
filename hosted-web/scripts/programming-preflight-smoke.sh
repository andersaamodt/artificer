#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SITE_ROOT/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_FIXTURES="$SITE_ROOT/tests/fixtures/artificer-programming-preflight-smoke.tsv"
DEFAULT_LABEL="programming-preflight-smoke"
API_SCRIPT="$SITE_ROOT/cgi/artificer-api"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for programming preflight smoke." >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: programming-preflight-smoke.sh [--label NAME] [--fixtures FILE]

Runs a live CGI smoke against programming-mode model-unavailable preflight handling.
EOF
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

post_api_json() {
  body=$1
  len=$(printf '%s' "$body" | wc -c | tr -d ' ')
  REQUEST_METHOD=POST CONTENT_LENGTH="$len" sh "$API_SCRIPT" <<EOF | tr -d '\r' | awk 'seen{print} /^$/{seen=1}'
$body
EOF
}

line_count_non_empty() {
  printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
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

if [ ! -f "$fixtures_file" ]; then
  echo "Fixture file not found: $fixtures_file" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

tsv_file="$OUT_DIR/$label.tsv"
json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"

models_json=$(post_api_json "action=models")
model_count=$(printf '%s' "$models_json" | jq -r '.models | length')
case "$model_count" in
  ""|*[!0-9]*)
    model_count=0
    ;;
esac
if [ "$model_count" -lt 1 ]; then
  echo "No installed models available; smoke cannot verify model-missing preflight against a known inventory." >&2
  exit 1
fi

tmp_ws=$(mktemp -d)
workspace_name="Programming Preflight Smoke $label"
ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$workspace_name")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
if [ -z "$workspace_id" ]; then
  echo "Could not create smoke workspace." >&2
  exit 1
fi

printf 'task_id\tstatus\tline_count\thas_outcome\thas_verify\thas_risks\thas_next\tno_pull_noise\tno_failure_ledger\tassistant_excerpt\n' > "$tsv_file"

total=0
passes=0
results_json=""
first_json=1

while IFS='	' read -r task_id model_name max_lines prompt_text; do
  [ "$task_id" != "task_id" ] || continue
  [ -n "$task_id" ] || continue
  total=$((total + 1))

  conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$task_id")")
  conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
  if [ -z "$conversation_id" ]; then
    status="fail"
    assistant_text="conversation creation failed"
  else
    post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model_name")" >/dev/null
    run_json=$(post_api_json "action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=programming&compute_budget=quick&advanced_loop=1&max_iterations=4")
    printf '%s\n' "$run_json" > "$raw_dir/$task_id-run.json"
    assistant_text=$(printf '%s' "$run_json" | jq -r '.assistant // ""')
  fi

  printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant.txt"
  line_count=$(line_count_non_empty "$assistant_text")
  has_outcome=0
  has_verify=0
  has_risks=0
  has_next=0
  no_pull_noise=1
  no_failure_ledger=1
  if printf '%s\n' "$assistant_text" | grep -q '^Outcome:'; then has_outcome=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:'; then has_verify=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Risks:'; then has_risks=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:'; then has_next=1; fi
  if printf '%s\n' "$assistant_text" | grep -Eiq 'pulling manifest|verifying sha256 digest|writing manifest'; then no_pull_noise=0; fi
  if printf '%s\n' "$assistant_text" | grep -Eiq 'failure ledger'; then no_failure_ledger=0; fi

  status="pass"
  if [ "$line_count" -gt "$max_lines" ] || [ "$has_outcome" -ne 1 ] || [ "$has_verify" -ne 1 ] || [ "$has_risks" -ne 1 ] || [ "$has_next" -ne 1 ] || [ "$no_pull_noise" -ne 1 ] || [ "$no_failure_ledger" -ne 1 ]; then
    status="fail"
  else
    passes=$((passes + 1))
  fi

  assistant_excerpt=$(printf '%s' "$assistant_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-220)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$task_id" "$status" "$line_count" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$no_pull_noise" "$no_failure_ledger" "$assistant_excerpt" >> "$tsv_file"

  task_id_json=$(printf '%s' "$task_id" | jq -Rs .)
  status_json=$(printf '%s' "$status" | jq -Rs .)
  excerpt_json=$(printf '%s' "$assistant_excerpt" | jq -Rs .)
  if [ "$first_json" -eq 0 ]; then
    results_json="$results_json,"
  fi
  first_json=0
  results_json="${results_json}{\"task_id\":$task_id_json,\"status\":$status_json,\"line_count\":$line_count,\"has_outcome\":$has_outcome,\"has_verify\":$has_verify,\"has_risks\":$has_risks,\"has_next\":$has_next,\"no_pull_noise\":$no_pull_noise,\"no_failure_ledger\":$no_failure_ledger,\"assistant_excerpt\":$excerpt_json}"
done < "$fixtures_file"

failures=$((total - passes))
printf '{"label":"%s","total":%s,"passes":%s,"failures":%s,"results":[%s]}\n' \
  "$label" "$total" "$passes" "$failures" "$results_json" > "$json_file"

{
  printf '# Programming Preflight Smoke: %s\n\n' "$label"
  printf -- '- Workspace: %s\n' "$workspace_id"
  printf -- '- Fixtures: %s\n' "$fixtures_file"
  printf -- '- Passes: %s/%s\n\n' "$passes" "$total"
  printf '| Task | Status | Lines | Outcome | Verify | Risks | Next | Clean |\n'
  printf '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n'
  tail -n +2 "$tsv_file" | while IFS='	' read -r task_id status line_count has_outcome has_verify has_risks has_next no_pull_noise no_failure_ledger assistant_excerpt; do
    clean=$((no_pull_noise * no_failure_ledger))
    printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$task_id" "$status" "$line_count" "$has_outcome" "$has_verify" "$has_risks" "$has_next" "$clean"
  done
} > "$md_file"

echo "$md_file"
if [ "$failures" -ne 0 ]; then
  exit 1
fi
