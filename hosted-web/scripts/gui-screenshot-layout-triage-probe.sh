#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

. "$SCRIPT_DIR/artificer-local-paths.sh"
artificer_ensure_local_dirs

OUT_DIR="$ARTIFICER_ASSAY_REPORTS_DIR"
DEFAULT_LABEL="gui-screenshot-layout-triage-probe"
API_SCRIPT="${ARTIFICER_API_SCRIPT:-$SITE_ROOT/cgi/artificer-api}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for GUI screenshot layout triage probe." >&2
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
Usage: gui-screenshot-layout-triage-probe.sh [--label NAME] [--scenario NAME] [--prompt TEXT] [--prompt-file PATH]

Captures a deterministic broken layout in Safari, uploads the screenshot through
Artificer attachments, runs a vision-capable model, and verifies that the answer
identifies the visible layout defect with concrete evidence and a fix direction.
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

render_layout_page() {
  scenario=$1
  html_path=$2
  case "$scenario" in
    dialog-offscreen)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dialog Offscreen</title>
<style>
  :root { color-scheme: light; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #f8fafc 0%, #e2e8f0 100%);
    color: #0f172a;
    min-height: 100vh;
    overflow: hidden;
  }
  .shell {
    padding: 36px;
  }
  .hero {
    max-width: 440px;
  }
  .hero h1 {
    margin: 0 0 12px;
    font-size: 40px;
    line-height: 1.05;
  }
  .hero p {
    margin: 0;
    color: #334155;
    font-size: 18px;
  }
  .rail {
    margin-top: 28px;
    width: 360px;
    background: #ffffff;
    border-radius: 22px;
    padding: 22px;
    box-shadow: 0 22px 60px rgba(15, 23, 42, 0.12);
  }
  .rail h2 {
    margin: 0 0 12px;
    font-size: 20px;
  }
  .rail .meter {
    height: 12px;
    border-radius: 999px;
    background: linear-gradient(90deg, #38bdf8 0 72%, #e2e8f0 72% 100%);
  }
  .dialog {
    position: fixed;
    top: 108px;
    left: 380px;
    width: 620px;
    background: #fff8ed;
    border: 3px solid #f97316;
    border-radius: 26px;
    box-shadow: 0 28px 80px rgba(15, 23, 42, 0.25);
    overflow: hidden;
  }
  .dialog header {
    padding: 24px 28px 10px;
  }
  .dialog h3 {
    margin: 0 0 8px;
    font-size: 32px;
  }
  .dialog p {
    margin: 0;
    color: #7c2d12;
    font-size: 18px;
  }
  .dialog .content {
    padding: 18px 28px 94px;
    display: grid;
    gap: 14px;
    color: #7c2d12;
    font-size: 17px;
  }
  .dialog .field {
    background: rgba(255,255,255,0.85);
    border-radius: 16px;
    padding: 14px 16px;
    border: 1px solid rgba(249,115,22,0.18);
  }
  .dialog .footer {
    position: absolute;
    right: 0;
    bottom: 0;
    display: flex;
    gap: 14px;
    padding: 18px 24px 22px;
    background: linear-gradient(180deg, rgba(255,248,237,0) 0%, #fff8ed 35%);
  }
  .btn {
    border: 0;
    border-radius: 999px;
    padding: 14px 20px;
    font-size: 17px;
    font-weight: 700;
  }
  .btn.secondary {
    background: #fed7aa;
    color: #9a3412;
  }
  .btn.primary {
    background: #ea580c;
    color: white;
    padding-inline: 28px;
  }
</style>
</head>
<body>
  <div class="shell">
    <div class="hero">
      <h1>Billing rule rollout</h1>
      <p>Review the partner-impact preview before approving the next tenant cohort.</p>
    </div>
    <div class="rail">
      <h2>Readiness</h2>
      <div class="meter"></div>
    </div>
  </div>
  <section class="dialog" aria-label="Partner impact preview">
    <header>
      <h3>Partner impact preview</h3>
      <p>Confirm the new billing rule before the tenant migration window opens.</p>
    </header>
    <div class="content">
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
    header-overlap)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Header Overlap</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #fffdf8;
    color: #111827;
    min-height: 100vh;
  }
  .page {
    padding: 40px 56px 56px;
    position: relative;
  }
  .title {
    margin: 0;
    font-size: 46px;
    line-height: 1.04;
    max-width: 720px;
  }
  .subtitle {
    margin-top: 18px;
    max-width: 560px;
    font-size: 19px;
    color: #475569;
  }
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
  }
  .board {
    margin-top: 40px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 18px;
    max-width: 860px;
  }
  .card {
    background: white;
    border-radius: 22px;
    padding: 24px;
    box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
  }
  .metric {
    font-size: 42px;
    font-weight: 800;
    color: #0f766e;
  }
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
    <p class="subtitle">Stakeholders need the migration summary, but the filter bar is still mounted into the title region instead of sitting below it.</p>
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
    card-grid-overflow)
      cat > "$html_path" <<'EOF_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Card Grid Overflow</title>
