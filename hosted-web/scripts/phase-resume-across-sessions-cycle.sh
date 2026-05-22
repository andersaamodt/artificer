#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

SMOKE_SCRIPT="$SCRIPT_DIR/programming-branchy-slice-smoke.sh"
DEFAULT_REGRESSIONS="$SITE_ROOT/tests/fixtures/artificer-phase-resume-across-sessions-regressions-v1.tsv"
DEFAULT_HOLDOUT="$SITE_ROOT/tests/fixtures/artificer-phase-resume-across-sessions-holdout-v1.tsv"
OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"

usage() {
  cat <<'EOF_USAGE'
Usage:
  phase-resume-across-sessions-cycle.sh run [--profile regressions|holdout] [--label LABEL]
  phase-resume-across-sessions-cycle.sh transfer --regressions-report PATH --holdout-report PATH [--label LABEL]
EOF_USAGE
}

[ -x "$SMOKE_SCRIPT" ] || {
  echo "programming-branchy-slice-smoke.sh is not executable: $SMOKE_SCRIPT" >&2
  exit 1
}

run_profile() {
  profile=$1
  label=$2
  case "$profile" in
    regressions)
      fixtures_file=$DEFAULT_REGRESSIONS
      ;;
    holdout)
      fixtures_file=$DEFAULT_HOLDOUT
      ;;
    *)
      echo "Unknown profile: $profile" >&2
      exit 1
      ;;
  esac

  mkdir -p "$OUT_DIR"
  summary_json="$OUT_DIR/$label-summary.json"
  summary_md="$OUT_DIR/$label-summary.md"

  set +e
  sh "$SMOKE_SCRIPT" --label "$label" --fixtures "$fixtures_file" >/tmp/${label}.out 2>/tmp/${label}.err
  smoke_rc=$?
  set -e

  smoke_json="$OUT_DIR/$label.json"
  smoke_md="$OUT_DIR/$label.md"
  if [ ! -f "$smoke_json" ]; then
    probe_stdout=$(cat /tmp/${label}.out 2>/dev/null || true)
    probe_stderr=$(cat /tmp/${label}.err 2>/dev/null || true)
    rm -f /tmp/${label}.out /tmp/${label}.err
    echo "Smoke report missing for $label" >&2
    jq -n \
      --arg label "$label" \
      --arg profile "$profile" \
      --arg stdout "$probe_stdout" \
      --arg stderr "$probe_stderr" \
      --argjson smoke_rc "$smoke_rc" \
      '{label:$label,profile:$profile,total:0,passes:0,failures:1,pass_rate:0,all_pass:false,smoke_rc:$smoke_rc,stdout:$stdout,stderr:$stderr,rows:[]}' > "$summary_json"
    {
      printf '# Phase Resume Across Sessions %s\n\n' "$label"
      printf -- '- Profile: %s\n' "$profile"
      printf -- '- Smoke rc: %s\n' "$smoke_rc"
      printf -- '- Missing smoke JSON report\n'
    } > "$summary_md"
    printf '%s\n' "$summary_json"
    printf '%s\n' "$summary_md"
    return 1
  fi

  total=$(jq -r '.total // 0' "$smoke_json")
  passes=$(jq -r '.passes // 0' "$smoke_json")
  failures=$(jq -r '.failures // 0' "$smoke_json")
  pass_rate=$(awk -v p="$passes" -v t="$total" 'BEGIN { if (t == 0) printf "0.0000"; else printf "%.4f", p / t }')
  all_pass=false
  if [ "$failures" -eq 0 ] && [ "$total" -gt 0 ]; then
    all_pass=true
  fi
  jq -n \
    --arg label "$label" \
    --arg profile "$profile" \
    --arg smoke_json "$smoke_json" \
    --arg smoke_md "$smoke_md" \
    --argjson total "$total" \
    --argjson passes "$passes" \
    --argjson failures "$failures" \
    --argjson smoke_rc "$smoke_rc" \
    --argjson all_pass "$all_pass" \
    --argjson pass_rate "$pass_rate" \
    --slurpfile rows "$smoke_json" \
    '{label:$label,profile:$profile,smoke_json:$smoke_json,smoke_md:$smoke_md,total:$total,passes:$passes,failures:$failures,pass_rate:$pass_rate,all_pass:$all_pass,smoke_rc:$smoke_rc,rows:($rows[0].results // [])}' > "$summary_json"
  {
    printf '# Phase Resume Across Sessions %s\n\n' "$label"
    printf -- '- Profile: %s\n' "$profile"
    printf -- '- Smoke JSON: %s\n' "$smoke_json"
    printf -- '- Smoke Markdown: %s\n' "$smoke_md"
    printf -- '- Total: %s\n' "$total"
    printf -- '- Passes: %s\n' "$passes"
    printf -- '- Failures: %s\n' "$failures"
    printf -- '- Pass rate: %s\n' "$pass_rate"
    printf -- '- All pass: %s\n' "$all_pass"
  } > "$summary_md"
  rm -f /tmp/${label}.out /tmp/${label}.err
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
    printf '# Phase Resume Across Sessions Transfer %s\n\n' "$label"
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
      label="phase-resume-across-sessions-v1-$profile"
    fi
    run_profile "$profile" "$label"
    ;;
  transfer)
    regressions_report=""
    holdout_report=""
    label="phase-resume-across-sessions-v1-transfer"
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
