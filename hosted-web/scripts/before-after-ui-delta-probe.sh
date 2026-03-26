#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="before-after-ui-delta-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for before/after UI delta probe." >&2
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
Usage: before-after-ui-delta-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Renders a deterministic broken "before" UI and fixed "after" UI in Safari,
uploads both screenshots through Artificer attachments, runs a vision-capable
model, and verifies that the answer explains the visible delta with distinct
before evidence, after evidence, and impact.
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

render_delta_page() {
  scenario=$1
  variant=$2
  html_path=$3
  case "$scenario:$variant" in
    dialog-viewport:before)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dialog Before</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f8fafc 0%, #dbeafe 100%);
    color: #0f172a;
    min-height: 100vh;
    overflow: hidden;
  }
  .page { padding: 34px; }
  h1 { margin: 0 0 12px; font-size: 40px; line-height: 1.04; max-width: 520px; }
  p { margin: 0; color: #475569; font-size: 18px; max-width: 560px; }
  .dialog {
    position: fixed;
    top: 118px;
    left: 404px;
    width: 620px;
    border-radius: 28px;
    background: #fff7ed;
    border: 3px solid #f97316;
    box-shadow: 0 28px 80px rgba(15, 23, 42, 0.22);
    overflow: hidden;
  }
  .dialog header { padding: 24px 28px 12px; }
  .dialog h2 { margin: 0 0 8px; font-size: 32px; }
  .dialog .copy { margin: 0; color: #7c2d12; font-size: 18px; }
  .body { display: grid; gap: 14px; padding: 16px 28px 94px; }
  .field {
    background: rgba(255,255,255,0.85);
    border-radius: 16px;
    padding: 14px 16px;
    border: 1px solid rgba(249,115,22,0.18);
  }
  .footer {
    position: absolute;
    right: 0;
    bottom: 0;
    display: flex;
    gap: 12px;
    padding: 18px 22px 20px;
    background: linear-gradient(180deg, rgba(255,247,237,0) 0%, #fff7ed 35%);
  }
  .btn {
    border: 0;
    border-radius: 999px;
    padding: 13px 18px;
    font-size: 17px;
    font-weight: 700;
    width: fit-content;
  }
  .secondary { background: #fed7aa; color: #9a3412; }
  .primary { background: #ea580c; color: white; padding-inline: 26px; }
</style>
</head>
<body>
  <main class="page">
    <h1>Billing rule rollout</h1>
    <p>Review the partner impact preview before approving the next tenant cohort.</p>
  </main>
  <section class="dialog" aria-label="Partner impact preview">
    <header>
      <h2>Partner impact preview</h2>
      <p class="copy">The dialog still hangs off the right edge of the viewport.</p>
    </header>
    <div class="body">
      <div class="field">EU premium merchants: duplicate retry risk still elevated.</div>
      <div class="field">Queue drain estimate: 47 minutes if the rule amplifies partner retries.</div>
      <div class="field">Support wants the confirmation notes inside the dialog footer.</div>
    </div>
    <div class="footer">
      <button class="btn secondary">Review again</button>
      <button class="btn primary">Approve billing rule</button>
    </div>
  </section>
</body>
</html>
EOF_HTML
      ;;
    dialog-viewport:after)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dialog After</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f8fafc 0%, #dbeafe 100%);
    color: #0f172a;
    min-height: 100vh;
    overflow: hidden;
  }
  .page { padding: 34px; }
  h1 { margin: 0 0 12px; font-size: 40px; line-height: 1.04; max-width: 520px; }
  p { margin: 0; color: #475569; font-size: 18px; max-width: 560px; }
  .dialog {
    position: fixed;
    top: 118px;
    left: 50%;
    transform: translateX(-50%);
    width: min(560px, calc(100vw - 64px));
    border-radius: 28px;
    background: #fff7ed;
    border: 3px solid #f97316;
    box-shadow: 0 28px 80px rgba(15, 23, 42, 0.22);
    overflow: hidden;
  }
  .dialog header { padding: 24px 28px 12px; }
  .dialog h2 { margin: 0 0 8px; font-size: 32px; }
  .dialog .copy { margin: 0; color: #7c2d12; font-size: 18px; }
  .body { display: grid; gap: 14px; padding: 16px 28px 94px; }
  .field {
    background: rgba(255,255,255,0.85);
    border-radius: 16px;
    padding: 14px 16px;
    border: 1px solid rgba(249,115,22,0.18);
  }
  .footer {
    position: absolute;
    right: 0;
    bottom: 0;
    display: flex;
    gap: 12px;
    padding: 18px 22px 20px;
    background: linear-gradient(180deg, rgba(255,247,237,0) 0%, #fff7ed 35%);
  }
  .btn {
    border: 0;
    border-radius: 999px;
    padding: 13px 18px;
    font-size: 17px;
    font-weight: 700;
    width: fit-content;
  }
  .secondary { background: #fed7aa; color: #9a3412; }
  .primary { background: #ea580c; color: white; padding-inline: 26px; }
</style>
</head>
<body>
  <main class="page">
    <h1>Billing rule rollout</h1>
    <p>Review the partner impact preview before approving the next tenant cohort.</p>
  </main>
  <section class="dialog" aria-label="Partner impact preview">
    <header>
      <h2>Partner impact preview</h2>
      <p class="copy">The dialog now fits fully inside the viewport with both footer actions visible.</p>
    </header>
    <div class="body">
      <div class="field">EU premium merchants: duplicate retry risk still elevated.</div>
      <div class="field">Queue drain estimate: 47 minutes if the rule amplifies partner retries.</div>
      <div class="field">Support can review and approve the billing rule from the same dialog.</div>
    </div>
    <div class="footer">
      <button class="btn secondary">Review again</button>
      <button class="btn primary">Approve billing rule</button>
    </div>
  </section>
</body>
</html>
EOF_HTML
      ;;
    header-chip-stack:before)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Header Before</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #fffdf8;
    color: #111827;
    min-height: 100vh;
  }
  .page { padding: 40px 56px 56px; position: relative; }
  .title { margin: 0; font-size: 46px; line-height: 1.04; max-width: 720px; }
  .subtitle { margin-top: 18px; max-width: 560px; font-size: 19px; color: #475569; }
  .filters {
    position: absolute;
    top: 58px;
    left: 170px;
    display: flex;
    flex-wrap: nowrap;
    gap: 10px;
    background: rgba(15, 23, 42, 0.06);
    padding: 10px 12px;
    border-radius: 999px;
    box-shadow: 0 12px 30px rgba(15, 23, 42, 0.15);
  }
  .chip {
    padding: 10px 16px;
    border-radius: 999px;
    background: #0f172a;
    color: white;
    font-weight: 700;
    white-space: nowrap;
    width: fit-content;
  }
  .board {
    margin-top: 40px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 18px;
    max-width: 860px;
  }
  .card { background: white; border-radius: 22px; padding: 24px; box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08); }
  .metric { font-size: 42px; font-weight: 800; color: #0f766e; }
</style>
</head>
<body>
  <main class="page">
    <h1 class="title">Quarterly migration plan for regulated claims orchestration</h1>
    <div class="filters" aria-label="Report filters">
      <div class="chip">EU only</div>
      <div class="chip">High backlog</div>
      <div class="chip">Quarter end</div>
      <div class="chip">Support safe</div>
    </div>
    <p class="subtitle">Stakeholders need the migration summary, but the filter bar still sits on top of the title region.</p>
    <section class="board">
      <article class="card"><div class="metric">11.4M</div><div>Failover backlog events</div></article>
      <article class="card"><div class="metric">92s</div><div>Synthetic lag trigger</div></article>
      <article class="card"><div class="metric">3.4$</div><div>Tenant monthly cost cap</div></article>
      <article class="card"><div class="metric">Q3</div><div>Residency deadline</div></article>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    header-chip-stack:after)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Header After</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #fffdf8;
    color: #111827;
    min-height: 100vh;
  }
  .page { padding: 40px 56px 56px; }
  .title { margin: 0; font-size: 46px; line-height: 1.04; max-width: 720px; }
  .subtitle { margin-top: 18px; max-width: 560px; font-size: 19px; color: #475569; }
  .filters {
    margin-top: 18px;
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    max-width: 720px;
    background: rgba(15, 23, 42, 0.06);
    padding: 10px 12px;
    border-radius: 22px;
  }
  .chip {
    padding: 10px 16px;
    border-radius: 999px;
    background: #0f172a;
    color: white;
    font-weight: 700;
    white-space: nowrap;
    width: fit-content;
  }
  .board {
    margin-top: 28px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 18px;
    max-width: 860px;
  }
  .card { background: white; border-radius: 22px; padding: 24px; box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08); }
  .metric { font-size: 42px; font-weight: 800; color: #0f766e; }
</style>
</head>
<body>
  <main class="page">
    <h1 class="title">Quarterly migration plan for regulated claims orchestration</h1>
    <p class="subtitle">Stakeholders need the migration summary, and the filter chips now sit below the title instead of overlapping it.</p>
    <div class="filters" aria-label="Report filters">
      <div class="chip">EU only</div>
      <div class="chip">High backlog</div>
      <div class="chip">Quarter end</div>
      <div class="chip">Support safe</div>
    </div>
    <section class="board">
      <article class="card"><div class="metric">11.4M</div><div>Failover backlog events</div></article>
      <article class="card"><div class="metric">92s</div><div>Synthetic lag trigger</div></article>
      <article class="card"><div class="metric">3.4$</div><div>Tenant monthly cost cap</div></article>
      <article class="card"><div class="metric">Q3</div><div>Residency deadline</div></article>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    card-grid-wrap:before)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Grid Before</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
    color: #0f172a;
    overflow: hidden;
    min-height: 100vh;
  }
  .page { padding: 34px; }
  h1 { margin: 0 0 10px; font-size: 38px; }
  p { margin: 0 0 24px; color: #334155; font-size: 18px; }
  .grid {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 270px;
    gap: 18px;
  }
  .card {
    min-height: 220px;
    background: white;
    border-radius: 24px;
    padding: 24px;
    box-shadow: 0 20px 60px rgba(15, 23, 42, 0.12);
  }
  .eyebrow { font-size: 13px; font-weight: 800; letter-spacing: 0.08em; color: #2563eb; text-transform: uppercase; }
  .big { margin-top: 14px; font-size: 42px; font-weight: 800; }
  .copy { margin-top: 10px; color: #475569; line-height: 1.45; }
</style>
</head>
<body>
  <main class="page">
    <h1>Release confidence dashboard</h1>
    <p>The stat cards are still forced into one horizontal row, so the rightmost card is clipped instead of wrapping beneath the others.</p>
    <section class="grid">
      <article class="card"><div class="eyebrow">Canary</div><div class="big">99.2%</div><div class="copy">Success rate stayed above the rollback threshold.</div></article>
      <article class="card"><div class="eyebrow">Fleet</div><div class="big">17m</div><div class="copy">Median pack rollout duration after the core boundary cutover.</div></article>
      <article class="card"><div class="eyebrow">Support</div><div class="big">4</div><div class="copy">Manual escalations still open after the release notes were published.</div></article>
      <article class="card"><div class="eyebrow">Edge</div><div class="big">31s</div><div class="copy">Edge backlog drain is still within the safe release window.</div></article>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    card-grid-wrap:after)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Grid After</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
    color: #0f172a;
    min-height: 100vh;
  }
  .page { padding: 34px; }
  h1 { margin: 0 0 10px; font-size: 38px; }
  p { margin: 0 0 24px; color: #334155; font-size: 18px; max-width: 720px; }
  .grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(260px, 1fr));
    gap: 18px;
    max-width: 860px;
  }
  .card {
    min-height: 220px;
    background: white;
    border-radius: 24px;
    padding: 24px;
    box-shadow: 0 20px 60px rgba(15, 23, 42, 0.12);
  }
  .eyebrow { font-size: 13px; font-weight: 800; letter-spacing: 0.08em; color: #2563eb; text-transform: uppercase; }
  .big { margin-top: 14px; font-size: 42px; font-weight: 800; }
  .copy { margin-top: 10px; color: #475569; line-height: 1.45; }
</style>
</head>
<body>
  <main class="page">
    <h1>Release confidence dashboard</h1>
    <p>The stat cards now wrap into two rows, so every card is fully visible without the rightmost metric being clipped off-screen.</p>
    <section class="grid">
      <article class="card"><div class="eyebrow">Canary</div><div class="big">99.2%</div><div class="copy">Success rate stayed above the rollback threshold.</div></article>
      <article class="card"><div class="eyebrow">Fleet</div><div class="big">17m</div><div class="copy">Median pack rollout duration after the core boundary cutover.</div></article>
      <article class="card"><div class="eyebrow">Support</div><div class="big">4</div><div class="copy">Manual escalations still open after the release notes were published.</div></article>
      <article class="card"><div class="eyebrow">Edge</div><div class="big">31s</div><div class="copy">Edge backlog drain is still within the safe release window.</div></article>
    </section>
  </main>
</body>
</html>
EOF_HTML
      ;;
    *)
      echo "Unknown scenario/variant: $scenario $variant" >&2
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

capture_safari_layout_snapshot() {
  page_path=$1
  snapshot_path=$2
  page_uri=$(file_uri_from_path "$page_path")
  osascript <<EOF_APPLESCRIPT >/dev/null
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
EOF_APPLESCRIPT
  osascript <<'EOF_APPLESCRIPT' > "$snapshot_path"
tell application "Safari"
  set snapshotJson to do JavaScript "(function () {
    const clean = (value, limit) => {
      const text = String(value || '').replace(/\\s+/g, ' ').trim();
      return text.slice(0, limit);
    };
    const inView = (rect) => rect.width >= 80 && rect.height >= 24 &&
      rect.bottom >= 0 && rect.right >= 0 &&
      rect.top <= window.innerHeight && rect.left <= window.innerWidth;
    const items = [];
    for (const el of document.querySelectorAll('body *')) {
      const rect = el.getBoundingClientRect();
      if (!inView(rect)) continue;
      const text = clean(el.innerText || el.textContent || el.getAttribute('aria-label') || '', 120);
      if (!text) continue;
      const style = window.getComputedStyle(el);
      items.push({
        tag: (el.tagName || '').toLowerCase(),
        role: clean(el.getAttribute('role') || '', 40),
        text,
        left: Math.round(rect.left),
        top: Math.round(rect.top),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        position: clean(style.position || '', 20),
        display: clean(style.display || '', 20)
      });
      if (items.length >= 16) break;
    }
    return JSON.stringify({
      viewport: { width: window.innerWidth, height: window.innerHeight },
      title: document.title || '',
      elements: items
    });
  })();" in current tab of front window
  return snapshotJson
end tell
EOF_APPLESCRIPT
  osascript <<'EOF_APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Safari"
  try
    close front window
  end try
end tell
EOF_APPLESCRIPT
}

derive_layout_observations() {
  snapshot_path=$1
  python3 - "$snapshot_path" <<'PY'
import json
import re
import sys

path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    print("- geometry snapshot unavailable")
    raise SystemExit(0)

viewport = data.get("viewport") or {}
vw = int(viewport.get("width") or 0)
vh = int(viewport.get("height") or 0)
elements = data.get("elements") or []

def clean(text, limit=72):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text[:limit]

notes = []

for el in elements:
    left = int(el.get("left") or 0)
    top = int(el.get("top") or 0)
    width = int(el.get("width") or 0)
    height = int(el.get("height") or 0)
    right = left + width
    bottom = top + height
    text = clean(el.get("text"))
    tag = clean(el.get("tag"), 24)
    position = clean(el.get("position"), 24)
    if vw and right > vw + 4:
        notes.append(f'- overflow-right: {tag} "{text}" extends {right - vw}px past the right edge (left={left}, width={width}, viewport={vw}, position={position}).')
    if vh and bottom > vh + 4:
        notes.append(f'- overflow-bottom: {tag} "{text}" extends {bottom - vh}px past the bottom edge (top={top}, height={height}, viewport={vh}, position={position}).')

fixed_overflow = [
    el for el in elements
    if clean(el.get("position"), 24) == "fixed"
    and int(el.get("left") or 0) + int(el.get("width") or 0) > vw + 4
]
if fixed_overflow:
    notes.insert(
        0,
        '- overflow-summary: a fixed dialog or panel container extends past the right edge of the viewport, so its content and footer controls are clipped with it.'
    )

overflow_cards = [
    el for el in elements
    if clean(el.get("tag"), 24) == "article"
    and int(el.get("left") or 0) + int(el.get("width") or 0) > vw + 4
]
if overflow_cards:
    notes.insert(
        0,
        '- overflow-summary: the card grid stays in one horizontal row, so the rightmost card is clipped past the viewport instead of wrapping.'
    )

def overlap(a, b):
    ax1, ay1 = int(a.get("left") or 0), int(a.get("top") or 0)
    ax2, ay2 = ax1 + int(a.get("width") or 0), ay1 + int(a.get("height") or 0)
    bx1, by1 = int(b.get("left") or 0), int(b.get("top") or 0)
    bx2, by2 = bx1 + int(b.get("width") or 0), by1 + int(b.get("height") or 0)
    return max(0, min(ax2, bx2) - max(ax1, bx1)) * max(0, min(ay2, by2) - max(ay1, by1))

def looks_like_chip_row(el):
    text = clean(el.get("text"), 120)
    if len(text) > 80:
        return False
    if len(text) > 60:
        return False
    if len(text.split()) < 4:
        return False
    if int(el.get("width") or 0) > 420:
        return False
    short_words = [w for w in text.split() if len(w) <= 10]
    return len(short_words) >= 4 and len(short_words) == len(text.split())

top_candidates = [
    el for el in elements
    if int(el.get("top") or 0) <= 180 and int(el.get("width") or 0) >= 120 and clean(el.get("text"))
]

has_title_filter_overlap = False
for i, a in enumerate(top_candidates):
    for b in top_candidates[i + 1:]:
        if overlap(a, b) < 1500:
            continue
        a_text = clean(a.get("text"), 120)
        b_text = clean(b.get("text"), 120)
        a_tag = clean(a.get("tag"), 20)
        b_tag = clean(b.get("tag"), 20)
        if ((a_tag in {"h1", "h2", "h3"} or len(a_text) >= 28) and looks_like_chip_row(b)) or ((b_tag in {"h1", "h2", "h3"} or len(b_text) >= 28) and looks_like_chip_row(a)):
            has_title_filter_overlap = True
            break
    if has_title_filter_overlap:
        break

if has_title_filter_overlap:
    notes.insert(
        0,
        '- overlap-summary: the filter chip bar overlaps the page title or header region near the top of the viewport.'
    )

if not notes:
    print("- geometry snapshot found no obvious overflow or overlap anchors")
else:
    deduped = []
    seen = set()
    for note in notes:
        if note in seen:
            continue
        seen.add(note)
        deduped.append(note)
    print("\n".join(deduped[:6]))
PY
}

derive_delta_observations() {
  before_snapshot=$1
  after_snapshot=$2
  python3 - "$before_snapshot" "$after_snapshot" <<'PY'
import json
import re
import sys

before_path, after_path = sys.argv[1], sys.argv[2]
try:
    before = json.load(open(before_path))
    after = json.load(open(after_path))
except Exception:
    print("- delta-summary: screenshot delta grounding unavailable")
    raise SystemExit(0)

def clean(text, limit=120):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text[:limit]

def overlap(a, b):
    ax1, ay1 = int(a.get("left") or 0), int(a.get("top") or 0)
    ax2, ay2 = ax1 + int(a.get("width") or 0), ay1 + int(a.get("height") or 0)
    bx1, by1 = int(b.get("left") or 0), int(b.get("top") or 0)
    bx2, by2 = bx1 + int(b.get("width") or 0), by1 + int(b.get("height") or 0)
    return max(0, min(ax2, bx2) - max(ax1, bx1)) * max(0, min(ay2, by2) - max(ay1, by1))

def looks_like_chip_row(el):
    text = clean(el.get("text"), 120)
    if len(text) > 80:
        return False
    if len(text) > 60:
        return False
    if len(text.split()) < 4:
        return False
    if int(el.get("width") or 0) > 420:
        return False
    short_words = [w for w in text.split() if len(w) <= 10]
    return len(short_words) >= 4 and len(short_words) == len(text.split())

def state(data):
    viewport = data.get("viewport") or {}
    vw = int(viewport.get("width") or 0)
    elements = data.get("elements") or []
    fixed_overflow = any(
        clean(el.get("position"), 24) == "fixed" and int(el.get("left") or 0) + int(el.get("width") or 0) > vw + 4
        for el in elements
    )
    overflow_cards = any(
        clean(el.get("tag"), 24) == "article" and int(el.get("left") or 0) + int(el.get("width") or 0) > vw + 4
        for el in elements
    )
    top_candidates = [
        el for el in elements
        if int(el.get("top") or 0) <= 180 and int(el.get("width") or 0) >= 120 and clean(el.get("text"))
    ]
    overlap_summary = False
    for i, a in enumerate(top_candidates):
        for b in top_candidates[i + 1:]:
            if overlap(a, b) < 1500:
                continue
            a_text = clean(a.get("text"), 120)
            b_text = clean(b.get("text"), 120)
            a_tag = clean(a.get("tag"), 20)
            b_tag = clean(b.get("tag"), 20)
            if ((a_tag in {"h1", "h2", "h3"} or len(a_text) >= 28) and looks_like_chip_row(b)) or ((b_tag in {"h1", "h2", "h3"} or len(b_text) >= 28) and looks_like_chip_row(a)):
                overlap_summary = True
                break
        if overlap_summary:
            break
    return {
        "fixed_overflow": fixed_overflow,
        "overflow_cards": overflow_cards,
        "header_overlap": overlap_summary,
    }

before_state = state(before)
after_state = state(after)
notes = []
if before_state["fixed_overflow"] and not after_state["fixed_overflow"]:
    notes.append("- delta-summary: the fixed dialog or panel that overflowed off the right edge in the before view is fully contained in the after view.")
if before_state["header_overlap"] and not after_state["header_overlap"]:
    notes.append("- delta-summary: the filter chip bar stops overlapping the page title in the after view and now sits in its own row.")
if before_state["overflow_cards"] and not after_state["overflow_cards"]:
    notes.append("- delta-summary: the rightmost card no longer overflows the viewport in the after view because the grid wraps into another row.")
if not notes:
    notes.append("- delta-summary: the after screenshot removes one concrete visible layout defect from the same region shown in the before screenshot.")
print("\n".join(notes[:4]))
PY
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

score_delta_answer() {
  scenario=$1
  answer_lower=$2
  change_ref=0
  before_ref=0
  after_ref=0
  impact_ref=0
  case "$scenario" in
    dialog-viewport)
      if text_has_any "$answer_lower" "dialog" "modal" "panel" \
        && text_has_any "$answer_lower" "contained" "inside the viewport" "fully visible" "no longer clipped" "right edge"; then
        change_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "clipped" "off-screen" "offscreen" "right edge" "footer"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "fully visible" "contained" "inside" "footer" "viewport"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "approve" "confirm" "review" "complete" "button" "action"; then
        impact_ref=1
      fi
      ;;
    header-chip-stack)
      if text_has_any "$answer_lower" "filter" "chip" "title" "header" \
        && text_has_any "$answer_lower" "below" "no longer overlap" "separate" "clear" "stack"; then
        change_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "overlap" "title" "header" "top" "chip"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "below" "title" "header" "wrap" "separate row"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "readable" "scan" "header" "filter" "usable"; then
        impact_ref=1
      fi
      ;;
    card-grid-wrap)
      if text_has_any "$answer_lower" "card" "grid" \
        && text_has_any "$answer_lower" "wrap" "second row" "fully visible" "no longer clipped"; then
        change_ref=1
      fi
      if text_has_any "$answer_lower" "before evidence:" \
        && text_has_any "$answer_lower" "clipped" "right edge" "overflow" "rightmost"; then
        before_ref=1
      fi
      if text_has_any "$answer_lower" "after evidence:" \
        && text_has_any "$answer_lower" "second row" "wrap" "fully visible" "all cards"; then
        after_ref=1
      fi
      if text_has_any "$answer_lower" "all cards" "scan" "metric" "compare" "readable"; then
        impact_ref=1
      fi
      ;;
  esac
  printf '%s %s %s %s\n' "$change_ref" "$before_ref" "$after_ref" "$impact_ref"
}

label=$DEFAULT_LABEL
scenario="dialog-viewport"
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
  dialog-viewport|header-chip-stack|card-grid-wrap)
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
before_snapshot_json="$raw_dir/$scenario-before-layout.json"
after_snapshot_json="$raw_dir/$scenario-after-layout.json"
before_observations_txt="$raw_dir/$scenario-before-observations.txt"
after_observations_txt="$raw_dir/$scenario-after-observations.txt"
delta_observations_txt="$raw_dir/$scenario-delta-observations.txt"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("llava:7b")) then "llava:7b"
  else ""
  end
