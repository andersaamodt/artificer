#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="dashboard-chart-read-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for dashboard chart read probe." >&2
  exit 1
fi
if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript is required for Safari screenshot capture." >&2
  exit 1
fi
if ! command -v screencapture >/dev/null 2>&1; then
  echo "screencapture is required for Safari screenshot capture." >&2
  exit 1
fi

usage() {
  cat <<'EOF_USAGE'
Usage: dashboard-chart-read-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Renders a deterministic dashboard chart or table in Safari, uploads the image
through Artificer attachments, runs a vision-capable model, and verifies that
the answer reads the visual correctly with a concrete finding, evidence, risk,
and next check.
EOF_USAGE
}

uri() {
  jq -nr --arg v "$1" '$v|@uri'
}

json_escape() {
  printf '%s' "$1" | jq -Rs '.'
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

file_uri_from_path() {
  python3 - "$1" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
}

render_chart_page() {
  scenario=$1
  html_path=$2
  case "$scenario" in
    regional-backlog-bars)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Regional Backlog</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eef2ff 0%, #dbeafe 100%);
    color: #0f172a;
  }
  .page {
    padding: 30px 34px 38px;
  }
  h1 {
    margin: 0;
    font-size: 38px;
  }
  .sub {
    margin-top: 8px;
    font-size: 18px;
    color: #475569;
  }
  .frame {
    margin-top: 24px;
    background: white;
    border-radius: 26px;
    padding: 28px 28px 24px;
    box-shadow: 0 24px 60px rgba(15, 23, 42, 0.12);
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: end;
    gap: 20px;
  }
  .summary {
    margin-top: 20px;
    display: inline-flex;
    align-items: baseline;
    gap: 12px;
    border-radius: 24px;
    background: #fef2f2;
    color: #991b1b;
    padding: 16px 20px;
  }
  .summary strong {
    font-size: 42px;
    line-height: 1;
  }
  .summary span {
    font-size: 22px;
    font-weight: 800;
  }
  .header h2 {
    margin: 0;
    font-size: 23px;
  }
  .header .note {
    color: #991b1b;
    font-size: 16px;
    font-weight: 700;
  }
  .bars {
    margin-top: 26px;
    display: flex;
    align-items: end;
    gap: 28px;
    height: 330px;
    padding: 0 10px 10px;
    border-bottom: 2px solid #cbd5e1;
  }
  .bar-wrap {
    width: 150px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }
  .bar-value {
    font-size: 30px;
    font-weight: 800;
  }
  .bar {
    width: 112px;
    border-radius: 26px 26px 0 0;
    display: flex;
    align-items: start;
    justify-content: center;
    color: white;
    font-size: 22px;
    font-weight: 800;
    padding-top: 12px;
  }
  .us { height: 96px; background: #2563eb; }
  .eu { height: 274px; background: #dc2626; }
  .apac { height: 136px; background: #0f766e; }
  .latam { height: 112px; background: #7c3aed; }
  .bar-label {
    font-size: 20px;
    font-weight: 800;
  }
  .footer {
    margin-top: 18px;
    display: flex;
    gap: 14px;
    flex-wrap: wrap;
  }
  .alert {
    margin-top: 18px;
    display: inline-flex;
    align-items: center;
    border-radius: 16px;
    background: #fef2f2;
    color: #991b1b;
    padding: 12px 16px;
    font-size: 18px;
    font-weight: 800;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    border-radius: 999px;
    background: #eff6ff;
    color: #1d4ed8;
    padding: 10px 14px;
    font-size: 15px;
    font-weight: 700;
  }
</style>
</head>
<body>
  <main class="page">
    <h1>Regional backlog risk</h1>
    <div class="sub">Open tickets per region for the current release week.</div>
    <section class="frame">
      <div class="header">
        <div>
          <h2>Backlog by region</h2>
          <div class="sub">Red means the queue is above the support-safe threshold.</div>
        </div>
        <div class="note">EU is over threshold</div>
      </div>
      <div class="summary"><strong>EU 92</strong><span>highest backlog</span></div>
      <div class="bars">
        <div class="bar-wrap">
          <div class="bar-value">24</div>
          <div class="bar us">24</div>
          <div class="bar-label">US</div>
        </div>
        <div class="bar-wrap">
          <div class="bar-value">92</div>
          <div class="bar eu">92</div>
          <div class="bar-label">EU</div>
        </div>
        <div class="bar-wrap">
          <div class="bar-value">38</div>
          <div class="bar apac">38</div>
          <div class="bar-label">APAC</div>
        </div>
        <div class="bar-wrap">
          <div class="bar-value">29</div>
          <div class="bar latam">29</div>
          <div class="bar-label">LATAM</div>
        </div>
      </div>
      <div class="alert">Highest backlog: EU 92 tickets</div>
      <div class="footer">
        <div class="pill">Threshold: 60 tickets</div>
        <div class="pill">Escalate the highest region first</div>
      </div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    activation-funnel-table)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Activation Funnel</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #fff7ed 0%, #ffedd5 100%);
    color: #111827;
  }
  .page {
    padding: 30px 34px 40px;
  }
  h1 {
    margin: 0;
    font-size: 38px;
  }
  .sub {
    margin-top: 8px;
    font-size: 18px;
    color: #475569;
  }
  .frame {
    margin-top: 24px;
    background: white;
    border-radius: 26px;
    padding: 24px 24px 20px;
    box-shadow: 0 24px 60px rgba(15, 23, 42, 0.10);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 10px;
  }
  th, td {
    text-align: left;
    padding: 16px 14px;
    border-bottom: 1px solid #e5e7eb;
    font-size: 18px;
  }
  th {
    font-size: 14px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #64748b;
  }
  .pct {
    font-weight: 800;
    font-size: 24px;
  }
  .good { color: #0f766e; }
  .warn { color: #b45309; }
  .bad { color: #dc2626; }
  .badge {
    margin-top: 16px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    border-radius: 999px;
    background: #fef2f2;
    color: #991b1b;
    padding: 10px 14px;
    font-weight: 800;
  }
  .summary {
    margin-top: 18px;
    display: inline-flex;
    align-items: baseline;
    gap: 12px;
    border-radius: 24px;
    background: #fef2f2;
    color: #991b1b;
    padding: 16px 20px;
  }
  .summary strong {
    font-size: 42px;
    line-height: 1;
  }
  .summary span {
    font-size: 22px;
    font-weight: 800;
  }
  .highlight-row td {
    background: #fef2f2;
  }
</style>
</head>
<body>
  <main class="page">
    <h1>Self-serve activation funnel</h1>
    <div class="sub">Step conversion for new workspace creation this week.</div>
    <section class="frame">
      <div class="summary"><strong>Paid 28%</strong><span>weakest step</span></div>
      <table aria-label="Activation funnel">
        <thead>
          <tr>
            <th>Step</th>
            <th>Conversion</th>
            <th>Signal</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>Signup</td>
            <td class="pct good">84%</td>
            <td>Stable</td>
          </tr>
          <tr>
            <td>Install</td>
            <td class="pct good">67%</td>
            <td>Within range</td>
          </tr>
          <tr>
            <td>First run</td>
            <td class="pct warn">51%</td>
            <td>Monitor</td>
          </tr>
          <tr class="highlight-row">
            <td>Paid</td>
            <td class="pct bad">28%</td>
            <td>Largest drop</td>
          </tr>
        </tbody>
      </table>
      <div class="badge">Weakest step: Paid 28%</div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    latency-spike-line)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Latency Spike</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #ecfeff 0%, #cffafe 100%);
    color: #0f172a;
  }
  .page {
    padding: 30px 34px 42px;
  }
  h1 {
    margin: 0;
    font-size: 38px;
  }
  .sub {
    margin-top: 8px;
    font-size: 18px;
    color: #475569;
  }
  .frame {
    margin-top: 24px;
    background: white;
    border-radius: 26px;
    padding: 24px;
    box-shadow: 0 24px 60px rgba(15, 23, 42, 0.10);
  }
  .legend {
    display: flex;
    gap: 18px;
    align-items: center;
    color: #475569;
    font-size: 15px;
  }
  .legend span::before {
    content: "";
    display: inline-block;
    width: 12px;
    height: 12px;
    border-radius: 999px;
    margin-right: 8px;
    vertical-align: middle;
  }
  .legend .latency::before { background: #0891b2; }
  .legend .spike::before { background: #dc2626; }
  .note {
    margin-top: 14px;
    color: #991b1b;
    font-weight: 800;
    font-size: 16px;
  }
  .alert {
    margin-top: 14px;
    display: inline-flex;
    align-items: center;
    border-radius: 16px;
    background: #fef2f2;
    color: #991b1b;
    padding: 12px 16px;
    font-size: 18px;
    font-weight: 800;
  }
  .summary {
    margin-top: 18px;
    display: inline-flex;
    align-items: baseline;
    gap: 12px;
    border-radius: 24px;
    background: #fef2f2;
    color: #991b1b;
    padding: 16px 20px;
  }
  .summary strong {
    font-size: 42px;
    line-height: 1;
  }
  .summary span {
    font-size: 22px;
    font-weight: 800;
  }
  .axis {
    font-size: 15px;
    fill: #475569;
  }
  .value {
    font-size: 16px;
    font-weight: 800;
    fill: #dc2626;
  }
</style>
</head>
<body>
  <main class="page">
    <h1>API latency trend</h1>
    <div class="sub">Median response time by hour after the latest release window.</div>
    <section class="frame">
      <div class="legend">
        <span class="latency">Median latency</span>
        <span class="spike">Peak alert</span>
      </div>
      <div class="summary"><strong>14:00 / 92s</strong><span>peak spike</span></div>
      <svg width="760" height="340" viewBox="0 0 760 340" role="img" aria-label="Latency line chart">
        <line x1="70" y1="280" x2="710" y2="280" stroke="#cbd5e1" stroke-width="2" />
        <line x1="70" y1="60" x2="70" y2="280" stroke="#cbd5e1" stroke-width="2" />
        <text x="30" y="280" class="axis">0s</text>
        <text x="24" y="200" class="axis">30s</text>
        <text x="24" y="120" class="axis">60s</text>
        <text x="24" y="70" class="axis">90s</text>
        <polyline fill="none" stroke="#0891b2" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"
          points="90,240 190,228 290,218 390,74 490,212 590,222 690,234" />
        <circle cx="90" cy="240" r="7" fill="#0891b2" />
        <circle cx="190" cy="228" r="7" fill="#0891b2" />
        <circle cx="290" cy="218" r="7" fill="#0891b2" />
        <circle cx="390" cy="74" r="10" fill="#dc2626" />
        <circle cx="490" cy="212" r="7" fill="#0891b2" />
        <circle cx="590" cy="222" r="7" fill="#0891b2" />
        <circle cx="690" cy="234" r="7" fill="#0891b2" />
        <text x="372" y="52" class="value">92s</text>
        <text x="82" y="308" class="axis">11:00</text>
        <text x="182" y="308" class="axis">12:00</text>
        <text x="282" y="308" class="axis">13:00</text>
        <text x="382" y="308" class="axis">14:00</text>
        <text x="482" y="308" class="axis">15:00</text>
        <text x="582" y="308" class="axis">16:00</text>
        <text x="682" y="308" class="axis">17:00</text>
      </svg>
      <div class="alert">Peak: 14:00 at 92s</div>
      <div class="note">The spike lines up with the 14:00 release.</div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    *)
      echo "Unknown --scenario value: $scenario" >&2
      exit 1
      ;;
  esac
}

capture_safari_screenshot() {
  page_path=$1
  screenshot_path=$2
  page_uri=$(file_uri_from_path "$page_path")
  bounds_csv=$(osascript <<EOF_APPLESCRIPT
set targetUrl to "$page_uri"
tell application "Safari"
  activate
  make new document with properties {URL:targetUrl}
  set bounds of front window to {70, 56, 1120, 980}
end tell
repeat 40 times
  delay 0.25
  tell application "Safari"
    try
      set readyState to do JavaScript "document.readyState" in current tab of front window
      set titleText to do JavaScript "document.title || ''" in current tab of front window
    on error
      set readyState to ""
      set titleText to ""
    end try
  end tell
  if readyState is "complete" and titleText is not "" then
    exit repeat
  end if
end repeat
tell application "Safari"
  try
    do JavaScript "window.scrollTo(0,0); document.body.style.zoom='135%';" in current tab of front window
  end try
  set b to bounds of front window
  return (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text)
end tell
EOF_APPLESCRIPT
)
  x1=$(printf '%s' "$bounds_csv" | awk -F',' '{print $1}')
  y1=$(printf '%s' "$bounds_csv" | awk -F',' '{print $2}')
  x2=$(printf '%s' "$bounds_csv" | awk -F',' '{print $3}')
  y2=$(printf '%s' "$bounds_csv" | awk -F',' '{print $4}')
  width=$((x2 - x1))
  height=$((y2 - y1))
  chrome_side=14
  chrome_top=92
  chrome_bottom=18
  shot_x=$((x1 + chrome_side))
  shot_y=$((y1 + chrome_top))
  shot_w=$((width - (chrome_side * 2)))
  shot_h=$((height - chrome_top - chrome_bottom))
  screencapture -x -R"$shot_x,$shot_y,$shot_w,$shot_h" "$screenshot_path"
  osascript <<'EOF_APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Safari"
  try
    close front window
  end try
end tell
EOF_APPLESCRIPT
}

text_has_any() {
  haystack=$1
  shift
  for needle in "$@"; do
    case "$haystack" in
      *"$needle"*)
        return 0
        ;;
    esac
  done
  return 1
}

score_chart_answer() {
  scenario=$1
  answer_lower=$2
  finding_ref=0
  evidence_ref=0
  risk_ref=0
  next_check_ref=0
  case "$scenario" in
    regional-backlog-bars)
      text_has_any "$answer_lower" "eu" "europe" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "92" "highest" "tallest" "over threshold" "red bar"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "backlog" "queue" "delay" "support" "sla" && risk_ref=1
      text_has_any "$answer_lower" "investigate" "check" "triage" "compare" "drill" "confirm" && next_check_ref=1
      ;;
    activation-funnel-table)
      text_has_any "$answer_lower" "paid" "payment" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "28%" "largest drop" "lowest" "weakest"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "conversion" "revenue" "drop" "funnel" "paid" && risk_ref=1
      text_has_any "$answer_lower" "cohort" "check" "compare" "instrument" "device" "verify" && next_check_ref=1
      ;;
    latency-spike-line)
      text_has_any "$answer_lower" "14:00" "14" "2:00" "spike" "latency" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "92s" "92" "peak" "release"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "timeout" "incident" "latency" "release" "user impact" && risk_ref=1
      text_has_any "$answer_lower" "logs" "deploy" "correlat" "check" "investigate" "verify" && next_check_ref=1
      ;;
  esac
  printf '%s %s %s %s\n' "$finding_ref" "$evidence_ref" "$risk_ref" "$next_check_ref"
}

