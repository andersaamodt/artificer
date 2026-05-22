#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="terminal-state-recovery-read-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for terminal-state recovery read probe." >&2
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
Usage: terminal-state-recovery-read-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Renders a deterministic terminal failure screenshot and a deterministic terminal
post-recovery screenshot in Safari, uploads both screenshots through Artificer
attachments, runs a vision-capable model, and verifies that the answer names
the visible state change, cites distinct before/after evidence, and provides
one concrete next shell check.
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

write_terminal_page() {
  html_path=$1
  title_text=$2
  lead_text=$3
  theme_css=$4
  badge_text=$5
  body_html=$6
  focus_text=$7
  cat > "$html_path" <<EOF_HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title_text</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: $theme_css;
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
  .badge {
    display: inline-flex;
    align-items: center;
    border-radius: 999px;
    background: rgba(148, 163, 184, 0.18);
    padding: 6px 10px;
    font-size: 15px;
    font-weight: 700;
  }
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
  .ok { color: #86efac; font-weight: 700; }
  .tip {
    margin-top: 18px;
    display: inline-flex;
    padding: 12px 16px;
    border-radius: 999px;
    background: rgba(15, 23, 42, 0.55);
    color: #e2e8f0;
    font-size: 20px;
    font-weight: 700;
  }
</style>
</head>
<body>
  <main class="page">
    <p class="lead">$lead_text</p>
    <section class="terminal">
      <div class="toolbar">
        <div class="dots"><span class="dot red"></span><span class="dot yellow"></span><span class="dot green"></span></div>
        <div>recovery.local</div>
        <div class="badge">$badge_text</div>
      </div>
      <pre>$body_html</pre>
    </section>
    <div class="tip">$focus_text</div>
  </main>
</body>
</html>
EOF_HTML
}

render_terminal_state_page() {
  scenario=$1
  variant=$2
  html_path=$3
  theme_css='radial-gradient(circle at top, #1f2937 0%, #020617 70%)'
  case "$scenario:$variant" in
    module-recovered:before)
      title_text="Module Missing Before"
      lead_text="Captured terminal output before the dependency recovery step."
      badge_text="before recovery"
      focus_text="Before focus: Cannot find module 'dotenv'"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Loading env from <span class="path">.env.local</span>
<span class="err">Error: Cannot find module 'dotenv'</span>
Require stack:
- <span class="path">/srv/artificer/api/bootstrap.js</span>
- <span class="path">/srv/artificer/bin/dev-server.js</span>
<span class="code">code: 'MODULE_NOT_FOUND'</span>
Node.js v20.12.2
EOF_BODY
)
      ;;
    module-recovered:after)
      title_text="Module Missing After"
      lead_text="Captured terminal output after the dependency recovery step."
      badge_text="after recovery"
      focus_text="After focus: Health check passed"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Loading env from <span class="path">.env.local</span>
Loaded 18 env vars
Connected to Redis cache
<span class="ok">Server listening on port 3000</span>
<span class="ok">Health check passed</span>
<span class="ok">Ready to accept requests</span>
EOF_BODY
)
      ;;
    port-recovered:before)
      title_text="Port Conflict Before"
      lead_text="Captured terminal output before clearing the stale listener."
      badge_text="before recovery"
      focus_text="Before focus: address already in use 0.0.0.0:3000"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Booting HTTP listener
<span class="err">Error: listen EADDRINUSE: address already in use 0.0.0.0:3000</span>
    at Server.setupListenHandle [as _listen2] (node:net:1829:16)
    at listenInCluster (node:net:1877:12)
<span class="code">code: 'EADDRINUSE'</span>
EOF_BODY
)
      ;;
    port-recovered:after)
      title_text="Port Conflict After"
      lead_text="Captured terminal output after clearing the stale listener."
      badge_text="after recovery"
      focus_text="After focus: Server listening on port 3000"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Booting HTTP listener
