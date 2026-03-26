#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SITE_ROOT/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_FIXTURES="$SITE_ROOT/tests/fixtures/artificer-programming-stalled-summary-smoke.tsv"
DEFAULT_LABEL="programming-stalled-summary-smoke"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for programming stalled summary smoke." >&2
  exit 1
fi

usage() {
  cat <<EOF_USAGE
Usage: programming-stalled-summary-smoke.sh [--label NAME] [--fixtures FILE]

Runs a live CGI smoke against bounded programming runs and checks the incomplete-run summary contract.
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

[ -f "$fixtures_file" ] || { echo "Fixture file not found: $fixtures_file" >&2; exit 1; }

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

printf 'task_id\tstatus\tline_count\thas_outcome\thas_files\thas_verify\thas_risks\thas_next\thas_required_phrase\tno_filler\tstream_line_count\tstream_clean\tstream_useful\tstream_fast_start\tfirst_progress_line\tassistant_excerpt\n' > "$tsv_file"
tab=$(printf '\t')

total=0
passes=0
results_json=""
first_json=1

while IFS=$tab read -r task_id prompt_text required_phrase max_lines; do
  [ "$task_id" != "task_id" ] || continue
  [ -n "$task_id" ] || continue
  total=$((total + 1))

  tmp_ws=$(mktemp -d)
  cat > "$tmp_ws/app.js" <<'EOF_APP'
function greet(name) {
  return 'hello ' + name;
}
module.exports = { greet };
EOF_APP

  ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$task_id")")
  workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
  conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$task_id")")
  conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
  post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null
  stream_session="${task_id}-stream"
  run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=45 post_api_json "action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=programming&compute_budget=quick&advanced_loop=1&max_iterations=1&assay_task_id=$(uri "$task_id")&stream_session=$(uri "$stream_session")")
  printf '%s\n' "$run_json" > "$raw_dir/$task_id-run.json"
  assistant_text=$(printf '%s' "$run_json" | jq -r '.assistant // ""')
  printf '%s\n' "$assistant_text" > "$raw_dir/$task_id-assistant.txt"
  stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
  printf '%s\n' "$stream_json" > "$raw_dir/$task_id-stream.json"
  stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
  printf '%s\n' "$stream_text" > "$raw_dir/$task_id-stream.txt"
  post_api_json "action=delete_workspace&workspace_id=$(uri "$workspace_id")" >/dev/null || true
  rm -rf "$tmp_ws"

  line_count=$(line_count_non_empty "$assistant_text")
  has_outcome=0
  has_files=0
  has_verify=0
  has_risks=0
  has_next=0
  has_required_phrase=0
  no_filler=1
  stream_clean=1
  stream_useful=0
  stream_fast_start=0
  if printf '%s\n' "$assistant_text" | grep -q '^Outcome:'; then has_outcome=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Files Changed:'; then has_files=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Verification Evidence:'; then has_verify=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Risks:'; then has_risks=1; fi
  if printf '%s\n' "$assistant_text" | grep -q '^Next Improvement:'; then has_next=1; fi
  if printf '%s\n' "$assistant_text" | grep -Fqi "$required_phrase"; then has_required_phrase=1; fi
  if printf '%s\n' "$assistant_text" | grep -Eiq 'how may i assist you further|have a great day|let me know if you have any more questions|failure ledger|current mode:|next best step:|action:|hypothesis:|next attempt:'; then
    no_filler=0
  fi
  stream_line_count=$(line_count_non_empty "$stream_text")
  if printf '%s\n' "$stream_text" | grep -Eiq 'controller prompt assembled|controller call started|controller response captured|current mode:|control sections parsed|completion check:|run orchestration initialized|initial checkpoints seeded|command [0-9]+ started|command [0-9]+ status|step [0-9]+ next:|step [0-9]+ checkpoint:|confidence updated|format retry'; then
    stream_clean=0
  fi
  if printf '%s\n' "$stream_text" | grep -Eiq 'Preparing workspace and implementation plan|Programming run started|planning the next move|inspecting the workspace and gathering evidence|applying code changes|running verification checks|switching from|preparing a partial summary|preparing a best-effort summary|Final answer ready|Run finished|Paused for a required user decision|Preparing a required user decision'; then
    stream_useful=1
  fi
  first_progress_line=$(printf '%s\n' "$stream_text" | awk '
    BEGIN { IGNORECASE=1; line_no=0; found=0 }
    /^[[:space:]]*$/ { next }
    {
      line_no++
      if (!found && $0 ~ /starting immediate workspace discovery|inspecting the workspace and gathering evidence|applying code changes|running verification checks|preparing a best-effort summary|preparing a partial summary/) {
        print line_no
        found=1
        exit
      }
    }
    END {
      if (!found) print 999
    }
  ')
  if [ "$first_progress_line" -le 6 ] 2>/dev/null; then
    stream_fast_start=1
  fi

  status="pass"
  if [ "$line_count" -gt "$max_lines" ] || [ "$has_outcome" -ne 1 ] || [ "$has_files" -ne 1 ] || [ "$has_verify" -ne 1 ] || [ "$has_risks" -ne 1 ] || [ "$has_next" -ne 1 ] || [ "$has_required_phrase" -ne 1 ] || [ "$no_filler" -ne 1 ] || [ "$stream_clean" -ne 1 ] || [ "$stream_useful" -ne 1 ] || [ "$stream_fast_start" -ne 1 ] || [ "$stream_line_count" -gt 18 ]; then
    status="fail"
  else
    passes=$((passes + 1))
  fi

  assistant_excerpt=$(printf '%s' "$assistant_text" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-220)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$task_id" "$status" "$line_count" "$has_outcome" "$has_files" "$has_verify" "$has_risks" "$has_next" "$has_required_phrase" "$no_filler" "$stream_line_count" "$stream_clean" "$stream_useful" "$stream_fast_start" "$first_progress_line" "$assistant_excerpt" >> "$tsv_file"

  task_id_json=$(printf '%s' "$task_id" | jq -Rs .)
  status_json=$(printf '%s' "$status" | jq -Rs .)
  excerpt_json=$(printf '%s' "$assistant_excerpt" | jq -Rs .)
  if [ "$first_json" -eq 0 ]; then
    results_json="$results_json,"
  fi
  first_json=0
  results_json="${results_json}{\"task_id\":$task_id_json,\"status\":$status_json,\"line_count\":$line_count,\"has_outcome\":$has_outcome,\"has_files\":$has_files,\"has_verify\":$has_verify,\"has_risks\":$has_risks,\"has_next\":$has_next,\"has_required_phrase\":$has_required_phrase,\"no_filler\":$no_filler,\"stream_line_count\":$stream_line_count,\"stream_clean\":$stream_clean,\"stream_useful\":$stream_useful,\"stream_fast_start\":$stream_fast_start,\"first_progress_line\":$first_progress_line,\"assistant_excerpt\":$excerpt_json}"
done < "$fixtures_file"

failures=$((total - passes))
printf '{"label":"%s","total":%s,"passes":%s,"failures":%s,"results":[%s]}\n' \
  "$label" "$total" "$passes" "$failures" "$results_json" > "$json_file"

{
  printf '# Programming Stalled Summary Smoke: %s\n\n' "$label"
  printf -- '- Fixtures: %s\n' "$fixtures_file"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Passes: %s/%s\n\n' "$passes" "$total"
  printf '| Task | Status | Lines | Outcome | Files | Verify | Risks | Next | Phrase | Clean | Stream Lines | Stream Clean | Stream Useful | Fast Start | First Progress Line |\n'
  printf '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n'
  tail -n +2 "$tsv_file" | while IFS=$tab read -r task_id status line_count has_outcome has_files has_verify has_risks has_next has_required_phrase no_filler stream_line_count stream_clean stream_useful stream_fast_start first_progress_line assistant_excerpt; do
    printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$task_id" "$status" "$line_count" "$has_outcome" "$has_files" "$has_verify" "$has_risks" "$has_next" "$has_required_phrase" "$no_filler" "$stream_line_count" "$stream_clean" "$stream_useful" "$stream_fast_start" "$first_progress_line"
  done
} > "$md_file"

echo "$md_file"
[ "$failures" -eq 0 ]