label=$DEFAULT_LABEL
scenario="regional-backlog-bars"
prompt_override=""
prompt_file=""
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

case "$scenario" in
  regional-backlog-bars|activation-funnel-table|latency-spike-line)
    ;;
  *)
    echo "Unknown --scenario value: $scenario" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_DIR" "$ARTIFICER_ASSAY_RUNS_DIR/$label"
raw_dir="$ARTIFICER_ASSAY_RUNS_DIR/$label/raw"
mkdir -p "$raw_dir"

json_file="$OUT_DIR/$label.json"
md_file="$OUT_DIR/$label.md"
page_html="$raw_dir/$scenario.html"
screenshot_png="$raw_dir/$scenario.png"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("llava:7b")) then "llava:7b"
  else ""
  end
')
[ -n "$model" ] || { echo "llava:7b is required for dashboard chart read probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# Dashboard Chart Read Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed chart-reading conversation.
EOF_README

render_chart_page "$scenario" "$page_html"
capture_safari_screenshot "$page_html" "$screenshot_png"

screenshot_exists=0
if [ -s "$screenshot_png" ]; then
  screenshot_exists=1
fi

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

attachment_uploaded=0
attachment_id=""
if [ "$screenshot_exists" -eq 1 ]; then
  screenshot_b64=$(base64 < "$screenshot_png" | tr -d '\n')
  upload_json=$(post_api_json "action=upload_attachment&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&name=$(uri "$scenario.png")&mime=$(uri "image/png")&data=$(uri "$screenshot_b64")")
  printf '%s\n' "$upload_json" > "$raw_dir/upload.json"
  attachment_id=$(printf '%s' "$upload_json" | jq -r '.attachment.id // ""')
  if [ -n "$attachment_id" ]; then
    attachment_uploaded=1
  fi
fi

default_prompt_text=$(cat <<'EOF_PROMPT'
Inspect the attached dashboard chart screenshot. Use only visible chart or table evidence. Respond in exactly four lines starting with `Finding:`, `Evidence:`, `Risk:`, and `Next Check:`. Identify the main anomaly or most important takeaway, cite the visual cue that proves it, explain the operational risk, and name one concrete next check.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=report&compute_budget=quick&advanced_loop=0&max_iterations=4&permission_mode=read-only&attachment_ids=$(uri "$attachment_id")&stream_session=$(uri "$stream_session")"
run_json=$(ARTIFICER_RUN_TIME_BUDGET_SEC=120 post_api_json_with_timeout "$run_body" 90)
printf '%s\n' "$run_json" > "$raw_dir/run.json"
timed_out=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then 1 else 0 end')
assistant_text=$(printf '%s' "$run_json" | jq -r 'if .__timed_out then "" else (.assistant // "") end')
printf '%s\n' "$assistant_text" > "$raw_dir/assistant.txt"
stream_json=$(post_api_json "action=run_stream_poll&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&stream_session=$(uri "$stream_session")&offset=0")
printf '%s\n' "$stream_json" > "$raw_dir/stream.json"
stream_text=$(printf '%s' "$stream_json" | jq -r '.delta // ""')
printf '%s\n' "$stream_text" > "$raw_dir/stream.txt"

assistant_lower=$(printf '%s' "$assistant_text" | tr '[:upper:]' '[:lower:]')
line_count=$(printf '%s\n' "$assistant_text" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
has_finding=$(printf '%s\n' "$assistant_lower" | grep -q '^finding:' && printf '1' || printf '0')
has_evidence=$(printf '%s\n' "$assistant_lower" | grep -q '^evidence:' && printf '1' || printf '0')
has_risk=$(printf '%s\n' "$assistant_lower" | grep -q '^risk:' && printf '1' || printf '0')
has_next_check=$(printf '%s\n' "$assistant_lower" | grep -q '^next check:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_finding" -eq 1 ] && [ "$has_evidence" -eq 1 ] && [ "$has_risk" -eq 1 ] && [ "$has_next_check" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_chart_answer "$scenario" "$assistant_lower")
finding_detected=$1
evidence_detected=$2
risk_detected=$3
next_check_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$screenshot_exists" -eq 1 ] && [ "$attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$finding_detected" -eq 1 ] && [ "$evidence_detected" -eq 1 ] \
  && [ "$risk_detected" -eq 1 ] && [ "$next_check_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"screenshot_exists":%s,"attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"finding_detected":%s,"evidence_detected":%s,"risk_detected":%s,"next_check_detected":%s,"line_count":%s,"screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$screenshot_exists" "$attachment_uploaded" "$sections_complete" "$no_disclaimer" "$finding_detected" "$evidence_detected" "$risk_detected" "$next_check_detected" "$line_count" "$(json_escape "$screenshot_png")" > "$json_file"

{
  printf '# Dashboard Chart Read Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Screenshot exists: %s\n' "$screenshot_exists"
  printf -- '- Attachment uploaded: %s\n' "$attachment_uploaded"
  printf -- '- Sections complete: %s\n' "$sections_complete"
  printf -- '- No disclaimer: %s\n' "$no_disclaimer"
  printf -- '- Finding detected: %s\n' "$finding_detected"
  printf -- '- Evidence detected: %s\n' "$evidence_detected"
  printf -- '- Risk detected: %s\n' "$risk_detected"
  printf -- '- Next check detected: %s\n' "$next_check_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Screenshot: %s\n' "$screenshot_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
