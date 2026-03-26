#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="diagram-annotation-read-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for diagram annotation read probe." >&2
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
Usage: diagram-annotation-read-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Renders a deterministic annotated system diagram in Safari, uploads the image
through Artificer attachments, runs a vision-capable model, and verifies that
the answer extracts one concrete operational takeaway with evidence, risk, and
one concrete next check.
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

render_diagram_page() {
  scenario=$1
  html_path=$2
  case "$scenario" in
    worker-queue-bottleneck)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claims Ingest Architecture</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
    color: #0f172a;
  }
  .page { padding: 28px 30px 34px; }
  h1 { margin: 0; font-size: 38px; }
  .sub { margin-top: 8px; font-size: 18px; color: #475569; }
  .frame {
    margin-top: 22px;
    background: white;
    border-radius: 28px;
    padding: 24px 24px 20px;
    box-shadow: 0 22px 60px rgba(15, 23, 42, 0.12);
  }
  .row { display: grid; grid-template-columns: 1.35fr 0.9fr; gap: 20px; align-items: start; }
  .canvas {
    position: relative;
    min-height: 430px;
    border-radius: 24px;
    background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
    border: 1px solid #cbd5e1;
    overflow: hidden;
  }
  .node {
    position: absolute;
    width: 156px;
    border-radius: 22px;
    padding: 16px 14px;
    background: white;
    border: 2px solid #94a3b8;
    box-shadow: 0 14px 36px rgba(15, 23, 42, 0.10);
    text-align: center;
  }
  .node .name { display: block; font-size: 21px; font-weight: 800; }
  .node .meta { display: block; margin-top: 8px; font-size: 15px; color: #475569; }
  .node.alert { border-color: #dc2626; background: #fef2f2; }
  .node.warn { border-color: #f59e0b; background: #fffbeb; }
  .note-stack { display: grid; gap: 14px; }
  .note {
    border-radius: 22px;
    padding: 16px 18px;
    background: #0f172a;
    color: white;
    box-shadow: 0 16px 36px rgba(15, 23, 42, 0.24);
  }
  .note.red { background: #991b1b; }
  .note.orange { background: #9a3412; }
  .note .eyebrow { font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; opacity: 0.8; }
  .note .value { margin-top: 8px; font-size: 30px; font-weight: 800; }
  .note .copy { margin-top: 8px; font-size: 17px; line-height: 1.35; }
  .footer { margin-top: 16px; display: flex; gap: 10px; flex-wrap: wrap; }
  .pill {
    display: inline-flex;
    align-items: center;
    padding: 9px 12px;
    border-radius: 999px;
    background: #eff6ff;
    color: #1d4ed8;
    font-size: 14px;
    font-weight: 700;
    width: fit-content;
  }
  .label { fill: #475569; font-size: 15px; font-weight: 700; }
  .hot { fill: #b91c1c; font-size: 16px; font-weight: 800; }
</style>
</head>
<body>
  <main class="page">
    <h1>Claims ingest architecture</h1>
    <div class="sub">Annotated live snapshot after the worker rollout.</div>
    <section class="frame">
      <div class="row">
        <div class="canvas">
          <svg width="100%" height="100%" viewBox="0 0 720 430" role="img" aria-label="Claims ingest architecture diagram">
            <defs>
              <marker id="arrow-red" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#dc2626"></path>
              </marker>
              <marker id="arrow-blue" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#2563eb"></path>
              </marker>
            </defs>
            <line x1="146" y1="195" x2="240" y2="195" stroke="#2563eb" stroke-width="6" marker-end="url(#arrow-blue)"></line>
            <text x="165" y="176" class="label">TLS ingress</text>
            <line x1="396" y1="195" x2="494" y2="195" stroke="#dc2626" stroke-width="7" marker-end="url(#arrow-red)"></line>
            <text x="399" y="172" class="hot">Backpressure starts here</text>
            <line x1="650" y1="195" x2="650" y2="300" stroke="#2563eb" stroke-width="6" marker-end="url(#arrow-blue)"></line>
            <text x="560" y="286" class="label">write claims</text>
          </svg>
          <div class="node" style="left: 40px; top: 132px;">
            <span class="name">Ingress</span>
            <span class="meta">tenant-web / claims-api</span>
          </div>
          <div class="node" style="left: 248px; top: 132px;">
            <span class="name">API pods</span>
            <span class="meta">enqueue claim jobs</span>
          </div>
          <div class="node alert" style="left: 492px; top: 130px;">
            <span class="name">Redis queue</span>
            <span class="meta">Depth 92k</span>
          </div>
          <div class="node warn" style="left: 560px; top: 288px; width: 136px;">
            <span class="name">Worker pool v2</span>
            <span class="meta">disabled</span>
          </div>
          <div class="node" style="left: 300px; top: 300px; width: 170px;">
            <span class="name">Postgres</span>
            <span class="meta">claims ledger</span>
          </div>
        </div>
        <div>
          <div class="note-stack">
            <div class="note red">
              <div class="eyebrow">Primary callout</div>
              <div class="value">Redis queue depth 92k</div>
              <div class="copy">Worker rollout did not restore queue consumers.</div>
            </div>
            <div class="note orange">
              <div class="eyebrow">Blocked dependency</div>
              <div class="value">worker-v2 disabled</div>
              <div class="copy">API keeps enqueueing, but the queue is no longer draining at the new worker boundary.</div>
            </div>
          </div>
          <div class="footer">
            <div class="pill">Backpressure starts here</div>
            <div class="pill">Delayed claim settlement risk</div>
          </div>
        </div>
      </div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    auth-cache-fallback)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Session Login Path</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #fff7ed 0%, #ffedd5 100%);
    color: #111827;
  }
  .page { padding: 28px 30px 34px; }
  h1 { margin: 0; font-size: 38px; }
  .sub { margin-top: 8px; font-size: 18px; color: #475569; }
  .frame {
    margin-top: 22px;
    background: white;
    border-radius: 28px;
    padding: 24px 24px 20px;
    box-shadow: 0 22px 60px rgba(15, 23, 42, 0.12);
  }
  .row { display: grid; grid-template-columns: 1.35fr 0.9fr; gap: 20px; align-items: start; }
  .canvas {
    position: relative;
    min-height: 430px;
    border-radius: 24px;
    background: linear-gradient(180deg, #fffaf5 0%, #ffedd5 100%);
    border: 1px solid #fed7aa;
    overflow: hidden;
  }
  .node {
    position: absolute;
    width: 148px;
    border-radius: 22px;
    padding: 16px 14px;
    background: white;
    border: 2px solid #cbd5e1;
    box-shadow: 0 14px 36px rgba(15, 23, 42, 0.10);
    text-align: center;
  }
  .node .name { display: block; font-size: 20px; font-weight: 800; }
  .node .meta { display: block; margin-top: 8px; font-size: 15px; color: #475569; }
  .node.alert { border-color: #dc2626; background: #fef2f2; }
  .note-stack { display: grid; gap: 14px; }
  .note {
    border-radius: 22px;
    padding: 16px 18px;
    background: #7c2d12;
    color: white;
    box-shadow: 0 16px 36px rgba(124, 45, 18, 0.25);
  }
  .note.red { background: #991b1b; }
  .note .eyebrow { font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; opacity: 0.8; }
  .note .value { margin-top: 8px; font-size: 30px; font-weight: 800; }
  .note .copy { margin-top: 8px; font-size: 17px; line-height: 1.35; }
  .footer { margin-top: 16px; display: flex; gap: 10px; flex-wrap: wrap; }
  .pill {
    display: inline-flex;
    align-items: center;
    padding: 9px 12px;
    border-radius: 999px;
    background: #fff7ed;
    color: #9a3412;
    font-size: 14px;
    font-weight: 700;
    width: fit-content;
  }
  .label { fill: #475569; font-size: 15px; font-weight: 700; }
  .hot { fill: #b91c1c; font-size: 16px; font-weight: 800; }
</style>
</head>
<body>
  <main class="page">
    <h1>Session login path</h1>
    <div class="sub">Annotated auth flow after the cache refresh change.</div>
    <section class="frame">
      <div class="row">
        <div class="canvas">
          <svg width="100%" height="100%" viewBox="0 0 720 430" role="img" aria-label="Session login path diagram">
            <defs>
              <marker id="arrow-orange" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#ea580c"></path>
              </marker>
              <marker id="arrow-red" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#dc2626"></path>
              </marker>
            </defs>
            <line x1="132" y1="140" x2="235" y2="140" stroke="#ea580c" stroke-width="6" marker-end="url(#arrow-orange)"></line>
            <line x1="386" y1="140" x2="490" y2="140" stroke="#ea580c" stroke-width="6" marker-end="url(#arrow-orange)"></line>
            <line x1="566" y1="212" x2="566" y2="304" stroke="#dc2626" stroke-width="7" marker-end="url(#arrow-red)"></line>
            <text x="508" y="284" class="hot">DB fallback path active</text>
            <text x="420" y="118" class="label">session lookup</text>
          </svg>
          <div class="node" style="left: 34px; top: 76px; width: 120px;">
            <span class="name">Browser</span>
            <span class="meta">login</span>
          </div>
          <div class="node" style="left: 236px; top: 76px; width: 132px;">
            <span class="name">Auth API</span>
            <span class="meta">session read</span>
          </div>
          <div class="node alert" style="left: 490px; top: 72px; width: 148px;">
            <span class="name">Session cache</span>
            <span class="meta">miss rate 68%</span>
          </div>
          <div class="node alert" style="left: 490px; top: 300px; width: 160px;">
            <span class="name">Postgres</span>
            <span class="meta">DB fallback path</span>
          </div>
          <div class="node" style="left: 236px; top: 300px; width: 148px;">
            <span class="name">Edge gateway</span>
            <span class="meta">token refresh</span>
          </div>
        </div>
        <div>
          <div class="note-stack">
            <div class="note red">
              <div class="eyebrow">Primary callout</div>
              <div class="value">Session cache miss rate 68%</div>
              <div class="copy">Auth requests are falling through to the database path instead of hitting cache.</div>
            </div>
            <div class="note">
              <div class="eyebrow">Latency consequence</div>
              <div class="value">Login p95 4.8s</div>
              <div class="copy">The visible fallback path adds round trips and pushes session lookups onto Postgres.</div>
            </div>
          </div>
          <div class="footer">
            <div class="pill">DB fallback path active</div>
            <div class="pill">Cache miss spike after refresh</div>
          </div>
        </div>
      </div>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    canary-drain-blocked)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Release Promotion Path</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f5f3ff 0%, #ede9fe 100%);
    color: #111827;
  }
  .page { padding: 28px 30px 34px; }
  h1 { margin: 0; font-size: 38px; }
  .sub { margin-top: 8px; font-size: 18px; color: #475569; }
  .frame {
    margin-top: 22px;
    background: white;
    border-radius: 28px;
    padding: 24px 24px 20px;
    box-shadow: 0 22px 60px rgba(15, 23, 42, 0.12);
  }
  .row { display: grid; grid-template-columns: 1.35fr 0.9fr; gap: 20px; align-items: start; }
  .canvas {
    position: relative;
    min-height: 430px;
    border-radius: 24px;
    background: linear-gradient(180deg, #faf5ff 0%, #ede9fe 100%);
    border: 1px solid #ddd6fe;
    overflow: hidden;
  }
  .node {
    position: absolute;
    width: 150px;
    border-radius: 22px;
    padding: 16px 14px;
    background: white;
    border: 2px solid #c4b5fd;
    box-shadow: 0 14px 36px rgba(15, 23, 42, 0.10);
    text-align: center;
  }
  .node .name { display: block; font-size: 20px; font-weight: 800; }
  .node .meta { display: block; margin-top: 8px; font-size: 15px; color: #475569; }
  .node.alert { border-color: #dc2626; background: #fef2f2; }
  .note-stack { display: grid; gap: 14px; }
  .note {
    border-radius: 22px;
    padding: 16px 18px;
    background: #5b21b6;
    color: white;
    box-shadow: 0 16px 36px rgba(91, 33, 182, 0.24);
  }
  .note.red { background: #991b1b; }
  .note .eyebrow { font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; opacity: 0.8; }
  .note .value { margin-top: 8px; font-size: 30px; font-weight: 800; }
  .note .copy { margin-top: 8px; font-size: 17px; line-height: 1.35; }
  .footer { margin-top: 16px; display: flex; gap: 10px; flex-wrap: wrap; }
  .pill {
    display: inline-flex;
    align-items: center;
    padding: 9px 12px;
    border-radius: 999px;
    background: #f5f3ff;
    color: #6d28d9;
    font-size: 14px;
    font-weight: 700;
    width: fit-content;
  }
  .label { fill: #6b7280; font-size: 15px; font-weight: 700; }
  .hot { fill: #b91c1c; font-size: 16px; font-weight: 800; }
</style>
</head>
<body>
  <main class="page">
    <h1>Release promotion path</h1>
    <div class="sub">Annotated rollout state after the latest canary cutover.</div>
    <section class="frame">
      <div class="row">
        <div class="canvas">
          <svg width="100%" height="100%" viewBox="0 0 720 430" role="img" aria-label="Release promotion path diagram">
            <defs>
              <marker id="arrow-purple" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#7c3aed"></path>
              </marker>
              <marker id="arrow-red" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto">
                <path d="M0,0 L10,5 L0,10 z" fill="#dc2626"></path>
              </marker>
            </defs>
            <line x1="164" y1="160" x2="300" y2="160" stroke="#7c3aed" stroke-width="6" marker-end="url(#arrow-purple)"></line>
            <line x1="458" y1="160" x2="586" y2="160" stroke="#dc2626" stroke-width="7" marker-end="url(#arrow-red)"></line>
            <text x="460" y="138" class="hot">Fleet promotion blocked</text>
            <line x1="370" y1="246" x2="370" y2="322" stroke="#dc2626" stroke-width="7" marker-end="url(#arrow-red)"></line>
            <text x="266" y="304" class="hot">Canary drain stuck 41m</text>
          </svg>
          <div class="node" style="left: 48px; top: 96px; width: 122px;">
            <span class="name">Build pack</span>
            <span class="meta">r2026.03.22</span>
          </div>
          <div class="node alert" style="left: 300px; top: 86px; width: 156px;">
            <span class="name">Canary</span>
            <span class="meta">drain stuck 41m</span>
          </div>
          <div class="node alert" style="left: 586px; top: 86px; width: 128px;">
            <span class="name">Fleet</span>
            <span class="meta">promotion blocked</span>
          </div>
          <div class="node" style="left: 278px; top: 324px; width: 184px;">
            <span class="name">Release notes</span>
            <span class="meta">waiting on cutover</span>
          </div>
        </div>
        <div>
          <div class="note-stack">
            <div class="note red">
              <div class="eyebrow">Primary callout</div>
              <div class="value">Canary drain stuck 41m</div>
              <div class="copy">The rollout has not cleared canary, so the fleet step is still blocked.</div>
            </div>
            <div class="note">
              <div class="eyebrow">Release consequence</div>
              <div class="value">Release notes waiting on cutover</div>
              <div class="copy">Operators are left in a partial rollout state until the canary gate clears.</div>
            </div>
          </div>
          <div class="footer">
            <div class="pill">Fleet promotion blocked</div>
            <div class="pill">Partial rollout drift risk</div>
          </div>
        </div>
      </div>
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

score_diagram_answer() {
  scenario=$1
  answer_lower=$2
  takeaway_ref=0
  evidence_ref=0
  risk_ref=0
  next_check_ref=0
  case "$scenario" in
    worker-queue-bottleneck)
      if text_has_any "$answer_lower" "takeaway:" && text_has_any "$answer_lower" "redis" "queue" && text_has_any "$answer_lower" "worker" "backpressure" "bottleneck"; then
        takeaway_ref=1
      fi
      if text_has_any "$answer_lower" "evidence:" && text_has_any "$answer_lower" "92k" "worker-v2" "backpressure starts here"; then
        evidence_ref=1
      fi
      if text_has_any "$answer_lower" "risk:" && text_has_any "$answer_lower" "backlog" "delay" "timeout" "queue"; then
        risk_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" && text_has_any "$answer_lower" "worker-v2" "kubectl" "redis-cli" "queue"; then
        next_check_ref=1
      fi
      ;;
    auth-cache-fallback)
      if text_has_any "$answer_lower" "takeaway:" && text_has_any "$answer_lower" "cache" "session cache" && text_has_any "$answer_lower" "db" "postgres" "fallback"; then
        takeaway_ref=1
      fi
      if text_has_any "$answer_lower" "evidence:" && text_has_any "$answer_lower" "68%" "db fallback" "4.8s"; then
        evidence_ref=1
      fi
      if text_has_any "$answer_lower" "risk:" && text_has_any "$answer_lower" "login" "latency" "postgres" "db load"; then
        risk_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" && text_has_any "$answer_lower" "redis" "cache" "hit rate" "auth"; then
        next_check_ref=1
      fi
      ;;
    canary-drain-blocked)
      if text_has_any "$answer_lower" "takeaway:" && text_has_any "$answer_lower" "canary" && text_has_any "$answer_lower" "fleet" "promotion blocked" "blocked"; then
        takeaway_ref=1
      fi
      if text_has_any "$answer_lower" "evidence:" && text_has_any "$answer_lower" "41m" "fleet promotion blocked" "release notes waiting"; then
        evidence_ref=1
      fi
      if text_has_any "$answer_lower" "risk:" && text_has_any "$answer_lower" "partial rollout" "drift" "release" "stale"; then
        risk_ref=1
      fi
      if text_has_any "$answer_lower" "next check:" && text_has_any "$answer_lower" "./bin/release" "release status" "kubectl"; then
        next_check_ref=1
      fi
      ;;
  esac
  printf '%s %s %s %s\n' "$takeaway_ref" "$evidence_ref" "$risk_ref" "$next_check_ref"
}

label=$DEFAULT_LABEL
scenario="worker-queue-bottleneck"
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
  worker-queue-bottleneck|auth-cache-fallback|canary-drain-blocked)
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
[ -n "$model" ] || { echo "llava:7b is required for diagram annotation read probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# Diagram Annotation Read Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed diagram-reading conversation.
EOF_README

render_diagram_page "$scenario" "$page_html"
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
Inspect the attached annotated system diagram screenshot. Use only visible diagram or annotation evidence. Respond in exactly four lines starting with `Takeaway:`, `Evidence:`, `Risk:`, and `Next Check:`. Name the single most important operational takeaway, cite the visible annotation or node label that proves it, explain the operational risk, and name one concrete next check.
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
has_takeaway=$(printf '%s\n' "$assistant_lower" | grep -q '^takeaway:' && printf '1' || printf '0')
has_evidence=$(printf '%s\n' "$assistant_lower" | grep -q '^evidence:' && printf '1' || printf '0')
has_risk=$(printf '%s\n' "$assistant_lower" | grep -q '^risk:' && printf '1' || printf '0')
has_next_check=$(printf '%s\n' "$assistant_lower" | grep -q '^next check:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_takeaway" -eq 1 ] && [ "$has_evidence" -eq 1 ] && [ "$has_risk" -eq 1 ] && [ "$has_next_check" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_diagram_answer "$scenario" "$assistant_lower")
takeaway_detected=$1
evidence_detected=$2
risk_detected=$3
next_check_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$screenshot_exists" -eq 1 ] && [ "$attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$takeaway_detected" -eq 1 ] && [ "$evidence_detected" -eq 1 ] \
  && [ "$risk_detected" -eq 1 ] && [ "$next_check_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"screenshot_exists":%s,"attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"takeaway_detected":%s,"evidence_detected":%s,"risk_detected":%s,"next_check_detected":%s,"line_count":%s,"screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$screenshot_exists" "$attachment_uploaded" "$sections_complete" "$no_disclaimer" "$takeaway_detected" "$evidence_detected" "$risk_detected" "$next_check_detected" "$line_count" "$(json_escape "$screenshot_png")" > "$json_file"

{
  printf '# Diagram Annotation Read Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Screenshot exists: %s\n' "$screenshot_exists"
  printf -- '- Attachment uploaded: %s\n' "$attachment_uploaded"
  printf -- '- Sections complete: %s\n' "$sections_complete"
  printf -- '- No disclaimer: %s\n' "$no_disclaimer"
  printf -- '- Takeaway detected: %s\n' "$takeaway_detected"
  printf -- '- Evidence detected: %s\n' "$evidence_detected"
  printf -- '- Risk detected: %s\n' "$risk_detected"
  printf -- '- Next check detected: %s\n' "$next_check_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Screenshot: %s\n' "$screenshot_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
