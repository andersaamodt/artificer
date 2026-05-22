#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PARENT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)

SITE_ROOT=""
if [ -x "$PROJECT_ROOT/hosted-web/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT/hosted-web"
elif [ -x "$PROJECT_ROOT/cgi/artificer-api" ]; then
  SITE_ROOT="$PROJECT_ROOT"
elif [ -x "$PARENT_ROOT/web/artificer/cgi/artificer-api" ]; then
  SITE_ROOT="$PARENT_ROOT/web/artificer"
fi

if [ -z "$SITE_ROOT" ]; then
  echo "Could not locate artificer site root from $SCRIPT_DIR" >&2
  exit 1
fi

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

API="$SITE_ROOT/cgi/artificer-api"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_TASKS="$SITE_ROOT/tests/fixtures/artificer-broad-reasoning-regressions-v44-compactthreadfit.tsv"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for compact reasoning assays." >&2
  exit 1
fi

cleanup_compact_ws_id=""
cleanup_compact_path=""

usage() {
  cat <<'USAGE'
Usage:
  compact-reasoning-cycle.sh run [--label NAME] [--tasks-file FILE] [--request-timeout-sec N] [--settle-timeout-sec N]
  compact-reasoning-cycle.sh transfer [--label NAME] --battery-summary FILE --holdout-summary FILE [--enforce-gates]

Notes:
  - The compact runner exercises the exact GUI-style five-line auto/quick reasoning path.
  - Prompts are sent as-is with run_mode=auto, compute_budget=quick, and advanced_loop=0.
  - Tasks may optionally include a followup_prompt column; when present, the runner sends
    the first prompt, waits for completion, then sends the follow-up in the same thread and
    scores the final assistant reply.

Examples:
  hosted-web/scripts/compact-reasoning-cycle.sh run --label compact-v42-regressions-r1
  hosted-web/scripts/compact-reasoning-cycle.sh transfer --label compact-v42-transfer-r1 \
    --battery-summary "$ARTIFICER_ASSAY_REPORTS_DIR"/compact-v42-regressions-r1-summary.json \
    --holdout-summary "$ARTIFICER_ASSAY_REPORTS_DIR"/compact-v42-holdout-r1-summary.json \
    --enforce-gates
USAGE
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

cleanup_compact_workspace() {
  if [ -n "$cleanup_compact_ws_id" ]; then
    post_api "action=delete_workspace&workspace_id=$(urlenc "$cleanup_compact_ws_id")" >/dev/null 2>&1 || true
    cleanup_compact_ws_id=""
  fi
  if [ -n "$cleanup_compact_path" ]; then
    rm -rf "$cleanup_compact_path" >/dev/null 2>&1 || true
    cleanup_compact_path=""
  fi
}

trap 'cleanup_compact_workspace' EXIT HUP INT TERM

urlenc() {
  jq -rn --arg v "$1" '$v|@uri'
}

json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

post_api() {
  body=$1
  REQUEST_METHOD=POST sh "$API" <<EOF_BODY
$body
EOF_BODY
}

post_api_json() {
  body=$1
  raw=$(post_api "$body")
  json=$(printf '%s' "$raw" | json_only)
  if [ -z "$(printf '%s' "$json" | tr -d '[:space:]')" ]; then
    echo "API response did not include JSON payload." >&2
    return 1
  fi
  ok=$(printf '%s' "$json" | jq -r 'if (type=="object" and has("success")) then (.success|tostring) else "true" end' 2>/dev/null || printf '%s' "false")
  if [ "$ok" = "false" ]; then
    err=$(printf '%s' "$json" | jq -r '.error // "unknown error"' 2>/dev/null || printf '%s' "unknown error")
    echo "API returned failure: $err" >&2
    return 1
  fi
  printf '%s' "$json"
}

run_with_timeout() {
  timeout_sec=$1
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_sec" "$@"
}

post_api_with_timeout() {
  timeout_sec=$1
  body=$2
  body_file=$(mktemp "${TMPDIR:-/tmp}/artificer-compact-body.XXXXXX")
  printf '%s' "$body" > "$body_file"
  set +e
  run_with_timeout "$timeout_sec" sh -c 'REQUEST_METHOD=POST sh "$1" < "$2"' sh "$API" "$body_file"
  status=$?
  set -e
  rm -f "$body_file"
  return "$status"
}

run_compact_turn() {
  workspace_id=$1
  conversation_id=$2
  prompt_text=$3
  request_timeout_sec=$4
  settle_timeout_sec=$5

  body="action=run&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&prompt=$(urlenc "$prompt_text")&run_mode=auto&compute_budget=quick&advanced_loop=0&max_iterations=7"
  turn_submit_timed_out=0
  if ! post_api_with_timeout "$request_timeout_sec" "$body" >/dev/null 2>&1; then
    turn_submit_timed_out=1
    post_api "action=queue_stop&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")" >/dev/null 2>&1 || true
  fi

  poll_count=0
  poll_limit=$((settle_timeout_sec * 4))
  turn_state_json='{}'
  turn_queue_json='{}'
  turn_assistant_text=""
  turn_run_event_id=""
  turn_run_status=""
  turn_stream_text=""
  while [ "$poll_count" -lt "$poll_limit" ]; do
    turn_queue_json=$(post_api_json "action=queue_list&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&limit=1")
    turn_state_json=$(post_api_json "action=get_conversation&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")")
    turn_assistant_text=$(printf '%s' "$turn_state_json" | jq -r '.conversation.messages | map(select(.role=="assistant")) | last | .content // ""')
    turn_run_event_id=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].id // ""')
    turn_run_status=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].status // ""')
    turn_stream_text=$(printf '%s' "$turn_state_json" | jq -r '.conversation.run_events[-1].stream_text // ""')
    queue_running=$(printf '%s' "$turn_queue_json" | jq -r '.queue_running // 0')

    if [ "$queue_running" != "1" ] && [ -n "$(trim "$turn_assistant_text")" ]; then
      break
    fi
    if [ "$queue_running" != "1" ] && { [ "$turn_run_status" = "error" ] || [ "$turn_run_status" = "timeout" ]; }; then
      break
    fi
    sleep 0.25
    poll_count=$((poll_count + 1))
  done

  if [ -z "$turn_run_status" ]; then
    turn_run_status="pending"
  fi
  if [ "$turn_submit_timed_out" -eq 1 ]; then
    turn_run_status="timeout"
  elif [ -z "$(trim "$turn_assistant_text")" ] && [ "$turn_run_status" = "pending" ]; then
    turn_run_status="timeout"
  fi
}