<span class="ok">Server listening on port 3000</span>
Background worker subscribed to queue default
<span class="ok">Health check passed</span>
<span class="ok">Ready to accept requests</span>
EOF_BODY
)
      ;;
    db-migration-pending:before)
      title_text="Database Refused Before"
      lead_text="Captured terminal output before the database recovery step."
      badge_text="before recovery"
      focus_text="Before focus: connect ECONNREFUSED 127.0.0.1:5432"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Loading env from <span class="path">.env.local</span>
<span class="err">Error: connect ECONNREFUSED 127.0.0.1:5432</span>
Postgres unavailable during bootstrap
Retry budget exhausted after 3 attempts
EOF_BODY
)
      ;;
    db-migration-pending:after)
      title_text="Database Refused After"
      lead_text="Captured terminal output after the database recovery step."
      badge_text="after recovery"
      focus_text="After focus: Migration required before serving traffic"
      body_html=$(cat <<'EOF_BODY'
<span class="cmd">$ node ./bin/dev-server.js</span>
Starting local API on port 3000
Loading env from <span class="path">.env.local</span>
Connected to PostgreSQL on 127.0.0.1:5432
Applying startup migrations
<span class="err">error: relation "tenants" does not exist</span>
<span class="err">Migration required before serving traffic</span>
EOF_BODY
)
      ;;
    *)
      echo "Unknown scenario/variant: $scenario $variant" >&2
      exit 1
      ;;
  esac
  write_terminal_page "$html_path" "$title_text" "$lead_text" "$theme_css" "$badge_text" "$body_html" "$focus_text"
}

visible_transcript_for() {
  scenario=$1
  variant=$2
  case "$scenario:$variant" in
    module-recovered:before)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Loading env from .env.local
Error: Cannot find module 'dotenv'
Require stack:
- /srv/artificer/api/bootstrap.js
- /srv/artificer/bin/dev-server.js
code: 'MODULE_NOT_FOUND'
Node.js v20.12.2
EOF_TEXT
      ;;
    module-recovered:after)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Loading env from .env.local
Loaded 18 env vars
Connected to Redis cache
Server listening on port 3000
Health check passed
Ready to accept requests
EOF_TEXT
      ;;
    port-recovered:before)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Booting HTTP listener
Error: listen EADDRINUSE: address already in use 0.0.0.0:3000
code: 'EADDRINUSE'
EOF_TEXT
      ;;
    port-recovered:after)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Booting HTTP listener
Server listening on port 3000
Background worker subscribed to queue default
Health check passed
Ready to accept requests
EOF_TEXT
      ;;
    db-migration-pending:before)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Loading env from .env.local
Error: connect ECONNREFUSED 127.0.0.1:5432
Postgres unavailable during bootstrap
Retry budget exhausted after 3 attempts
EOF_TEXT
      ;;
    db-migration-pending:after)
      cat <<'EOF_TEXT'
$ node ./bin/dev-server.js
Starting local API on port 3000
Loading env from .env.local
Connected to PostgreSQL on 127.0.0.1:5432
Applying startup migrations
error: relation "tenants" does not exist
Migration required before serving traffic
EOF_TEXT
      ;;
    *)
      echo "Unknown transcript scenario/variant: $scenario $variant" >&2
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
  set bounds of front window to {90, 72, 930, 940}
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
    do JavaScript "window.scrollTo(0,0); document.body.style.zoom='100%';" in current tab of front window
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