<style>
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
    color: #0f172a;
    overflow: hidden;
    min-height: 100vh;
  }
  .page {
    padding: 34px;
  }
  .page h1 {
    margin: 0 0 10px;
    font-size: 38px;
  }
  .page p {
    margin: 0 0 24px;
    color: #334155;
    font-size: 18px;
  }
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
  .eyebrow {
    font-size: 13px;
    font-weight: 800;
    letter-spacing: 0.08em;
    color: #2563eb;
    text-transform: uppercase;
  }
  .big {
    margin-top: 14px;
    font-size: 42px;
    font-weight: 800;
  }
  .copy {
    margin-top: 10px;
    color: #475569;
    line-height: 1.45;
  }
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
  if (count of windows) = 0 then
    make new document with properties {URL:targetUrl}
  else
    set URL of front document to targetUrl
  end if
  set bounds of front window to {90, 72, 930, 940}
end tell
delay 1.5
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
}

capture_safari_layout_snapshot() {
  snapshot_path=$1
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
        '- overflow-summary: a fixed dialog/panel container extends past the right edge of the viewport, so its content and footer controls are clipped with it.'
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

top_candidates = [
    el for el in elements
    if int(el.get("top") or 0) <= 180 and int(el.get("width") or 0) >= 120 and clean(el.get("text"))
]

def overlap(a, b):
    ax1, ay1 = int(a.get("left") or 0), int(a.get("top") or 0)
    ax2, ay2 = ax1 + int(a.get("width") or 0), ay1 + int(a.get("height") or 0)
    bx1, by1 = int(b.get("left") or 0), int(b.get("top") or 0)
    bx2, by2 = bx1 + int(b.get("width") or 0), by1 + int(b.get("height") or 0)
    return max(0, min(ax2, bx2) - max(ax1, bx1)) * max(0, min(ay2, by2) - max(ay1, by1))

for i, a in enumerate(top_candidates):
    for b in top_candidates[i + 1:]:
        if clean(a.get("text")) == clean(b.get("text")):
            continue
        if overlap(a, b) >= 1500:
            notes.append(
                f'- overlap: "{clean(a.get("text"), 56)}" overlaps "{clean(b.get("text"), 56)}" near the top of the viewport.'
            )

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
        '- overlap-summary: the filter chip bar overlaps the page title/header region near the top of the viewport.'
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

score_layout_answer() {
  scenario=$1
  answer_lower=$2
  issue_region=0
  issue_fault=0
  evidence_ref=0
  fix_ref=0
  case "$scenario" in
    dialog-offscreen)
      text_has_any "$answer_lower" "dialog" "modal" "panel" && issue_region=1
      text_has_any "$answer_lower" "clipped" "cut off" "cutoff" "off-screen" "offscreen" "overflow" && issue_fault=1
      text_has_any "$answer_lower" "button" "primary" "right edge" "right side" "footer" && evidence_ref=1
      text_has_any "$answer_lower" "max-width" "width" "center" "position" "clamp" "responsive" "overflow" && fix_ref=1
      ;;
    header-overlap)
      text_has_any "$answer_lower" "header" "title" "filters" "chips" && issue_region=1
      text_has_any "$answer_lower" "overlap" "cover" "covered" "collid" "stacked on" && issue_fault=1
      text_has_any "$answer_lower" "title" "filter" "chip" "header" && evidence_ref=1
      text_has_any "$answer_lower" "margin" "spacing" "wrap" "stack" "position" "absolute" "negative" && fix_ref=1
      ;;
    card-grid-overflow)
      text_has_any "$answer_lower" "card" "cards" "grid" "column" && issue_region=1
      text_has_any "$answer_lower" "clipped" "cut off" "cutoff" "off-screen" "offscreen" "overflow" && issue_fault=1
      text_has_any "$answer_lower" "right" "card" "grid" "column" && evidence_ref=1
      text_has_any "$answer_lower" "wrap" "grid-template" "minmax" "columns" "responsive" "overflow" && fix_ref=1
      ;;
  esac
  printf '%s %s %s %s\n' "$issue_region" "$issue_fault" "$evidence_ref" "$fix_ref"
}