')
[ -n "$model" ] || { echo "llava:7b is required for before/after UI delta probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# Before/After UI Delta Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed before/after delta conversation.
EOF_README

render_delta_page "$scenario" before "$before_html"
render_delta_page "$scenario" after "$after_html"
capture_safari_screenshot "$before_html" "$before_png"
capture_safari_screenshot "$after_html" "$after_png"
capture_safari_layout_snapshot "$before_html" "$before_snapshot_json"
capture_safari_layout_snapshot "$after_html" "$after_snapshot_json"
derive_layout_observations "$before_snapshot_json" > "$before_observations_txt"
derive_layout_observations "$after_snapshot_json" > "$after_observations_txt"
derive_delta_observations "$before_snapshot_json" "$after_snapshot_json" > "$delta_observations_txt"

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
Compare the two attached Safari screenshots of the same local admin page. The first screenshot is BEFORE and the second screenshot is AFTER. Ignore browser chrome and use only visible screenshot evidence. Respond in exactly four lines starting with `Change:`, `Before Evidence:`, `After Evidence:`, and `Impact:`. Name the concrete visual or layout improvement, cite one visible cue from the before screenshot, cite one visible cue from the after screenshot, and explain why the change matters.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
if [ -s "$before_snapshot_json" ]; then
  before_snapshot_compact=$(jq -c . "$before_snapshot_json" 2>/dev/null || cat "$before_snapshot_json")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Before screenshot DOM and geometry snapshot from the same Safari view:
$before_snapshot_compact
EOF_PROMPT
)
fi
if [ -s "$after_snapshot_json" ]; then
  after_snapshot_compact=$(jq -c . "$after_snapshot_json" 2>/dev/null || cat "$after_snapshot_json")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