score_state_answer() {
  scenario=$1
  answer_lower=$2
  state_ref=0
  before_ref=0
  after_ref=0
  next_check_ref=0
  case "$scenario" in
    module-recovered)
      if text_has_any "$answer_lower" "state change:" \
        && text_has_any "$answer_lower" "recover" "healthy" "starts successfully" "ready to accept requests"; then
        state_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "cannot find module" "dotenv" "module_not_found"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "health check passed" "listening on port 3000" "ready to accept requests"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" \
        && text_has_any "$answer_lower" "curl" "health"; then
        next_check_ref=1
      fi
      ;;
    port-recovered)
      if text_has_any "$answer_lower" "state change:" \
        && text_has_any "$answer_lower" "recover" "healthy" "listening" "port conflict"; then
        state_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "eaddrinuse" "address already in use" "0.0.0.0:3000"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "listening on port 3000" "health check passed" "ready to accept requests"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" \
        && text_has_any "$answer_lower" "curl" "health"; then
        next_check_ref=1
      fi
      ;;
    db-migration-pending)
      if text_has_any "$answer_lower" "state change:" \
        && text_has_any "$answer_lower" "failure changed" "still blocked" "still failing" "recovery incomplete" "migration" "schema"; then
        state_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "connection refused" "econnrefused" "127.0.0.1:5432" "postgres"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "migration" "db:migrate" "relation \"tenants\"" "serving traffic"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" \
        && text_has_any "$answer_lower" "db:migrate" "migrate"; then
        next_check_ref=1
      fi
      ;;
  esac
  printf '%s %s %s %s\n' "$state_ref" "$before_ref" "$after_ref" "$next_check_ref"
}

label=$DEFAULT_LABEL
scenario="module-recovered"
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
  module-recovered|port-recovered|db-migration-pending)
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
before_html="$raw_dir/$scenario-before.html"
after_html="$raw_dir/$scenario-after.html"
before_png="$raw_dir/$scenario-before.png"
after_png="$raw_dir/$scenario-after.png"
before_transcript_txt="$raw_dir/$scenario-before-transcript.txt"
after_transcript_txt="$raw_dir/$scenario-after-transcript.txt"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("llava:7b")) then "llava:7b"
  else ""
  end