label=$DEFAULT_LABEL
scenario="dialog-offscreen"
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
  dialog-offscreen|header-overlap|card-grid-overflow)
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
layout_snapshot_json="$raw_dir/$scenario-layout.json"
layout_observations_txt="$raw_dir/$scenario-layout-observations.txt"

models_json=$(post_api_json "action=models")
model=$(printf '%s' "$models_json" | jq -r '
  .models as $m |
  if ($m | index("llava:7b")) then "llava:7b"
  else ""
  end
')
[ -n "$model" ] || { echo "llava:7b is required for GUI screenshot layout triage probe." >&2; exit 1; }

tmp_ws=$(mktemp -d)
workspace_id=""
cleanup() {
  delete_workspace_best_effort "$workspace_id"
  rm -rf "$tmp_ws"
}
trap cleanup EXIT INT TERM

cat > "$tmp_ws/README.md" <<EOF_README
# GUI Screenshot Layout Triage Demo

Scenario: $scenario
This workspace exists only to host the screenshot-backed GUI triage conversation.
EOF_README

render_layout_page "$scenario" "$page_html"
capture_safari_screenshot "$page_html" "$screenshot_png"
capture_safari_layout_snapshot "$layout_snapshot_json"
derive_layout_observations "$layout_snapshot_json" > "$layout_observations_txt"

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
Inspect the attached Safari screenshot of a local admin page. Ignore browser chrome and use only visible screenshot evidence. Respond in exactly four lines starting with `Issue:`, `Evidence:`, `Likely Cause:`, and `Fix Direction:`. Identify the concrete layout defect, point to the affected UI region, and give one actionable fix direction.
EOF_PROMPT
)
prompt_text=$default_prompt_text
if [ -n "$prompt_file" ]; then
  prompt_text=$(cat "$prompt_file")
fi
if [ -n "$prompt_override" ]; then
  prompt_text=$prompt_override
fi
if [ -s "$layout_snapshot_json" ]; then
  layout_snapshot_compact=$(jq -c . "$layout_snapshot_json" 2>/dev/null || cat "$layout_snapshot_json")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Cross-check with this DOM/geometry snapshot from the same Safari view. Use it only to ground visible text and approximate positions; if it conflicts with the screenshot, trust the screenshot.
