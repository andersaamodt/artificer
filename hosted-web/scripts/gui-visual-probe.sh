#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="gui-layout-triage-probe"
GUI_SCRIPT="$SCRIPT_DIR/gui-regression-system.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for GUI visual probe." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: gui-visual-probe.sh [--label NAME] [--browser auto|safari|firefox] [--profile PROFILE] [--required-checks CHECK1|CHECK2|...]

Runs a live GUI regression scenario and verifies that the expected check set is
present and passing for the selected browser/profile combination.
EOF_USAGE
}

json_escape() {
  printf '%s' "$1" | jq -Rs '.'
}

required_checks_default_for_profile() {
  profile_name=$1
  case "$profile_name" in
    core)
      cat <<'EOF_CHECKS'
three seeded conversations available
draft remains scoped to conversation A
queue edit journey persists updated prompt via queue API
archive journey keeps hash route on active conversation
live run status surfaces no-dead-air liveness hints
EOF_CHECKS
      ;;
    intelligence)
      cat <<'EOF_CHECKS'
interactive intelligence starts from default run mode
interactive causal scenario includes explicit revision contract
interactive security scenario includes claim-to-evidence map
interactive strategy scenario avoids generic cross-domain fallback
interactive strategy scenario settles before the next scenario
EOF_CHECKS
      ;;
    *)
      cat <<'EOF_CHECKS'
three seeded conversations available
EOF_CHECKS
      ;;
  esac
}

checks_raw_to_file() {
  checks_raw=$1
  out_file=$2
  if [ -z "$checks_raw" ]; then
    : > "$out_file"
    return 0
  fi
  printf '%s' "$checks_raw" | tr '|' '\n' | sed '/^[[:space:]]*$/d' > "$out_file"
}

label=$DEFAULT_LABEL
browser="auto"
profile="core"
required_checks_raw=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label)
      label=$2
      shift 2
      ;;
    --browser)
      browser=$2
      shift 2
      ;;
    --profile)
      profile=$2
      shift 2
      ;;
    --required-checks)
      required_checks_raw=$2
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

[ -x "$GUI_SCRIPT" ] || {
  echo "gui-regression-system.sh is not executable: $GUI_SCRIPT" >&2
  exit 1
}

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"
required_checks_file=$(mktemp)
present_checks_file=$(mktemp)
missing_checks_file=$(mktemp)
trap 'rm -f "$required_checks_file" "$present_checks_file" "$missing_checks_file"' EXIT INT TERM

if [ -n "$required_checks_raw" ]; then
  checks_raw_to_file "$required_checks_raw" "$required_checks_file"
else
  required_checks_default_for_profile "$profile" > "$required_checks_file"
fi

set +e
probe_output=$(sh "$GUI_SCRIPT" --browser "$browser" --profile "$profile" --label "$label" 2>&1)
probe_rc=$?
set -e
printf '%s\n' "$probe_output" > "$raw_dir/probe-output.txt"

result_json_path=$(printf '%s\n' "$probe_output" | sed -n '1p')
report_md_path=$(printf '%s\n' "$probe_output" | sed -n '2p')

status="fail"
failure_reason=""
success=false
checks_total=0
failed_check_count=0
present_required_count=0
required_total=0
missing_required_json='[]'
present_required_json='[]'
failed_checks_json='[]'

if [ "$probe_rc" -ne 0 ]; then
  failure_reason="gui regression command failed"
elif [ ! -f "$result_json_path" ]; then
  failure_reason="gui regression did not produce result json"
else
  success=$(jq -r 'if .success then "true" else "false" end' "$result_json_path" 2>/dev/null || printf '%s' "false")
  checks_total=$(jq -r '(.checks | length) // 0' "$result_json_path" 2>/dev/null || printf '%s' "0")
  failed_check_count=$(jq -r '[.checks[]? | select((.pass // false) | not)] | length' "$result_json_path" 2>/dev/null || printf '%s' "0")
  failed_checks_json=$(jq -c '[.checks[]? | select((.pass // false) | not) | .name]' "$result_json_path" 2>/dev/null || printf '%s' '[]')
  : > "$present_checks_file"
  : > "$missing_checks_file"
  while IFS= read -r required_check; do
    [ -n "$required_check" ] || continue
    required_total=$((required_total + 1))
    if jq -e --arg check_name "$required_check" '.checks[]? | select(.name == $check_name and (.pass // false) == true)' "$result_json_path" >/dev/null 2>&1; then
      printf '%s\n' "$required_check" >> "$present_checks_file"
    else
      printf '%s\n' "$required_check" >> "$missing_checks_file"
    fi
  done < "$required_checks_file"
  present_required_count=$(wc -l < "$present_checks_file" | tr -d ' ')
  missing_required_json=$(jq -Rs 'split("\n") | map(select(length > 0))' "$missing_checks_file")
  present_required_json=$(jq -Rs 'split("\n") | map(select(length > 0))' "$present_checks_file")
  if [ "$success" = "true" ] && [ "$checks_total" -gt 0 ] && [ "$required_total" -eq "$present_required_count" ]; then
    status="pass"
  else
    if [ "$success" != "true" ]; then
      failure_reason="scenario reported failure"
    elif [ "$checks_total" -le 0 ]; then
      failure_reason="scenario returned no checks"
    else
      failure_reason="required GUI checks missing"
    fi
  fi
fi

printf '{"label":%s,"status":%s,"browser":%s,"profile":%s,"probe_rc":%s,"success":%s,"checks_total":%s,"failed_check_count":%s,"required_total":%s,"present_required_count":%s,"missing_required_checks":%s,"present_required_checks":%s,"failed_checks":%s,"result_json_path":%s,"report_md_path":%s,"failure_reason":%s}\n' \
  "$(json_escape "$label")" \
  "$(json_escape "$status")" \
  "$(json_escape "$browser")" \
  "$(json_escape "$profile")" \
  "$probe_rc" \
  "$success" \
  "$checks_total" \
  "$failed_check_count" \
  "$required_total" \
  "$present_required_count" \
  "$missing_required_json" \
  "$present_required_json" \
  "$failed_checks_json" \
  "$(json_escape "$result_json_path")" \
  "$(json_escape "$report_md_path")" \
  "$(json_escape "$failure_reason")" > "$json_file"

{
  printf '# GUI Visual Probe %s\n\n' "$label"
  printf -- '- Browser: %s\n' "$browser"
  printf -- '- Profile: %s\n' "$profile"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Probe rc: %s\n' "$probe_rc"
  printf -- '- Success: %s\n' "$success"
  printf -- '- Checks total: %s\n' "$checks_total"
  printf -- '- Failed checks: %s\n' "$failed_check_count"
  printf -- '- Required checks present: %s/%s\n' "$present_required_count" "$required_total"
  printf -- '- Result JSON: %s\n' "$result_json_path"
  printf -- '- Report MD: %s\n' "$report_md_path"
  if [ -n "$failure_reason" ]; then
    printf -- '- Failure reason: %s\n' "$failure_reason"
  fi
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"

[ "$status" = "pass" ]
