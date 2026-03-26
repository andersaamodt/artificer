#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="terminal-screenshot-debug-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for terminal screenshot debug probe." >&2
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
Usage: terminal-screenshot-debug-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Renders a deterministic terminal or log screenshot in Safari, uploads the image
through Artificer attachments, runs a vision-capable model, and verifies that
the answer identifies the visible failure, cites the exact visible evidence,
names one concrete next command, and explains the operational risk.
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

render_terminal_page() {
  scenario=$1
  html_path=$2
  case "$scenario" in
    node-module-missing)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Node Module Missing</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: radial-gradient(circle at top, #1f2937 0%, #020617 70%);
    color: #e5e7eb;
  }
  .page {
    padding: 26px 28px 34px;
  }
  .lead {
    margin: 0 0 18px;
    font-size: 18px;
    color: #cbd5e1;
  }
  .terminal {
    background: #020617;
    border: 1px solid #334155;
    border-radius: 22px;
    box-shadow: 0 28px 80px rgba(2, 6, 23, 0.55);
    overflow: hidden;
  }
  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    background: #111827;
    border-bottom: 1px solid #334155;
    font-size: 18px;
    color: #cbd5e1;
  }
  .dots { display: flex; gap: 10px; }
  .dot { width: 13px; height: 13px; border-radius: 999px; }
  .red { background: #f87171; }
  .yellow { background: #fbbf24; }
  .green { background: #34d399; }
  pre {
    margin: 0;
    padding: 26px 28px 30px;
    font: 27px/1.58 SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    white-space: pre-wrap;
  }
  .cmd { color: #93c5fd; }
  .path { color: #fcd34d; }
  .err { color: #fca5a5; font-weight: 700; }
  .code { color: #fda4af; font-weight: 700; }
  .tip {
    margin-top: 18px;
    display: inline-flex;
    padding: 12px 16px;
    border-radius: 999px;
    background: #3f0d0d;
    color: #fecaca;
    font-size: 20px;
    font-weight: 700;
  }
</style>
</head>
<body>
  <main class="page">
    <p class="lead">Captured terminal output after trying to boot the local API.</p>
    <section class="terminal">
      <div class="toolbar">
        <div class="dots"><span class="dot red"></span><span class="dot yellow"></span><span class="dot green"></span></div>
        <div>api-dev.local</div>
        <div>node 20.12.2</div>
      </div>
      <pre><span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Loading env from <span class="path">.env.local</span>
<span class="err">Error: Cannot find module 'dotenv'</span>
Require stack:
- <span class="path">/srv/artificer/api/bootstrap.js</span>
- <span class="path">/srv/artificer/bin/dev-server.js</span>
<span class="code">code: 'MODULE_NOT_FOUND'</span>
Node.js v20.12.2</pre>
    </section>
    <div class="tip">Focus line: Cannot find module 'dotenv'</div>
  </main>
</body>
</html>
EOF_HTML
      ;;
    port-in-use)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Port Already In Use</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: radial-gradient(circle at top, #312e81 0%, #020617 72%);
    color: #e5e7eb;
  }
  .page { padding: 26px 28px 34px; }
  .lead { margin: 0 0 18px; font-size: 18px; color: #cbd5e1; }
  .terminal {
    background: #020617;
    border: 1px solid #334155;
    border-radius: 22px;
    box-shadow: 0 28px 80px rgba(2, 6, 23, 0.55);
    overflow: hidden;
  }
  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    background: #111827;
    border-bottom: 1px solid #334155;
    font-size: 18px;
    color: #cbd5e1;
  }
  .dots { display: flex; gap: 10px; }
  .dot { width: 13px; height: 13px; border-radius: 999px; }
  .red { background: #f87171; }
  .yellow { background: #fbbf24; }
  .green { background: #34d399; }
  pre {
    margin: 0;
    padding: 26px 28px 30px;
    font: 27px/1.58 SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    white-space: pre-wrap;
  }
  .cmd { color: #93c5fd; }
  .ok { color: #86efac; }
  .err { color: #fca5a5; font-weight: 700; }
  .tip {
    margin-top: 18px;
    display: inline-flex;
    padding: 12px 16px;
    border-radius: 999px;
    background: #3f0d0d;
    color: #fecaca;
    font-size: 20px;
    font-weight: 700;
  }
</style>
</head>
<body>
  <main class="page">
    <p class="lead">Captured terminal output after the frontend dev server restart.</p>
    <section class="terminal">
      <div class="toolbar">
        <div class="dots"><span class="dot red"></span><span class="dot yellow"></span><span class="dot green"></span></div>
        <div>frontend-dev.local</div>
        <div>vite 5.4.1</div>
      </div>
      <pre><span class="cmd">$ npm run dev</span>
> web@1.0.0 dev
> vite --host 0.0.0.0 --port 3000

<span class="err">Error: listen EADDRINUSE: address already in use :::3000</span>
    at Server.setupListenHandle [as _listen2] (node:net:1898:16)
    at listenInCluster (node:net:1955:12)
    at Server.listen (node:net:2057:7)
<span class="ok">Previous health check passed on http://localhost:3000/healthz</span></pre>
    </section>
    <div class="tip">Focus line: address already in use :::3000</div>
  </main>
</body>
</html>
EOF_HTML
      ;;
    db-connection-refused)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Database Connection Refused</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: radial-gradient(circle at top, #083344 0%, #020617 72%);
    color: #e5e7eb;
  }
  .page { padding: 26px 28px 34px; }
  .lead { margin: 0 0 18px; font-size: 18px; color: #cbd5e1; }
  .terminal {
    background: #020617;
    border: 1px solid #334155;
    border-radius: 22px;
    box-shadow: 0 28px 80px rgba(2, 6, 23, 0.55);
    overflow: hidden;
  }
  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    background: #111827;
    border-bottom: 1px solid #334155;
    font-size: 18px;
    color: #cbd5e1;
  }
  .dots { display: flex; gap: 10px; }
  .dot { width: 13px; height: 13px; border-radius: 999px; }
  .red { background: #f87171; }
  .yellow { background: #fbbf24; }
  .green { background: #34d399; }
  pre {
    margin: 0;
    padding: 26px 28px 30px;
    font: 27px/1.58 SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    white-space: pre-wrap;
  }
  .cmd { color: #93c5fd; }
  .err { color: #fca5a5; font-weight: 700; }
  .tip {
    margin-top: 18px;
    display: inline-flex;
    padding: 12px 16px;
    border-radius: 999px;
    background: #3f0d0d;
    color: #fecaca;
    font-size: 20px;
    font-weight: 700;
  }
</style>
</head>
<body>
  <main class="page">
    <p class="lead">Captured terminal output during the migration preflight check.</p>
    <section class="terminal">
      <div class="toolbar">
        <div class="dots"><span class="dot red"></span><span class="dot yellow"></span><span class="dot green"></span></div>
        <div>db-preflight.local</div>
        <div>postgres check</div>
      </div>
      <pre><span class="cmd">$ ./bin/run-migrations.sh --dry-run</span>
Checking database connectivity for app_main
<span class="err">psql: error: connection to server at "127.0.0.1", port 5432 failed: Connection refused</span>
<span class="err">Is the server running on that host and accepting TCP/IP connections?</span>
Migration preflight aborted.</pre>
    </section>
    <div class="tip">Focus line: connection refused on port 5432</div>
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
  set bounds of front window to {70, 56, 1180, 980}
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
    do JavaScript "window.scrollTo(0,0); document.body.style.zoom='140%';" in current tab of front window
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

score_terminal_answer() {
  scenario=$1
  answer_lower=$2
  finding_ref=0
  evidence_ref=0
  next_command_ref=0
  risk_ref=0
  case "$scenario" in
    node-module-missing)
      text_has_any "$answer_lower" "cannot find module" "module_not_found" "module not found" "dotenv" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "dotenv" "module_not_found" "cannot find module"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "npm install dotenv" "pnpm add dotenv" "yarn add dotenv" "npm install" && next_command_ref=1
      text_has_any "$answer_lower" "cannot start" "boot" "startup" "service" "app" "process" && risk_ref=1
      ;;
    port-in-use)
      text_has_any "$answer_lower" "eaddrinuse" "address already in use" "port 3000" ":::3000" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "3000" "eaddrinuse" "address already in use"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "lsof" "ss -ltnp" "kill" "pkill" "stop the process" && next_command_ref=1
      text_has_any "$answer_lower" "cannot bind" "cannot start" "won't start" "service" "dev server" "port" && risk_ref=1
      ;;
    db-connection-refused)
      text_has_any "$answer_lower" "connection refused" "5432" "postgres" "database" && finding_ref=1
      if [ "$finding_ref" -eq 1 ] && text_has_any "$answer_lower" "127.0.0.1" "5432" "connection refused"; then
        evidence_ref=1
      fi
      text_has_any "$answer_lower" "pg_isready" "brew services restart postgresql" "systemctl status postgresql" "docker compose ps db" && next_command_ref=1
      text_has_any "$answer_lower" "migrations" "requests" "app" "cannot connect" "database" && risk_ref=1
      ;;
  esac
  printf '%s %s %s %s\n' "$finding_ref" "$evidence_ref" "$next_command_ref" "$risk_ref"
}

label=$DEFAULT_LABEL
scenario="node-module-missing"
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
  node-module-missing|port-in-use|db-connection-refused)
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
[ -n "$model" ] || { echo "llava:7b is required for terminal screenshot debug probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# Terminal Screenshot Debug Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed terminal-debug conversation.
EOF_README

render_terminal_page "$scenario" "$page_html"
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
Inspect the attached terminal screenshot. Use only visible terminal or log evidence. Respond in exactly four lines starting with `Finding:`, `Evidence:`, `Next Command:`, and `Risk:`. Identify the main failure, cite the exact visible error line or code, name one concrete next command, and explain the operational risk.
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
has_next_command=$(printf '%s\n' "$assistant_lower" | grep -q '^next command:' && printf '1' || printf '0')
has_risk=$(printf '%s\n' "$assistant_lower" | grep -q '^risk:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_finding" -eq 1 ] && [ "$has_evidence" -eq 1 ] && [ "$has_next_command" -eq 1 ] && [ "$has_risk" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_terminal_answer "$scenario" "$assistant_lower")
finding_detected=$1
evidence_detected=$2
next_command_detected=$3
risk_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$screenshot_exists" -eq 1 ] && [ "$attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$finding_detected" -eq 1 ] && [ "$evidence_detected" -eq 1 ] \
  && [ "$next_command_detected" -eq 1 ] && [ "$risk_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"screenshot_exists":%s,"attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"finding_detected":%s,"evidence_detected":%s,"next_command_detected":%s,"risk_detected":%s,"line_count":%s,"screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$screenshot_exists" "$attachment_uploaded" "$sections_complete" "$no_disclaimer" "$finding_detected" "$evidence_detected" "$next_command_detected" "$risk_detected" "$line_count" "$(json_escape "$screenshot_png")" > "$json_file"

{
  printf '# Terminal Screenshot Debug Probe: %s\n\n' "$label"
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
  printf -- '- Next command detected: %s\n' "$next_command_detected"
  printf -- '- Risk detected: %s\n' "$risk_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Screenshot: %s\n' "$screenshot_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