score_compact_row() {
  assistant_text=$1
  run_status=$2
  task_id=$3
  mode=$4
  budget=$5
  domain=$6
  pair_id=$7
  variant=$8
  tactics=$9
  required_patterns=${10}
  forbidden_patterns=${11}
  conversation_id=${12}
  run_event_id=${13}

  jq -rn \
    --arg assistant "$assistant_text" \
    --arg status "$run_status" \
    --arg task_id "$task_id" \
    --arg mode "$mode" \
    --arg budget "$budget" \
    --arg domain "$domain" \
    --arg pair_id "$pair_id" \
    --arg variant "$variant" \
    --arg tactics "$tactics" \
    --arg required "$required_patterns" \
    --arg forbidden "$forbidden_patterns" \
    --arg conversation_id "$conversation_id" \
    --arg run_event_id "$run_event_id" '
      def split_patterns(s): [ (s | split(";"))[] | gsub("^[[:space:]]+|[[:space:]]+$"; "") | select(length > 0 and (ascii_downcase != "__none__")) ];
      def clamp(x): if x < 0 then 0 elif x > 100 then 100 else x end;
      ($assistant | gsub("\r"; "")) as $assistant_text |
      ($assistant_text | split("\n") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $lines |
      ($assistant_text | ascii_downcase) as $assistant_lower |
      (split_patterns($required)) as $reqs |
      (split_patterns($forbidden)) as $forb |
      (["Outcome:", "Initial Assumption:", "Invalidating Evidence:", "Revised Decision:", "Claim-to-Evidence Map:"]) as $labels |
      ($lines | length) as $line_count |
      ([$labels[] as $label | ($lines | map(select(startswith($label))) | length)]) as $label_counts |
      ($label_counts | all(. == 1)) as $labels_exact_once |
      (($line_count == 5) and $labels_exact_once) as $exact_contract |
      ([ $reqs[]? as $pat | if ($assistant_lower | contains($pat | ascii_downcase)) then 1 else 0 end ] | add // 0) as $req_hits |
      ([ $forb[]? as $pat | select($assistant_lower | contains($pat | ascii_downcase)) ] | length) as $forb_hits |
      (if ($reqs | length) > 0 then ($req_hits / ($reqs | length)) else 1 end) as $req_ratio |
      (($assistant_lower | test("owner:")) and ($assistant_lower | test("review window:"))) as $owner_window_signal |
      (($assistant_lower | test("current scenario|scenario anchors|cross-domain integrated reasoning"))) as $generic_fallback_signal |
      (clamp(
        15
        + (if $status == "done" then 20 elif $status == "timeout" then -20 else -10 end)
        + (if $exact_contract then 25 else -20 end)
        + (25 * $req_ratio)
        + (if $owner_window_signal then 10 else 0 end)
        - (20 * $forb_hits)
        - (if $generic_fallback_signal then 15 else 0 end)
      ) | floor) as $overall |
      (if ($status == "done" and (($req_ratio < 1) or ($forb_hits > 0) or ($exact_contract | not))) then 1 else 0 end) as $fail_open |
      (if (($forb_hits > 0) or $generic_fallback_signal) then 1 else 0 end) as $contradiction |
      (if (($exact_contract | not) or ($req_ratio < 1)) then 1 else 0 end) as $shallow |
      [
        $task_id,
        $mode,
        $budget,
        $domain,
        $pair_id,
        $variant,
        $tactics,
        $status,
        ($line_count | tostring),
        (if $labels_exact_once then "1" else "0" end),
        (if $exact_contract then "1" else "0" end),
        ($req_ratio | tostring),
        ($forb_hits | tostring),
        (if $owner_window_signal then "1" else "0" end),
        $overall,
        $fail_open,
        $contradiction,
        $shallow,
        $conversation_id,
        $run_event_id
      ] | @tsv
    '
}

emit_summary_json() {
  score_file=$1
  summary_file=$2
  awk -F '\t' '
    NR==1 { next }
    {
      rows += 1
      if ($8 == "done") done += 1
      line_count_total += ($9 + 0)
      labels_exact_total += ($10 + 0)
      exact_total += ($11 + 0)
      required_total += ($12 + 0)
      forbidden_total += ($13 + 0)
      owner_window_total += ($14 + 0)
      overall_total += ($15 + 0)
      fail_open_total += ($16 + 0)
      contradiction_total += ($17 + 0)
      shallow_total += ($18 + 0)
    }
    END {
      total = rows
      if (total < 1) total = 1
      printf "{\"tasks\":%d,\"done\":%d,\"avg_line_count\":%.2f,\"labels_exact_once_rate\":%.4f,\"exact_contract_rate\":%.4f,\"avg_required_ratio\":%.4f,\"forbidden_hit_rate\":%.4f,\"owner_window_rate\":%.4f,\"avg_overall\":%.2f,\"fail_open_rate\":%.4f,\"contradiction_rate\":%.4f,\"shallow_completion_rate\":%.4f}\n", \
        rows + 0, done + 0, line_count_total / total, labels_exact_total / total, exact_total / total, required_total / total, forbidden_total / total, owner_window_total / total, overall_total / total, fail_open_total / total, contradiction_total / total, shallow_total / total
    }
  ' "$score_file" > "$summary_file"
}

render_report() {
  label=$1
  score_file=$2
  summary_file=$3
  report_file=$4

  {
    printf '# Compact Reasoning Assay Report: %s\n\n' "$label"
    printf '## Summary\n'
    printf -- '- Average overall score: %s\n' "$(jq -r '.avg_overall' "$summary_file")"
    printf -- '- Exact contract rate: %s\n' "$(jq -r '.exact_contract_rate' "$summary_file")"
    printf -- '- Labels-exact-once rate: %s\n' "$(jq -r '.labels_exact_once_rate' "$summary_file")"
    printf -- '- Average required-pattern ratio: %s\n' "$(jq -r '.avg_required_ratio' "$summary_file")"
    printf -- '- Owner-window rate: %s\n' "$(jq -r '.owner_window_rate' "$summary_file")"
    printf -- '- Fail-open rate: %s\n' "$(jq -r '.fail_open_rate' "$summary_file")"
    printf -- '- Contradiction rate: %s\n' "$(jq -r '.contradiction_rate' "$summary_file")"
    printf -- '- Shallow-completion rate: %s\n' "$(jq -r '.shallow_completion_rate' "$summary_file")"

    printf '\n## Task Scores\n'
    printf '| Task | Variant | Status | Lines | Labels Exact | Exact Contract | Required Ratio | Forbidden Hits | Owner/Window | Overall |\n'
    printf '|---|---|---|---:|---:|---:|---:|---:|---:|---:|\n'
    awk -F '\t' 'NR>1 { printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $6, $8, $9, $10, $11, $12, $13, $14, $15 }' "$score_file"
  } > "$report_file"
}

run_transfer_gap_analysis() {
  label=$1
  battery_summary=$2
  holdout_summary=$3
  out_json=$4
  out_report=$5

  jq -n \
    --arg label "$label" \
    --slurpfile battery "$battery_summary" \
    --slurpfile holdout "$holdout_summary" '
      def nz(x): if x == null then 0 else x end;
      ($battery[0] // {}) as $b |
      ($holdout[0] // {}) as $h |
      ((nz($h.avg_overall) - nz($b.avg_overall))) as $delta_overall |
      ((nz($h.avg_required_ratio) - nz($b.avg_required_ratio))) as $delta_required |
      ((nz($h.exact_contract_rate) - nz($b.exact_contract_rate))) as $delta_exact |
      ((nz($h.owner_window_rate) - nz($b.owner_window_rate))) as $delta_owner_window |
      ((nz($h.fail_open_rate) - nz($b.fail_open_rate))) as $delta_fail_open |
      ((nz($h.contradiction_rate) - nz($b.contradiction_rate))) as $delta_contradiction |
      {
        label: $label,
        battery: $b,
        holdout: $h,
        deltas: {
          overall: $delta_overall,
          required_ratio: $delta_required,
          exact_contract_rate: $delta_exact,
          owner_window_rate: $delta_owner_window,
          fail_open_rate: $delta_fail_open,
          contradiction_rate: $delta_contradiction
        },
        gates: {
          fail_open_non_increase: ($delta_fail_open <= 0),
          contradiction_non_increase: ($delta_contradiction <= 0),
          holdout_not_worse_overall: ($delta_overall >= 0),
          exact_contract_full: ((nz($b.exact_contract_rate) >= 1) and (nz($h.exact_contract_rate) >= 1)),
          required_ratio_full: ((nz($b.avg_required_ratio) >= 1) and (nz($h.avg_required_ratio) >= 1)),
          owner_window_full: ((nz($b.owner_window_rate) >= 1) and (nz($h.owner_window_rate) >= 1))
        },
        all_gates_pass: (
          ($delta_fail_open <= 0) and
          ($delta_contradiction <= 0) and
          ($delta_overall >= 0) and
          ((nz($b.exact_contract_rate) >= 1) and (nz($h.exact_contract_rate) >= 1)) and
          ((nz($b.avg_required_ratio) >= 1) and (nz($h.avg_required_ratio) >= 1)) and
          ((nz($b.owner_window_rate) >= 1) and (nz($h.owner_window_rate) >= 1))
        ),
        transfer_risk: (
          if ($delta_fail_open > 0 or $delta_contradiction > 0 or $delta_overall < -2) then "high"
          elif ($delta_overall < 0 or $delta_exact < 0 or $delta_required < 0) then "medium"
          else "low"
          end
        )
      }
    ' > "$out_json"

  {
    printf '# Compact Transfer Gap Report: %s\n\n' "$label"
    printf '## Battery vs Holdout\n'
    printf -- '- Overall delta: %s\n' "$(jq -r '.deltas.overall' "$out_json")"
    printf -- '- Required-ratio delta: %s\n' "$(jq -r '.deltas.required_ratio' "$out_json")"
    printf -- '- Exact-contract delta: %s\n' "$(jq -r '.deltas.exact_contract_rate' "$out_json")"
    printf -- '- Owner-window delta: %s\n' "$(jq -r '.deltas.owner_window_rate' "$out_json")"
    printf -- '- Fail-open delta: %s\n' "$(jq -r '.deltas.fail_open_rate' "$out_json")"
    printf -- '- Contradiction delta: %s\n' "$(jq -r '.deltas.contradiction_rate' "$out_json")"

    printf '\n## Gate Check\n'
    printf -- '- no fail-open increase: %s\n' "$(jq -r '.gates.fail_open_non_increase' "$out_json")"
    printf -- '- no contradiction increase: %s\n' "$(jq -r '.gates.contradiction_non_increase' "$out_json")"
    printf -- '- holdout not worse overall: %s\n' "$(jq -r '.gates.holdout_not_worse_overall' "$out_json")"
    printf -- '- exact contract full on battery+holdout: %s\n' "$(jq -r '.gates.exact_contract_full' "$out_json")"
    printf -- '- required ratio full on battery+holdout: %s\n' "$(jq -r '.gates.required_ratio_full' "$out_json")"
    printf -- '- owner/window full on battery+holdout: %s\n' "$(jq -r '.gates.owner_window_full' "$out_json")"
    printf -- '- all gates pass: %s\n' "$(jq -r '.all_gates_pass' "$out_json")"

    printf '\n## Risk\n'
    printf -- '- Transfer risk: %s\n' "$(jq -r '.transfer_risk' "$out_json")"
  } > "$out_report"
}

run_panel() {
  label=$1
  tasks_file=$2
  request_timeout_sec=$3
  settle_timeout_sec=$4

  mkdir -p "$OUT_DIR"
  mkdir -p "$ARTIFICER_ASSAY_RUNS_DIR/$label"
  raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
  mkdir -p "$raw_dir"

  score_file="$OUT_DIR/$label-scores.tsv"
  summary_file="$OUT_DIR/$label-summary.json"
  report_file="$OUT_DIR/$label-report.md"

  cleanup_compact_path=$(mktemp -d "${TMPDIR:-/tmp}/artificer-compact-workspace.XXXXXX")
  ws_json=$(post_api_json "action=add_workspace&path=$(urlenc "$cleanup_compact_path")&name=$(urlenc "Compact Reasoning $label")")
  cleanup_compact_ws_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id')
  if [ -z "$cleanup_compact_ws_id" ] || [ "$cleanup_compact_ws_id" = "null" ]; then
    echo "Failed to create compact workspace." >&2
    exit 1
  fi

  printf 'task_id\tmode\tbudget\tdomain\tpair_id\tvariant\ttactics\tstatus\tline_count\tlabels_exact_once\texact_contract\trequired_ratio\tforbidden_hits\towner_window_hit\toverall\tfail_open\tcontradiction\tshallow_completion\tconversation_id\trun_event_id\n' > "$score_file"

  tab_char=$(printf '\t')
  while IFS="$tab_char" read -r task_id mode budget domain pair_id variant tactics required_patterns forbidden_patterns prompt followup_prompt || [ -n "$task_id" ]; do
    task_id=$(trim "$task_id")
    [ -n "$task_id" ] || continue
    case "$task_id" in
      task_id) continue ;;
      \#*) continue ;;
    esac

    conv_title="${label}-${task_id}"
    conv_json=$(post_api_json "action=new_conversation&workspace_id=$(urlenc "$cleanup_compact_ws_id")&title=$(urlenc "$conv_title")")
    conv_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id')
    if [ -z "$conv_id" ] || [ "$conv_id" = "null" ]; then
      echo "Failed to create compact conversation for $task_id" >&2
      exit 1
    fi

    run_compact_turn "$cleanup_compact_ws_id" "$conv_id" "$prompt" "$request_timeout_sec" "$settle_timeout_sec"
    initial_state_json=$turn_state_json
    initial_assistant_text=$turn_assistant_text
    initial_run_event_id=$turn_run_event_id
    initial_run_status=$turn_run_status
    initial_stream_text=$turn_stream_text

    state_json=$initial_state_json
    assistant_text=$initial_assistant_text
    run_event_id=$initial_run_event_id
    run_status=$initial_run_status
    stream_text=$initial_stream_text

    followup_prompt=$(trim "${followup_prompt:-}")
    if [ -n "$followup_prompt" ] && [ "$run_status" = "done" ] && [ -n "$(trim "$assistant_text")" ]; then
      run_compact_turn "$cleanup_compact_ws_id" "$conv_id" "$followup_prompt" "$request_timeout_sec" "$settle_timeout_sec"
      state_json=$turn_state_json
      assistant_text=$turn_assistant_text
      run_event_id=$turn_run_event_id
      run_status=$turn_run_status
      stream_text=$turn_stream_text
    fi

    printf '%s\n' "$initial_state_json" > "$raw_dir/${task_id}-conversation-initial.json"
    printf '%s\n' "$(printf '%s' "$initial_state_json" | jq -c '.conversation.run_events[-1] // {}')" > "$raw_dir/${task_id}-event-initial.json"
    printf '%s\n' "$initial_assistant_text" > "$raw_dir/${task_id}-assistant-initial.txt"
    printf '%s\n' "$initial_stream_text" > "$raw_dir/${task_id}-stream-initial.txt"
    printf '%s\n' "$state_json" > "$raw_dir/${task_id}-conversation.json"
    printf '%s\n' "$(printf '%s' "$state_json" | jq -c '.conversation.run_events[-1] // {}')" > "$raw_dir/${task_id}-event.json"
    printf '%s\n' "$assistant_text" > "$raw_dir/${task_id}-assistant.txt"
    printf '%s\n' "$stream_text" > "$raw_dir/${task_id}-stream.txt"

    row=$(score_compact_row "$assistant_text" "$run_status" "$task_id" "$mode" "$budget" "$domain" "$pair_id" "$variant" "$tactics" "$required_patterns" "$forbidden_patterns" "$conv_id" "$run_event_id")
    printf '%s\n' "$row" >> "$score_file"
    echo "compact[$label] done: $task_id" >&2
  done < "$tasks_file"

  emit_summary_json "$score_file" "$summary_file"
  render_report "$label" "$score_file" "$summary_file" "$report_file"

  printf '%s\n' "$score_file"
  printf '%s\n' "$summary_file"
  printf '%s\n' "$report_file"
}

mode=${1:-}
if [ -z "$mode" ]; then
  usage
  exit 1
fi
shift

case "$mode" in
  run)
    label="compact-$(date +%Y%m%d-%H%M%S)"
    tasks_file="$DEFAULT_TASKS"
    request_timeout_sec=45
    settle_timeout_sec=45

    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --tasks-file)
          tasks_file=$2
          shift 2
          ;;
        --request-timeout-sec)
          request_timeout_sec=$2
          shift 2
          ;;
        --settle-timeout-sec)
          settle_timeout_sec=$2
          shift 2
          ;;
        --help|-h|--usage)
          usage
          exit 0
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage >&2
          exit 1
          ;;
      esac
    done

    if [ ! -f "$tasks_file" ]; then
      echo "Tasks file not found: $tasks_file" >&2
      exit 1
    fi

    run_panel "$label" "$tasks_file" "$request_timeout_sec" "$settle_timeout_sec"
    ;;
  transfer)
    label="compact-transfer-$(date +%Y%m%d-%H%M%S)"
    battery_summary=""
    holdout_summary=""
    enforce_transfer_gates=0

    while [ $# -gt 0 ]; do
      case "$1" in
        --label)
          label=$2
          shift 2
          ;;
        --battery-summary)
          battery_summary=$2
          shift 2
          ;;
        --holdout-summary)
          holdout_summary=$2
          shift 2
          ;;
        --enforce-gates)
          enforce_transfer_gates=1
          shift
          ;;
        --help|-h|--usage)
          usage
          exit 0
          ;;
        *)
          echo "Unknown arg: $1" >&2
          usage >&2
          exit 1
          ;;
      esac
    done

    if [ ! -f "$battery_summary" ]; then
      echo "Battery summary not found: $battery_summary" >&2
      exit 1
    fi
    if [ ! -f "$holdout_summary" ]; then
      echo "Holdout summary not found: $holdout_summary" >&2
      exit 1
    fi

    mkdir -p "$OUT_DIR"
    transfer_json="$OUT_DIR/$label-transfer.json"
    transfer_report="$OUT_DIR/$label-transfer.md"
    run_transfer_gap_analysis "$label" "$battery_summary" "$holdout_summary" "$transfer_json" "$transfer_report"
    printf '%s\n' "$transfer_json"
    printf '%s\n' "$transfer_report"
    if [ "$enforce_transfer_gates" -eq 1 ]; then
      if ! jq -e '.all_gates_pass == true' "$transfer_json" >/dev/null 2>&1; then
        echo "Compact transfer gates failed for label '$label'." >&2
        exit 2
      fi
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
