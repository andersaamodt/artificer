#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

PROBE_SCRIPT="$SCRIPT_DIR/current-ops-guidance-probe.sh"
DEFAULT_REGRESSIONS="$SITE_ROOT/tests/fixtures/artificer-current-ops-guidance-regressions-v1.tsv"
DEFAULT_HOLDOUT="$SITE_ROOT/tests/fixtures/artificer-current-ops-guidance-holdout-v1.tsv"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"

usage() {
  cat <<'EOF_USAGE'
Usage:
  current-ops-guidance-cycle.sh run [--profile regressions|holdout] [--label LABEL]
  current-ops-guidance-cycle.sh transfer --regressions-report PATH --holdout-report PATH [--label LABEL]
EOF_USAGE
}

[ -x "$PROBE_SCRIPT" ] || {
  echo "current-ops-guidance-probe.sh is not executable: $PROBE_SCRIPT" >&2
  exit 1
}

run_profile() {
  profile=$1
  label=$2
  case "$profile" in
    regressions)
      tasks_file=$DEFAULT_REGRESSIONS
      ;;
    holdout)
      tasks_file=$DEFAULT_HOLDOUT
      ;;
    *)
      echo "Unknown profile: $profile" >&2
      exit 1
      ;;
  esac

  mkdir -p "$OUT_DIR"
  summary_json="$OUT_DIR/$label-summary.json"
  summary_md="$OUT_DIR/$label-summary.md"
  total=0
  passes=0
  failures=0
  rows_json=""
  first_row=1

  {
    IFS=$(printf '\t')
    read -r _header || exit 1
    while IFS=$(printf '\t') read -r task_id scenario prompt; do
      [ -n "$task_id" ] || continue
      total=$((total + 1))
      row_label="${label}-${task_id}"
      prompt_file=$(mktemp)
      printf '%s\n' "$prompt" > "$prompt_file"
      set +e
      probe_output=$(sh "$PROBE_SCRIPT" --label "$row_label" --scenario "$scenario" --prompt-file "$prompt_file" 2>&1)
      probe_rc=$?
      set -e
      rm -f "$prompt_file"
      row_json=$(printf '%s\n' "$probe_output" | sed -n '1p')
      if [ "$probe_rc" -eq 0 ] && [ -f "$row_json" ]; then
        row_status=$(jq -r '.status // "fail"' "$row_json")
      else
        row_status="fail"
        row_json=""
      fi
      if [ "$row_status" = "pass" ]; then
        passes=$((passes + 1))
      else
        failures=$((failures + 1))
      fi
      if [ -n "$row_json" ] && [ -f "$row_json" ]; then
        row_payload=$(cat "$row_json")
      else
        row_payload=$(jq -n \
          --arg label "$row_label" \
          --arg scenario "$scenario" \
          --arg output "$probe_output" \
          --argjson probe_rc "$probe_rc" \
          '{label:$label,scenario:$scenario,status:"fail",probe_rc:$probe_rc,probe_output:$output}')
      fi
      if [ "$first_row" -eq 1 ]; then
        rows_json=$row_payload
        first_row=0
      else
        rows_json="$rows_json,$row_payload"
      fi
    done
  } < "$tasks_file"

  pass_rate=$(awk -v p="$passes" -v t="$total" 'BEGIN { if (t == 0) printf "0.0000"; else printf "%.4f", p / t }')
  all_pass=false
  if [ "$failures" -eq 0 ] && [ "$total" -gt 0 ]; then
    all_pass=true
  fi

  printf '{"label":"%s","profile":"%s","total":%s,"passes":%s,"failures":%s,"pass_rate":%s,"all_pass":%s,"rows":[%s]}\n' \
    "$label" "$profile" "$total" "$passes" "$failures" "$pass_rate" "$all_pass" "$rows_json" > "$summary_json"

  {
    printf '# Current Ops Guidance %s\n\n' "$label"
    printf -- '- Profile: %s\n' "$profile"
    printf -- '- Total: %s\n' "$total"
    printf -- '- Passes: %s\n' "$passes"
    printf -- '- Failures: %s\n' "$failures"
    printf -- '- Pass rate: %s\n' "$pass_rate"
    printf -- '- All pass: %s\n' "$all_pass"
  } > "$summary_md"

  printf '%s\n' "$summary_json"
  printf '%s\n' "$summary_md"
  [ "$all_pass" = true ]
}

run_transfer() {
  regressions_report=$1
  holdout_report=$2
  label=$3
  mkdir -p "$OUT_DIR"
  transfer_json="$OUT_DIR/$label-transfer.json"
  transfer_md="$OUT_DIR/$label-transfer.md"
  reg_pass_rate=$(jq -r '.pass_rate // 0' "$regressions_report")
  hold_pass_rate=$(jq -r '.pass_rate // 0' "$holdout_report")
  reg_all_pass=$(jq -r '.all_pass // false' "$regressions_report")
  hold_all_pass=$(jq -r '.all_pass // false' "$holdout_report")
  transfer_risk=high
  all_gates_pass=false
  if [ "$reg_all_pass" = "true" ] && [ "$hold_all_pass" = "true" ]; then
    transfer_risk=low
    all_gates_pass=true
  fi
  printf '{"label":"%s","regressions_report":"%s","holdout_report":"%s","regressions_pass_rate":%s,"holdout_pass_rate":%s,"all_gates_pass":%s,"transfer_risk":"%s"}\n' \
    "$label" "$regressions_report" "$holdout_report" "$reg_pass_rate" "$hold_pass_rate" "$all_gates_pass" "$transfer_risk" > "$transfer_json"
  {
    printf '# Current Ops Guidance Transfer %s\n\n' "$label"
    printf -- '- Regressions report: %s\n' "$regressions_report"
    printf -- '- Holdout report: %s\n' "$holdout_report"
    printf -- '- Regressions pass rate: %s\n' "$reg_pass_rate"
    printf -- '- Holdout pass rate: %s\n' "$hold_pass_rate"
    printf -- '- All gates pass: %s\n' "$all_gates_pass"
    printf -- '- Transfer risk: %s\n' "$transfer_risk"
  } > "$transfer_md"
  printf '%s\n' "$transfer_json"
  printf '%s\n' "$transfer_md"
  [ "$all_gates_pass" = true ]
}

command_name=${1:-}
[ -n "$command_name" ] || {
  usage >&2
  exit 1
}
shift

case "$command_name" in
  run)
    profile="regressions"
    label=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --profile)
          profile=${2:-}
          shift 2
          ;;
        --label)
          label=${2:-}
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
    if [ -z "$label" ]; then
      label="current-ops-guidance-v1-$profile"
    fi
    run_profile "$profile" "$label"
    ;;
  transfer)
    regressions_report=""
    holdout_report=""
    label="current-ops-guidance-v1-transfer"
    while [ $# -gt 0 ]; do
      case "$1" in
        --regressions-report)
          regressions_report=${2:-}
          shift 2
          ;;
        --holdout-report)
          holdout_report=${2:-}
          shift 2
          ;;
        --label)
          label=${2:-}
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
    [ -n "$regressions_report" ] || { echo "Missing --regressions-report" >&2; exit 1; }
    [ -n "$holdout_report" ] || { echo "Missing --holdout-report" >&2; exit 1; }
    run_transfer "$regressions_report" "$holdout_report" "$label"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage >&2
    exit 1
    ;;
esac