')
[ -n "$model" ] || { echo "llava:7b is required for terminal-state recovery read probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# Terminal State Recovery Read Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed terminal state comparison conversation.
EOF_README

render_terminal_state_page "$scenario" before "$before_html"
render_terminal_state_page "$scenario" after "$after_html"
visible_transcript_for "$scenario" before > "$before_transcript_txt"
visible_transcript_for "$scenario" after > "$after_transcript_txt"
capture_safari_screenshot "$before_html" "$before_png"
capture_safari_screenshot "$after_html" "$after_png"

before_exists=0
after_exists=0
[ -s "$before_png" ] && before_exists=1
[ -s "$after_png" ] && after_exists=1

ws_json=$(post_api_json "action=add_workspace&path=$(uri "$tmp_ws")&name=$(uri "$label")")
workspace_id=$(printf '%s' "$ws_json" | jq -r '.workspace.id // ""')
conv_json=$(post_api_json "action=new_conversation&workspace_id=$(uri "$workspace_id")&title=$(uri "$label")")
conversation_id=$(printf '%s' "$conv_json" | jq -r '.conversation.id // ""')
post_api_json "action=set_model&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&model=$(uri "$model")" >/dev/null

before_attachment_uploaded=0
after_attachment_uploaded=0
before_attachment_id=""
after_attachment_id=""
if [ "$before_exists" -eq 1 ]; then
  before_b64=$(base64 < "$before_png" | tr -d '\n')
  upload_before_json=$(post_api_json "action=upload_attachment&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&name=$(uri "$scenario-before.png")&mime=$(uri "image/png")&data=$(uri "$before_b64")")
  printf '%s\n' "$upload_before_json" > "$raw_dir/upload-before.json"
  before_attachment_id=$(printf '%s' "$upload_before_json" | jq -r '.attachment.id // ""')
  [ -n "$before_attachment_id" ] && before_attachment_uploaded=1
fi
if [ "$after_exists" -eq 1 ]; then
  after_b64=$(base64 < "$after_png" | tr -d '\n')
  upload_after_json=$(post_api_json "action=upload_attachment&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&name=$(uri "$scenario-after.png")&mime=$(uri "image/png")&data=$(uri "$after_b64")")
  printf '%s\n' "$upload_after_json" > "$raw_dir/upload-after.json"
  after_attachment_id=$(printf '%s' "$upload_after_json" | jq -r '.attachment.id // ""')
  [ -n "$after_attachment_id" ] && after_attachment_uploaded=1
fi
attachment_ids_csv="$before_attachment_id,$after_attachment_id"

default_prompt_text=$(cat <<'EOF_PROMPT'
Compare the two attached terminal screenshots from the same local recovery attempt. The first screenshot is BEFORE the recovery step and the second screenshot is AFTER it. Ignore browser chrome and use only visible screenshot evidence. Respond in exactly four lines starting with `State Change:`, `Before Evidence:`, `After Evidence:`, and `Next Check:`. State whether the visible terminal state recovered, stayed broken, or changed into a different visible failure, cite one visible cue from the before screenshot, cite one visible cue from the after screenshot, and name one concrete shell check or repair command justified by the after state.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
if [ -s "$before_transcript_txt" ]; then
  before_transcript=$(cat "$before_transcript_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Before screenshot visible transcript from the same Safari view:
$before_transcript
EOF_PROMPT
)
fi
if [ -s "$after_transcript_txt" ]; then
  after_transcript=$(cat "$after_transcript_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

After screenshot visible transcript from the same Safari view:
$after_transcript
EOF_PROMPT
)
fi

stream_session="${label}-stream"
run_body="action=run&workspace_id=$(uri "$workspace_id")&conversation_id=$(uri "$conversation_id")&prompt=$(uri "$prompt_text")&run_mode=report&compute_budget=quick&advanced_loop=0&max_iterations=4&permission_mode=read-only&attachment_ids=$(uri "$attachment_ids_csv")&stream_session=$(uri "$stream_session")"
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
has_state_change=$(printf '%s\n' "$assistant_lower" | grep -q '^state change:' && printf '1' || printf '0')
has_before=$(printf '%s\n' "$assistant_lower" | grep -q '^before evidence:' && printf '1' || printf '0')
has_after=$(printf '%s\n' "$assistant_lower" | grep -q '^after evidence:' && printf '1' || printf '0')
has_next_check=$(printf '%s\n' "$assistant_lower" | grep -q '^next check:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_state_change" -eq 1 ] && [ "$has_before" -eq 1 ] && [ "$has_after" -eq 1 ] && [ "$has_next_check" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_state_answer "$scenario" "$assistant_lower")
state_change_detected=$1
before_detected=$2
after_detected=$3
next_check_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$before_exists" -eq 1 ] && [ "$after_exists" -eq 1 ] \
  && [ "$before_attachment_uploaded" -eq 1 ] && [ "$after_attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$state_change_detected" -eq 1 ] && [ "$before_detected" -eq 1 ] \
  && [ "$after_detected" -eq 1 ] && [ "$next_check_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"before_exists":%s,"after_exists":%s,"before_attachment_uploaded":%s,"after_attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"state_change_detected":%s,"before_detected":%s,"after_detected":%s,"next_check_detected":%s,"line_count":%s,"before_screenshot_path":%s,"after_screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$before_exists" "$after_exists" "$before_attachment_uploaded" "$after_attachment_uploaded" "$sections_complete" "$no_disclaimer" "$state_change_detected" "$before_detected" "$after_detected" "$next_check_detected" "$line_count" "$(json_escape "$before_png")" "$(json_escape "$after_png")" > "$json_file"

{
  printf '# Terminal State Recovery Read Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Before screenshot exists: %s\n' "$before_exists"
  printf -- '- After screenshot exists: %s\n' "$after_exists"
  printf -- '- Before attachment uploaded: %s\n' "$before_attachment_uploaded"
  printf -- '- After attachment uploaded: %s\n' "$after_attachment_uploaded"
  printf -- '- Sections complete: %s\n' "$sections_complete"
  printf -- '- No disclaimer: %s\n' "$no_disclaimer"
  printf -- '- State change detected: %s\n' "$state_change_detected"
  printf -- '- Before evidence detected: %s\n' "$before_detected"
  printf -- '- After evidence detected: %s\n' "$after_detected"
  printf -- '- Next check detected: %s\n' "$next_check_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Before screenshot: %s\n' "$before_png"
  printf -- '- After screenshot: %s\n' "$after_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