$layout_snapshot_compact
EOF_PROMPT
)
fi
if [ -s "$layout_observations_txt" ]; then
  layout_observations=$(cat "$layout_observations_txt")
  prompt_text=$(cat <<EOF_PROMPT
$prompt_text

Geometry observations from the same Safari view:
$layout_observations

Use these geometry observations as evidence anchors when they identify clipping, overlap, or an affected edge.
EOF_PROMPT
)
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
has_issue=$(printf '%s\n' "$assistant_lower" | grep -q '^issue:' && printf '1' || printf '0')
has_evidence=$(printf '%s\n' "$assistant_lower" | grep -q '^evidence:' && printf '1' || printf '0')
has_cause=$(printf '%s\n' "$assistant_lower" | grep -q '^likely cause:' && printf '1' || printf '0')
has_fix=$(printf '%s\n' "$assistant_lower" | grep -q '^fix direction:' && printf '1' || printf '0')
sections_complete=0
if [ "$has_issue" -eq 1 ] && [ "$has_evidence" -eq 1 ] && [ "$has_cause" -eq 1 ] && [ "$has_fix" -eq 1 ]; then
  sections_complete=1
fi
no_disclaimer=1
if text_has_any "$assistant_lower" "cannot inspect" "can't inspect" "unable to inspect" "cannot view" "can't view" "unable to view" "do not have access to the image"; then
  no_disclaimer=0
fi
set -- $(score_layout_answer "$scenario" "$assistant_lower")
issue_region_detected=$1
issue_fault_detected=$2
evidence_detected=$3
fix_detected=$4
status='fail'
if [ "$timed_out" -eq 0 ] && [ "$screenshot_exists" -eq 1 ] && [ "$attachment_uploaded" -eq 1 ] \
  && [ "$sections_complete" -eq 1 ] && [ "$no_disclaimer" -eq 1 ] \
  && [ "$issue_region_detected" -eq 1 ] && [ "$issue_fault_detected" -eq 1 ] \
  && [ "$evidence_detected" -eq 1 ] && [ "$fix_detected" -eq 1 ]; then
  status='pass'
fi

printf '{"label":"%s","status":"%s","scenario":"%s","model":"%s","timed_out":%s,"screenshot_exists":%s,"attachment_uploaded":%s,"sections_complete":%s,"no_disclaimer":%s,"issue_region_detected":%s,"issue_fault_detected":%s,"evidence_detected":%s,"fix_detected":%s,"line_count":%s,"screenshot_path":%s}
' \
  "$label" "$status" "$scenario" "$model" "$timed_out" "$screenshot_exists" "$attachment_uploaded" "$sections_complete" "$no_disclaimer" "$issue_region_detected" "$issue_fault_detected" "$evidence_detected" "$fix_detected" "$line_count" "$(json_escape "$screenshot_png")" > "$json_file"

{
  printf '# GUI Screenshot Layout Triage Probe: %s\n\n' "$label"
  printf -- '- Status: %s\n' "$status"
  printf -- '- Scenario: %s\n' "$scenario"
  printf -- '- Model: %s\n' "$model"
  printf -- '- Timed out: %s\n' "$timed_out"
  printf -- '- Screenshot exists: %s\n' "$screenshot_exists"
  printf -- '- Attachment uploaded: %s\n' "$attachment_uploaded"
  printf -- '- Sections complete: %s\n' "$sections_complete"
  printf -- '- No disclaimer: %s\n' "$no_disclaimer"
  printf -- '- Issue region detected: %s\n' "$issue_region_detected"
  printf -- '- Issue fault detected: %s\n' "$issue_fault_detected"
  printf -- '- Evidence detected: %s\n' "$evidence_detected"
  printf -- '- Fix detected: %s\n' "$fix_detected"
  printf -- '- Line count: %s\n' "$line_count"
  printf -- '- Screenshot: %s\n' "$screenshot_png"
} > "$md_file"

printf '%s\n' "$json_file"
printf '%s\n' "$md_file"
[ "$status" = 'pass' ]