After screenshot DOM and geometry snapshot from the same Safari view:
$after_snapshot_compact
EOF_PROMPT
)
fi
if [ -s "$before_observations_txt" ]; then
  before_observations=$(cat "$before_observations_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Before screenshot geometry observations:
$before_observations
EOF_PROMPT
)
fi
if [ -s "$after_observations_txt" ]; then
  after_observations=$(cat "$after_observations_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

After screenshot geometry observations:
$after_observations
EOF_PROMPT
)
fi
if [ -s "$delta_observations_txt" ]; then
  delta_observations=$(cat "$delta_observations_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Delta observations comparing the two Safari views:
$delta_observations
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
has_change=$(printf '%s\n' "$assistant_lower" | grep -q '^change:' && printf '1' || printf '0')
has_before=$(printf '%s\n' "$assistant_lower" | grep -q '^before evidence:' && printf '1' || printf '0')
has_after=$(printf '%s\n' "$assistant_lower" | grep -q '^after evidence:' && printf '1' || printf '0')
has_impact=$(printf '%s\n' "$assistant_lower" | grep -q '^impact:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_change" -eq 1 ] && [ "$has_before" -eq 1 ] && [ "$has_after" -eq 1 ] && [ "$has_impact" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_delta_answer "$scenario" "$assistant_lower")
change_detected=$1
before_detected=$2
after_detected=$3
impact_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$before_exists" -eq 1 ] && [ "$after_exists" -eq 1 ] \
  && [ "$before_attachment_uploaded" -eq 1 ] && [ "$after_attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$change_detected" -eq 1 ] && [ "$before_detected" -eq 1 ] \
  && [ "$after_detected" -eq 1 ] && [ "$impact_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"before_exists":%s,"after_exists":%s,"before_attachment_uploaded":%s,"after_attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"change_detected":%s,"before_detected":%s,"after_detected":%s,"impact_detected":%s,"line_count":%s,"before_screenshot_path":%s,"after_screenshot_path":%s}\n' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$before_exists" "$after_exists" "$before_attachment_uploaded" "$after_attachment_uploaded" "$sections_complete" "$no_disclaimer" "$change_detected" "$before_detected" "$after_detected" "$impact_detected" "$line_count" "$(json_escape "$before_png")" "$(json_escape "$after_png")" > "$json_file"

{
  printf '# Before/After UI Delta Probe: %s\n\n' "$label"
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
  printf -- '- Change detected: %s\n' "$change_detected"
  printf -- '- Before evidence detected: %s\n' "$before_detected"
  printf -- '- After evidence detected: %s\n' "$after_detected"
  printf -- '- Impact detected: %s\n' "$impact_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Before screenshot: %s\n' "$before_png"
  printf -- '- After screenshot: %s\n' "$after_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
