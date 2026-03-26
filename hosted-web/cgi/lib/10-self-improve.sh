self_improve_selected_model() {
  printf '%s' "$(trim "$(read_file_line "$self_improve_model_file" "")")"
}

set_self_improve_selected_model() {
  next_model=$1
  mkdir -p "$llm_settings_dir"
  printf '%s\n' "$next_model" > "$self_improve_model_file"
}

self_improve_default_objective() {
  printf '%s' "Improve Artificer's end-to-end self-improvement ability across web research, knowledge integration, planning, architecture, programming, verification, and local admin setup while keeping every improvement reversible and push-ready."
}

self_improve_param_present() {
  key=$1
  case "&${post_data}&${query_data}&" in
    *"&$key="*)
      return 0
      ;;
  esac
  return 1
}

self_improve_run_options_json() {
  default_objective=$(self_improve_default_objective)
  python3 - "$self_improve_run_options_file" "$default_objective" <<'PY'
import json
import os
import sys

path = sys.argv[1]
default_objective = str(sys.argv[2]).strip()
defaults = {
    "objective": default_objective,
    "competition_enabled": True,
    "challenger_model": "",
    "sources": {
        "papers": True,
        "web": True,
        "runtime": True,
        "repo": True,
        "platform": True,
    },
}


def as_bool(value, fallback):
    if isinstance(value, bool):
        return value
    if value is None:
        return fallback
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on", "enabled"}:
        return True
    if text in {"0", "false", "no", "off", "disabled"}:
        return False
    return fallback


def normalize(payload):
    if not isinstance(payload, dict):
        payload = {}
    objective = " ".join(str(payload.get("objective", defaults["objective"])).split()).strip()
    if not objective:
        objective = defaults["objective"]
    competition_enabled = as_bool(payload.get("competition_enabled"), defaults["competition_enabled"])
    challenger_model = " ".join(str(payload.get("challenger_model", "")).split()).strip()
    raw_sources = payload.get("sources", {})
    if not isinstance(raw_sources, dict):
        raw_sources = {}
    sources = {}
    for key, default in defaults["sources"].items():
        sources[key] = as_bool(raw_sources.get(key), default)
    return {
        "objective": objective,
        "competition_enabled": competition_enabled,
        "challenger_model": challenger_model,
        "sources": sources,
    }


payload = {}
if os.path.isfile(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        payload = {}

print(json.dumps(normalize(payload), ensure_ascii=False, separators=(",", ":")))
PY
}

set_self_improve_run_options_json() {
  options_json=$1
  default_objective=$(self_improve_default_objective)
  mkdir -p "$llm_settings_dir"
  python3 - "$self_improve_run_options_file" "$options_json" "$default_objective" <<'PY'
import json
import sys

path = sys.argv[1]
options_json = sys.argv[2]
default_objective = str(sys.argv[3]).strip()
defaults = {
    "objective": default_objective,
    "competition_enabled": True,
    "challenger_model": "",
    "sources": {
        "papers": True,
        "web": True,
        "runtime": True,
        "repo": True,
        "platform": True,
    },
}


def as_bool(value, fallback):
    if isinstance(value, bool):
        return value
    if value is None:
        return fallback
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on", "enabled"}:
        return True
    if text in {"0", "false", "no", "off", "disabled"}:
        return False
    return fallback


def normalize(payload):
    if not isinstance(payload, dict):
        payload = {}
    objective = " ".join(str(payload.get("objective", defaults["objective"])).split()).strip()
    if not objective:
        objective = defaults["objective"]
    competition_enabled = as_bool(payload.get("competition_enabled"), defaults["competition_enabled"])
    challenger_model = " ".join(str(payload.get("challenger_model", "")).split()).strip()
    raw_sources = payload.get("sources", {})
    if not isinstance(raw_sources, dict):
        raw_sources = {}
    sources = {}
    for key, default in defaults["sources"].items():
        sources[key] = as_bool(raw_sources.get(key), default)
    return {
        "objective": objective,
        "competition_enabled": competition_enabled,
        "challenger_model": challenger_model,
        "sources": sources,
    }


try:
    incoming = json.loads(options_json) if options_json else {}
except Exception:
    incoming = {}
normalized = normalize(incoming)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(normalized, handle, ensure_ascii=False, indent=2)
print(json.dumps(normalized, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_run_options_merge_json() {
  objective_value=$1
  competition_value=$2
  challenger_value=$3
  source_papers_value=$4
  source_web_value=$5
  source_runtime_value=$6
  source_repo_value=$7
  source_platform_value=$8

  current_json=$(self_improve_run_options_json)
  default_objective=$(self_improve_default_objective)
  python3 - "$current_json" "$objective_value" "$competition_value" "$challenger_value" "$source_papers_value" "$source_web_value" "$source_runtime_value" "$source_repo_value" "$source_platform_value" "$default_objective" <<'PY'
import json
import sys

current_json, objective_value, competition_value, challenger_value, source_papers_value, source_web_value, source_runtime_value, source_repo_value, source_platform_value, default_objective = sys.argv[1:11]
keep = "__ARTIFICER_KEEP__"


def as_bool(value, fallback):
    if isinstance(value, bool):
        return value
    if value is None:
        return fallback
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on", "enabled"}:
        return True
    if text in {"0", "false", "no", "off", "disabled"}:
        return False
    return fallback


def normalize(payload):
    defaults = {
        "objective": default_objective,
        "competition_enabled": True,
        "challenger_model": "",
        "sources": {
            "papers": True,
            "web": True,
            "runtime": True,
            "repo": True,
            "platform": True,
        },
    }
    if not isinstance(payload, dict):
        payload = {}
    objective = " ".join(str(payload.get("objective", defaults["objective"])).split()).strip()
    if not objective:
        objective = defaults["objective"]
    competition_enabled = as_bool(payload.get("competition_enabled"), defaults["competition_enabled"])
    challenger_model = " ".join(str(payload.get("challenger_model", "")).split()).strip()
    raw_sources = payload.get("sources", {})
    if not isinstance(raw_sources, dict):
        raw_sources = {}
    sources = {}
    for key, fallback in defaults["sources"].items():
        sources[key] = as_bool(raw_sources.get(key), fallback)
    return {
        "objective": objective,
        "competition_enabled": competition_enabled,
        "challenger_model": challenger_model,
        "sources": sources,
    }


try:
    payload = json.loads(current_json) if current_json else {}
except Exception:
    payload = {}
normalized = normalize(payload)

if objective_value != keep:
    next_objective = " ".join(str(objective_value).split()).strip()
    normalized["objective"] = next_objective or default_objective
if competition_value != keep:
    normalized["competition_enabled"] = as_bool(competition_value, normalized["competition_enabled"])
if challenger_value != keep:
    normalized["challenger_model"] = " ".join(str(challenger_value).split()).strip()
if source_papers_value != keep:
    normalized["sources"]["papers"] = as_bool(source_papers_value, normalized["sources"]["papers"])
if source_web_value != keep:
    normalized["sources"]["web"] = as_bool(source_web_value, normalized["sources"]["web"])
if source_runtime_value != keep:
    normalized["sources"]["runtime"] = as_bool(source_runtime_value, normalized["sources"]["runtime"])
if source_repo_value != keep:
    normalized["sources"]["repo"] = as_bool(source_repo_value, normalized["sources"]["repo"])
if source_platform_value != keep:
    normalized["sources"]["platform"] = as_bool(source_platform_value, normalized["sources"]["platform"])

print(json.dumps(normalized, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_plugins_json() {
  python3 - "$self_improve_plugins_dir" <<'PY'
import json
import os
import sys

plugins_dir = sys.argv[1]
items = []
if os.path.isdir(plugins_dir):
    for name in sorted(os.listdir(plugins_dir)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(plugins_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            continue
        if not isinstance(payload, dict):
            continue
        payload.setdefault("id", os.path.splitext(name)[0])
        payload["enabled"] = bool(payload.get("enabled", True))
        payload.setdefault("source_lane", "")
        payload.setdefault("risk_level", "medium")
        payload.setdefault("domain_tags", [])
        payload.setdefault("evidence_refs", [])
        payload.setdefault("admin_actions", [])
        items.append(payload)
print(json.dumps(items, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_last_run_json() {
  if [ ! -f "$self_improve_last_run_file" ]; then
    printf '{"summary":"","generated_at":"","model":"","papers":[],"web_signals":[],"objective":"","competition_enabled":false,"winner_lane":"","winner_model":"","lane_scores":{},"evidence_counts":{},"run_options":{},"lanes":[],"plugin_ids":[]}'
    return 0
  fi
  python3 - "$self_improve_last_run_file" <<'PY'
import json
import sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    payload = {}
if not isinstance(payload, dict):
    payload = {}
payload.setdefault("summary", "")
payload.setdefault("generated_at", "")
payload.setdefault("model", "")
payload.setdefault("papers", [])
payload.setdefault("web_signals", [])
payload.setdefault("plugin_ids", [])
payload.setdefault("objective", "")
payload.setdefault("competition_enabled", False)
payload.setdefault("winner_lane", "")
payload.setdefault("winner_model", "")
payload.setdefault("lane_scores", {})
payload.setdefault("evidence_counts", {})
payload.setdefault("run_options", {})
payload.setdefault("lanes", [])
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_settings_json() {
  selected_model=$(self_improve_selected_model)
  plugins_json=$(self_improve_plugins_json)
  last_run_json=$(self_improve_last_run_json)
  run_options_json=$(self_improve_run_options_json)
  printf '{"success":true,"selected_model":"%s","run_options":%s,"plugins":%s,"last_run":%s}\n' \
    "$(json_escape "$selected_model")" \
    "$run_options_json" \
    "$plugins_json" \
    "$last_run_json"
}

self_improve_fetch_research_json() {
  python3 - <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

queries = [
    "large language model reasoning verification planning",
    "large language model self refinement self correction",
    "large language model tool use retrieval augmentation",
    "large language model uncertainty calibration hallucination mitigation",
]

headers = {
    "User-Agent": "Artificer/1.0 (self-improve paper search)"
}

papers = []
seen = set()

def add_item(item):
    title = " ".join(str(item.get("title", "")).split()).strip()
    if not title:
      return
    key = title.lower()
    if key in seen:
      return
    seen.add(key)
    papers.append(item)

for query in queries:
    encoded = urllib.parse.quote(query)
    try:
        req = urllib.request.Request(
            f"https://export.arxiv.org/api/query?search_query=all:{encoded}&start=0&max_results=3&sortBy=relevance&sortOrder=descending",
            headers=headers,
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            root = ET.fromstring(resp.read())
        ns = {"a": "http://www.w3.org/2005/Atom"}
        for entry in root.findall("a:entry", ns):
            title = entry.findtext("a:title", default="", namespaces=ns)
            summary = entry.findtext("a:summary", default="", namespaces=ns)
            link = entry.findtext("a:id", default="", namespaces=ns)
            published = entry.findtext("a:published", default="", namespaces=ns)
            authors = [node.findtext("a:name", default="", namespaces=ns) for node in entry.findall("a:author", ns)]
            add_item({
                "source": "arXiv",
                "query": query,
                "title": title,
                "summary": " ".join(summary.split()),
                "url": link,
                "published": published[:10],
                "authors": [a for a in authors if a][:4],
            })
    except Exception:
        pass
    time.sleep(0.15)

for query in queries[:3]:
    encoded = urllib.parse.quote(query)
    try:
        req = urllib.request.Request(
            "https://api.crossref.org/works?rows=3&select=title,URL,DOI,issued,author"
            + f"&query.title={encoded}&filter=type:journal-article",
            headers=headers,
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        for item in payload.get("message", {}).get("items", []):
            title_list = item.get("title") or []
            title = title_list[0] if title_list else ""
            authors = []
            for author in item.get("author", [])[:4]:
                given = author.get("given", "")
                family = author.get("family", "")
                authors.append(" ".join(part for part in [given, family] if part))
            issued = item.get("issued", {}).get("date-parts", [[]])
            published = ""
            if issued and issued[0]:
                published = "-".join(str(part) for part in issued[0][:3])
            add_item({
                "source": "Crossref",
                "query": query,
                "title": title,
                "summary": "",
                "url": item.get("URL") or ("https://doi.org/" + item.get("DOI", "") if item.get("DOI") else ""),
                "published": published,
                "authors": [a for a in authors if a],
            })
    except Exception:
        pass
    time.sleep(0.15)

papers = papers[:10]
print(json.dumps({"papers": papers}, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_fetch_web_signals_json() {
  python3 - <<'PY'
import json
import time
import urllib.parse
import urllib.request

topics = [
    "llm agent reliability",
    "local llm automation scheduler",
    "llm code verification workflow",
]

headers = {
    "User-Agent": "Artificer/1.0 (self-improve web signals)",
    "Accept": "application/json",
}

signals = []
seen = set()


def add_signal(item):
    title = " ".join(str(item.get("title", "")).split()).strip()
    if not title:
        return
    key = title.lower()
    if key in seen:
        return
    seen.add(key)
    signals.append(item)


for topic in topics:
    encoded = urllib.parse.quote(topic)
    try:
        req = urllib.request.Request(
            f"https://hn.algolia.com/api/v1/search?tags=story&hitsPerPage=2&query={encoded}",
            headers=headers,
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        for hit in payload.get("hits", [])[:2]:
            title = hit.get("title") or hit.get("story_title") or ""
            url = hit.get("url") or ""
            published = str(hit.get("created_at", ""))[:10]
            summary = ""
            points = hit.get("points")
            if points is not None:
                summary = f"HN points: {points}"
            add_signal({
                "source": "Hacker News",
                "topic": topic,
                "title": title,
                "summary": summary,
                "url": url,
                "published": published,
                "tags": ["news", "engineering"],
            })
    except Exception:
        pass
    time.sleep(0.12)

for topic in topics:
    encoded = urllib.parse.quote(topic)
    try:
        req = urllib.request.Request(
            f"https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q={encoded}&site=stackoverflow&pagesize=2",
            headers=headers,
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        for item in payload.get("items", [])[:2]:
            title = item.get("title", "")
            url = item.get("link", "")
            published = ""
            creation_date = item.get("creation_date")
            if isinstance(creation_date, int) and creation_date > 0:
                published = time.strftime("%Y-%m-%d", time.gmtime(creation_date))
            tags = [str(tag).strip() for tag in item.get("tags", [])[:4] if str(tag).strip()]
            add_signal({
                "source": "Stack Overflow",
                "topic": topic,
                "title": title,
                "summary": "Community troubleshooting signal",
                "url": url,
                "published": published,
                "tags": tags,
            })
    except Exception:
        pass
    time.sleep(0.12)

try:
    req = urllib.request.Request(
        "https://api.github.com/search/issues?q=llm+agent+reliability+in:title,body&sort=updated&order=desc&per_page=4",
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    for item in payload.get("items", [])[:4]:
        title = item.get("title", "")
        url = item.get("html_url", "")
        published = str(item.get("updated_at", ""))[:10]
        repo_url = item.get("repository_url", "")
        repo_name = repo_url.split("/")[-1] if repo_url else ""
        summary = "Issue and ops signal"
        if repo_name:
            summary = f"Issue and ops signal ({repo_name})"
        add_signal({
            "source": "GitHub Issues",
            "topic": "llm agent reliability",
            "title": title,
            "summary": summary,
            "url": url,
            "published": published,
            "tags": ["github", "issues", "ops"],
        })
except Exception:
    pass

signals = signals[:12]
print(json.dumps({"web_signals": signals}, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_runtime_signals_json() {
  failure_summary="none"
  quality_summary="none"
  proposal_summary="none"
  controller_json="{}"

  if [ "$mode_runtime_lib_loaded" = "1" ]; then
    ensure_mode_runtime_bootstrap
    if command -v mr_failure_taxonomy_recent_summary_text >/dev/null 2>&1; then
      failure_summary=$(mr_failure_taxonomy_recent_summary_text "12")
    fi
    if command -v mr_quality_scorecard_recent_summary_text >/dev/null 2>&1; then
      quality_summary=$(mr_quality_scorecard_recent_summary_text "12")
    fi
    if command -v mr_improvement_proposals_recent_summary_text >/dev/null 2>&1; then
      proposal_summary=$(mr_improvement_proposals_recent_summary_text "" "20" "4")
    fi
    if command -v mr_controller_variants_state_json >/dev/null 2>&1; then
      controller_json=$(mr_controller_variants_state_json)
    fi
  fi

  RUNTIME_CONTROLLER_JSON=$controller_json python3 - "$mode_runtime_root" "$failure_summary" "$quality_summary" "$proposal_summary" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
failure_summary = " ".join(str(sys.argv[2]).split()).strip() or "none"
quality_summary = " ".join(str(sys.argv[3]).split()).strip() or "none"
proposal_summary = " ".join(str(sys.argv[4]).split()).strip() or "none"
controller_raw = os.environ.get("RUNTIME_CONTROLLER_JSON", "{}")


def line_count(path):
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            return sum(1 for _ in handle)
    except Exception:
        return 0


failure_events = line_count(root / "failure-taxonomy" / "events.tsv")
quality_entries = line_count(root / "quality-scorecard" / "entries.tsv")
proposal_count = 0
proposal_root = root / "improvement-proposals"
if proposal_root.is_dir():
    for child in proposal_root.iterdir():
        if not child.is_dir():
            continue
        if (child / "meta.env").is_file():
            proposal_count += 1

try:
    controller_state = json.loads(controller_raw)
    if not isinstance(controller_state, dict):
        controller_state = {}
except Exception:
    controller_state = {}

payload = {
    "failure_summary": failure_summary,
    "quality_summary": quality_summary,
    "proposal_summary": proposal_summary,
    "controller_variants": controller_state,
    "counts": {
        "failure_events": failure_events,
        "quality_entries": quality_entries,
        "proposal_items": proposal_count,
    },
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_repo_signals_json() {
  repo_root=$(artificer_app_root_for_runtime)
  if [ -z "$repo_root" ]; then
    repo_root=$(CDPATH= cd -- "$ARTIFICER_SCRIPT_DIR/../.." 2>/dev/null && pwd -P || true)
  fi
  python3 - "$repo_root" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

repo_root = pathlib.Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else pathlib.Path(".")
if not repo_root.is_dir():
    print(json.dumps({"repo_root": "", "worktree": {}, "top_extensions": [], "todo_hotspots": [], "workflows": [], "release_scripts": []}, ensure_ascii=False, separators=(",", ":")))
    sys.exit(0)


def run_git(*args):
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=12,
        )
        return proc.returncode, proc.stdout or ""
    except Exception:
        return 1, ""


tracked = 0
untracked = 0
rc, status_output = run_git("status", "--short")
if rc == 0:
    for line in status_output.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("??"):
            untracked += 1
        else:
            tracked += 1

ignore_dirs = {".git", "node_modules", ".venv", "venv", "dist", "build", "tmp", ".cache"}
ext_counts = {}
text_candidates = []
scanned = 0
for path in repo_root.rglob("*"):
    if scanned >= 2600:
        break
    if not path.is_file():
        continue
    rel_parts = set(path.relative_to(repo_root).parts)
    if rel_parts & ignore_dirs:
        continue
    scanned += 1
    ext = path.suffix.lower() or "[none]"
    ext_counts[ext] = ext_counts.get(ext, 0) + 1
    if ext in {".sh", ".md", ".txt", ".js", ".ts", ".css", ".json", ".yml", ".yaml", ".py"}:
        text_candidates.append(path)

top_extensions = [
    {"ext": ext, "count": count}
    for ext, count in sorted(ext_counts.items(), key=lambda item: (-item[1], item[0]))[:10]
]

todo_hotspots = []
todo_pattern = re.compile(r"\b(TODO|FIXME|HACK)\b", re.IGNORECASE)
for path in text_candidates[:220]:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    matches = len(todo_pattern.findall(text))
    if matches <= 0:
        continue
    todo_hotspots.append({
        "path": str(path.relative_to(repo_root)),
        "count": matches,
    })
todo_hotspots.sort(key=lambda item: (-item["count"], item["path"]))
todo_hotspots = todo_hotspots[:8]

workflow_dir = repo_root / ".github" / "workflows"
workflows = []
if workflow_dir.is_dir():
    for path in sorted(workflow_dir.glob("*.y*ml"))[:20]:
        workflows.append(path.name)

release_scripts = []
for rel in [
    "install-artificer",
    "uninstall-artificer",
    "scripts/build-release-linux.sh",
    "scripts/build-release-macos-app.sh",
    "scripts/artificer-automations.sh",
]:
    target = repo_root / rel
    release_scripts.append({
        "path": rel,
        "exists": target.exists(),
    })

payload = {
    "repo_root": str(repo_root),
    "worktree": {
        "tracked_changes": tracked,
        "untracked_changes": untracked,
    },
    "top_extensions": top_extensions,
    "todo_hotspots": todo_hotspots,
    "workflows": workflows,
    "release_scripts": release_scripts,
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_platform_signals_json() {
  python3 - <<'PY'
import json
import platform
import shutil

commands = [
    "git",
    "curl",
    "python3",
    "node",
    "npm",
    "ollama",
    "launchctl",
    "systemctl",
    "crontab",
    "brew",
    "apt-get",
    "dnf",
    "pacman",
]
available = {name: bool(shutil.which(name)) for name in commands}

payload = {
    "os": platform.system().lower(),
    "arch": platform.machine().lower(),
    "commands": available,
    "scheduler_support": {
        "launchd": available.get("launchctl", False),
        "systemd_user": available.get("systemctl", False),
        "cron": available.get("crontab", False),
    },
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_build_evidence_bundle_json() {
  run_options_json=$1
  options_flags=$(SELF_IMPROVE_OPTIONS_JSON=$run_options_json python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("SELF_IMPROVE_OPTIONS_JSON", "") or "{}")
except Exception:
    payload = {}
if not isinstance(payload, dict):
    payload = {}
sources = payload.get("sources", {})
if not isinstance(sources, dict):
    sources = {}


def as_bool(value, default):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on", "enabled"}:
        return True
    if text in {"0", "false", "no", "off", "disabled"}:
        return False
    return default


print(f"papers={'1' if as_bool(sources.get('papers'), True) else '0'}")
print(f"web={'1' if as_bool(sources.get('web'), True) else '0'}")
print(f"runtime={'1' if as_bool(sources.get('runtime'), True) else '0'}")
print(f"repo={'1' if as_bool(sources.get('repo'), True) else '0'}")
print(f"platform={'1' if as_bool(sources.get('platform'), True) else '0'}")
PY
)

  source_papers=$(kv_get "papers" "$options_flags")
  source_web=$(kv_get "web" "$options_flags")
  source_runtime=$(kv_get "runtime" "$options_flags")
  source_repo=$(kv_get "repo" "$options_flags")
  source_platform=$(kv_get "platform" "$options_flags")

  papers_json='{"papers":[]}'
  web_json='{"web_signals":[]}'
  runtime_json='{"failure_summary":"none","quality_summary":"none","proposal_summary":"none","controller_variants":{},"counts":{"failure_events":0,"quality_entries":0,"proposal_items":0}}'
  repo_json='{"repo_root":"","worktree":{"tracked_changes":0,"untracked_changes":0},"top_extensions":[],"todo_hotspots":[],"workflows":[],"release_scripts":[]}'
  platform_json='{"os":"","arch":"","commands":{},"scheduler_support":{"launchd":false,"systemd_user":false,"cron":false}}'

  if [ "$source_papers" = "1" ]; then
    papers_json=$(self_improve_fetch_research_json)
  fi
  if [ "$source_web" = "1" ]; then
    web_json=$(self_improve_fetch_web_signals_json)
  fi
  if [ "$source_runtime" = "1" ]; then
    runtime_json=$(self_improve_runtime_signals_json)
  fi
  if [ "$source_repo" = "1" ]; then
    repo_json=$(self_improve_repo_signals_json)
  fi
  if [ "$source_platform" = "1" ]; then
    platform_json=$(self_improve_platform_signals_json)
  fi

  python3 - "$run_options_json" "$papers_json" "$web_json" "$runtime_json" "$repo_json" "$platform_json" <<'PY'
import json
import sys

run_options_json, papers_json, web_json, runtime_json, repo_json, platform_json = sys.argv[1:7]


def parse_json(raw, fallback):
    try:
        payload = json.loads(raw) if raw else fallback
    except Exception:
        payload = fallback
    if isinstance(fallback, dict) and not isinstance(payload, dict):
        payload = fallback
    if isinstance(fallback, list) and not isinstance(payload, list):
        payload = fallback
    return payload


run_options = parse_json(run_options_json, {})
papers_payload = parse_json(papers_json, {})
web_payload = parse_json(web_json, {})
runtime_payload = parse_json(runtime_json, {})
repo_payload = parse_json(repo_json, {})
platform_payload = parse_json(platform_json, {})

papers = papers_payload.get("papers", []) if isinstance(papers_payload, dict) else []
web_signals = web_payload.get("web_signals", []) if isinstance(web_payload, dict) else []
runtime_counts = runtime_payload.get("counts", {}) if isinstance(runtime_payload, dict) else {}
repo_worktree = repo_payload.get("worktree", {}) if isinstance(repo_payload, dict) else {}


def to_int(value):
    try:
        return int(str(value).strip())
    except Exception:
        return 0

counts = {
    "papers": len(papers) if isinstance(papers, list) else 0,
    "web_signals": len(web_signals) if isinstance(web_signals, list) else 0,
    "failure_events": to_int(runtime_counts.get("failure_events", 0)),
    "quality_entries": to_int(runtime_counts.get("quality_entries", 0)),
    "proposal_items": to_int(runtime_counts.get("proposal_items", 0)),
    "repo_tracked_changes": to_int(repo_worktree.get("tracked_changes", 0)),
    "repo_untracked_changes": to_int(repo_worktree.get("untracked_changes", 0)),
}

bundle = {
    "objective": " ".join(str(run_options.get("objective", "")).split()).strip(),
    "sources": run_options.get("sources", {}) if isinstance(run_options, dict) else {},
    "papers": papers if isinstance(papers, list) else [],
    "web_signals": web_signals if isinstance(web_signals, list) else [],
    "runtime_signals": runtime_payload if isinstance(runtime_payload, dict) else {},
    "repo_signals": repo_payload if isinstance(repo_payload, dict) else {},
    "platform_signals": platform_payload if isinstance(platform_payload, dict) else {},
    "counts": counts,
}
print(json.dumps(bundle, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_generate_lane_report_json() {
  model_name=$1
  lane_name=$2
  objective_text=$3
  evidence_json=$4
  prompt=$(cat <<EOF
You are operating the "$lane_name" lane in a competitive self-improvement run for Artificer.

Goal:
$objective_text

Evidence package (JSON):
$evidence_json

You must propose 4 to 8 concrete, toggleable self-improvement plugins that make Artificer better at:
- web research
- knowledge integration
- planning
- architecture
- programming
- verification
- local admin/setup work needed to make improvements operational

Rules:
- Be operational and implementation-oriented. Avoid vague advice.
- Plugins must be safe to toggle on/off at runtime.
- Every plugin must include specific instructions plus an implementation plan.
- Include domain tags from: web-research, knowledge-integration, planning, architecture, programming, verification, admin-setup
- Include concise evidence references and any admin/setup actions needed.
- Return strict JSON only.

JSON schema:
{
  "summary": "one short paragraph",
  "strategy": "how this lane approached the problem",
  "plugins": [
    {
      "id": "short-kebab-id",
      "name": "Human readable name",
      "description": "what this changes",
      "instructions": "runtime guidance when enabled",
      "implementation_plan": "how Artificer should implement/use it",
      "rationale": "why this helps",
      "domain_tags": ["planning", "verification"],
      "evidence_refs": ["short evidence reference"],
      "admin_actions": ["concrete setup action if needed"],
      "risk_level": "low|medium|high"
    }
  ]
}
EOF
)
  export ARTIFICER_SKIP_SELF_IMPROVE_PLUGINS=1
  model_output=$(RUN_TIMEOUT_SEC=180 run_model "$model_name" "$prompt" 2>&1 || true)
  unset ARTIFICER_SKIP_SELF_IMPROVE_PLUGINS
  MODEL_OUTPUT=$model_output python3 - "$lane_name" "$model_name" <<'PY'
import json
import os
import re
import sys

lane_name = sys.argv[1]
model_name = sys.argv[2]
raw = os.environ.get("MODEL_OUTPUT", "")
candidates = []
fenced = re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.S | re.I)
candidates.extend(fenced)
candidates.append(raw)

decoder = json.JSONDecoder()
parsed = None
for candidate in candidates:
    text = candidate.strip()
    if not text:
        continue
    try:
        parsed = decoder.decode(text)
        break
    except Exception:
        for idx, ch in enumerate(text):
            if ch != "{":
                continue
            try:
                parsed, _ = decoder.raw_decode(text[idx:])
                break
            except Exception:
                continue
        if parsed is not None:
            break

allowed_domains = {
    "web-research",
    "knowledge-integration",
    "planning",
    "architecture",
    "programming",
    "verification",
    "admin-setup",
}
domain_aliases = {
    "research": "web-research",
    "web": "web-research",
    "knowledge": "knowledge-integration",
    "synthesis": "knowledge-integration",
    "plan": "planning",
    "architect": "architecture",
    "coding": "programming",
    "code": "programming",
    "verify": "verification",
    "test": "verification",
    "admin": "admin-setup",
    "setup": "admin-setup",
    "ops": "admin-setup",
}


def infer_domains(text):
    text_l = str(text).lower()
    found = []
    for token, mapped in domain_aliases.items():
        if token in text_l and mapped not in found:
            found.append(mapped)
    return found


if not isinstance(parsed, dict):
    print(
        json.dumps(
            {
                "lane": lane_name,
                "model": model_name,
                "summary": "",
                "strategy": "",
                "plugins": [],
                "error": "model did not return valid JSON",
                "raw": raw[:4000],
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    sys.exit(0)

summary = " ".join(str(parsed.get("summary", "")).split()).strip()
strategy = " ".join(str(parsed.get("strategy", "")).split()).strip()
plugins = parsed.get("plugins", [])
if not isinstance(plugins, list):
    plugins = []

clean = []
for index, item in enumerate(plugins[:8], 1):
    if not isinstance(item, dict):
        continue
    plugin_id = re.sub(r"[^a-z0-9-]+", "-", str(item.get("id", "")).strip().lower()).strip("-")
    if not plugin_id:
        plugin_id = f"{lane_name}-{index}"
    name = " ".join(str(item.get("name", "")).split()).strip()
    description = " ".join(str(item.get("description", "")).split()).strip()
    instructions = " ".join(str(item.get("instructions", "")).split()).strip()
    implementation_plan = " ".join(str(item.get("implementation_plan", "")).split()).strip()
    rationale = " ".join(str(item.get("rationale", "")).split()).strip()
    if not name:
        name = plugin_id
    if not instructions:
        continue

    raw_domains = item.get("domain_tags", [])
    domains = []
    if isinstance(raw_domains, list):
        for raw_domain in raw_domains:
            token = re.sub(r"[^a-z0-9-]+", "-", str(raw_domain).strip().lower()).strip("-")
            if not token:
                continue
            token = domain_aliases.get(token, token)
            if token in allowed_domains and token not in domains:
                domains.append(token)
    inferred = infer_domains(" ".join([name, description, instructions, implementation_plan, rationale]))
    for inferred_domain in inferred:
        if inferred_domain in allowed_domains and inferred_domain not in domains:
            domains.append(inferred_domain)
    domains = domains[:4]

    evidence_refs = item.get("evidence_refs", [])
    if not isinstance(evidence_refs, list):
        evidence_refs = []
    evidence_refs = [" ".join(str(ref).split()).strip() for ref in evidence_refs[:6] if str(ref).strip()]

    admin_actions = item.get("admin_actions", [])
    if not isinstance(admin_actions, list):
        admin_actions = []
    admin_actions = [" ".join(str(action).split()).strip() for action in admin_actions[:6] if str(action).strip()]

    risk_level = str(item.get("risk_level", "medium")).strip().lower()
    if risk_level not in {"low", "medium", "high"}:
        risk_level = "medium"

    clean.append(
        {
            "id": plugin_id,
            "name": name,
            "description": description,
            "instructions": instructions,
            "implementation_plan": implementation_plan,
            "rationale": rationale,
            "domain_tags": domains,
            "evidence_refs": evidence_refs,
            "admin_actions": admin_actions,
            "risk_level": risk_level,
            "source_lane": lane_name,
            "source_model": model_name,
        }
    )

print(
    json.dumps(
        {
            "lane": lane_name,
            "model": model_name,
            "summary": summary,
            "strategy": strategy,
            "plugins": clean,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
)
PY
}

self_improve_compare_reports_json() {
  objective_text=$1
  evidence_json=$2
  primary_report_json=$3
  challenger_report_json=$4
  primary_model=$5
  challenger_model=$6
  competition_enabled_value=$7
  python3 - "$objective_text" "$evidence_json" "$primary_report_json" "$challenger_report_json" "$primary_model" "$challenger_model" "$competition_enabled_value" <<'PY'
import json
import re
import sys

objective_text, evidence_json, primary_report_json, challenger_report_json, primary_model, challenger_model, competition_enabled_value = sys.argv[1:8]
competition_enabled = str(competition_enabled_value).strip().lower() in {"1", "true", "yes", "on", "enabled"}

target_domains = [
    "web-research",
    "knowledge-integration",
    "planning",
    "architecture",
    "programming",
    "verification",
    "admin-setup",
]
domain_aliases = {
    "research": "web-research",
    "web": "web-research",
    "knowledge": "knowledge-integration",
    "synthesis": "knowledge-integration",
    "plan": "planning",
    "architect": "architecture",
    "code": "programming",
    "program": "programming",
    "verify": "verification",
    "test": "verification",
    "admin": "admin-setup",
    "ops": "admin-setup",
    "setup": "admin-setup",
}


def parse_json(raw, fallback):
    try:
        payload = json.loads(raw) if raw else fallback
    except Exception:
        payload = fallback
    if isinstance(fallback, dict) and not isinstance(payload, dict):
        payload = fallback
    if isinstance(fallback, list) and not isinstance(payload, list):
        payload = fallback
    return payload


def infer_domains(text):
    text_l = str(text).lower()
    found = []
    for token, mapped in domain_aliases.items():
        if token in text_l and mapped not in found:
            found.append(mapped)
    return found


def normalize_report(raw_json, lane_name, model_name):
    parsed = parse_json(raw_json, {})
    plugins = parsed.get("plugins", []) if isinstance(parsed, dict) else []
    if not isinstance(plugins, list):
        plugins = []
    clean_plugins = []
    for index, plugin in enumerate(plugins[:10], 1):
        if not isinstance(plugin, dict):
            continue
        plugin_copy = dict(plugin)
        plugin_copy["id"] = re.sub(r"[^a-z0-9-]+", "-", str(plugin_copy.get("id", "")).strip().lower()).strip("-") or f"{lane_name}-{index}"
        plugin_copy["name"] = " ".join(str(plugin_copy.get("name", plugin_copy["id"])).split()).strip()
        plugin_copy["instructions"] = " ".join(str(plugin_copy.get("instructions", "")).split()).strip()
        if not plugin_copy["instructions"]:
            continue
        plugin_copy["implementation_plan"] = " ".join(str(plugin_copy.get("implementation_plan", "")).split()).strip()
        plugin_copy["rationale"] = " ".join(str(plugin_copy.get("rationale", "")).split()).strip()
        plugin_copy["description"] = " ".join(str(plugin_copy.get("description", "")).split()).strip()
        domains = plugin_copy.get("domain_tags", [])
        if not isinstance(domains, list):
            domains = []
        normalized_domains = []
        for domain in domains:
            token = re.sub(r"[^a-z0-9-]+", "-", str(domain).strip().lower()).strip("-")
            if token in target_domains and token not in normalized_domains:
                normalized_domains.append(token)
        if not normalized_domains:
            inferred = infer_domains(" ".join([plugin_copy["name"], plugin_copy["description"], plugin_copy["instructions"], plugin_copy["implementation_plan"], plugin_copy["rationale"]]))
            for inferred_domain in inferred:
                if inferred_domain in target_domains and inferred_domain not in normalized_domains:
                    normalized_domains.append(inferred_domain)
        plugin_copy["domain_tags"] = normalized_domains[:4]
        refs = plugin_copy.get("evidence_refs", [])
        if not isinstance(refs, list):
            refs = []
        plugin_copy["evidence_refs"] = [" ".join(str(ref).split()).strip() for ref in refs[:6] if str(ref).strip()]
        admin_actions = plugin_copy.get("admin_actions", [])
        if not isinstance(admin_actions, list):
            admin_actions = []
        plugin_copy["admin_actions"] = [" ".join(str(action).split()).strip() for action in admin_actions[:6] if str(action).strip()]
        risk_level = str(plugin_copy.get("risk_level", "medium")).strip().lower()
        if risk_level not in {"low", "medium", "high"}:
            risk_level = "medium"
        plugin_copy["risk_level"] = risk_level
        plugin_copy["source_lane"] = lane_name
        plugin_copy["source_model"] = model_name
        clean_plugins.append(plugin_copy)

    return {
        "lane": lane_name,
        "model": model_name,
        "summary": " ".join(str(parsed.get("summary", "")).split()).strip() if isinstance(parsed, dict) else "",
        "strategy": " ".join(str(parsed.get("strategy", "")).split()).strip() if isinstance(parsed, dict) else "",
        "error": " ".join(str(parsed.get("error", "")).split()).strip() if isinstance(parsed, dict) else "",
        "plugins": clean_plugins,
    }


def score_report(report):
    plugins = report.get("plugins", [])
    if not isinstance(plugins, list):
        plugins = []
    plugin_count = len(plugins)
    domain_coverage = []
    evidence_ref_count = 0
    admin_action_count = 0
    plan_count = 0
    rationale_count = 0
    risk_balance = {"low": 0, "medium": 0, "high": 0}
    fingerprints = set()
    duplicate_penalty = 0
    instruction_word_total = 0
    for plugin in plugins:
        domain_tags = plugin.get("domain_tags", [])
        if isinstance(domain_tags, list):
            for domain in domain_tags:
                if domain in target_domains and domain not in domain_coverage:
                    domain_coverage.append(domain)
        refs = plugin.get("evidence_refs", [])
        if isinstance(refs, list):
            evidence_ref_count += len(refs)
        admin_actions = plugin.get("admin_actions", [])
        if isinstance(admin_actions, list):
            admin_action_count += len(admin_actions)
        if str(plugin.get("implementation_plan", "")).strip():
            plan_count += 1
        if str(plugin.get("rationale", "")).strip():
            rationale_count += 1
        risk = str(plugin.get("risk_level", "medium")).strip().lower()
        if risk not in risk_balance:
            risk = "medium"
        risk_balance[risk] += 1
        instructions = str(plugin.get("instructions", ""))
        instruction_word_total += len(instructions.split())
        fingerprint = (str(plugin.get("name", "")).strip().lower(), instructions.strip().lower())
        if fingerprint in fingerprints:
            duplicate_penalty += 1
        else:
            fingerprints.add(fingerprint)

    coverage_score = (len(domain_coverage) / len(target_domains)) * 38.0
    plugin_count_score = min(plugin_count, 8) * 3.4
    evidence_score = min(18.0, evidence_ref_count * 1.5 + admin_action_count * 1.1)
    implementation_score = min(16.0, plan_count * 2.0 + rationale_count * 1.2)
    avg_instruction_words = (instruction_word_total / plugin_count) if plugin_count else 0.0
    instruction_quality = 0.0
    if avg_instruction_words >= 14:
        instruction_quality = min(10.0, avg_instruction_words / 2.0)
    risk_penalty = max(0, risk_balance["high"] - max(1, plugin_count // 3)) * 1.5
    duplicate_penalty_score = duplicate_penalty * 3.0

    total_score = coverage_score + plugin_count_score + evidence_score + implementation_score + instruction_quality
    total_score -= (risk_penalty + duplicate_penalty_score)
    if total_score < 0:
        total_score = 0.0
    if total_score > 100:
        total_score = 100.0

    return {
        "score": round(total_score, 2),
        "domain_coverage": sorted(domain_coverage),
        "plugin_count": plugin_count,
        "evidence_ref_count": evidence_ref_count,
        "admin_action_count": admin_action_count,
        "avg_instruction_words": round(avg_instruction_words, 2),
        "risk_balance": risk_balance,
        "has_error": bool(report.get("error")),
    }


primary = normalize_report(primary_report_json, "artificer", primary_model)
challenger = normalize_report(challenger_report_json, "challenger", challenger_model)
primary_score = score_report(primary)
challenger_score = score_report(challenger) if competition_enabled else {
    "score": 0.0,
    "domain_coverage": [],
    "plugin_count": 0,
    "evidence_ref_count": 0,
    "admin_action_count": 0,
    "avg_instruction_words": 0.0,
    "risk_balance": {"low": 0, "medium": 0, "high": 0},
    "has_error": False,
}

winner = primary
winner_score = primary_score
loser = challenger
loser_score = challenger_score
if competition_enabled and challenger_score["score"] > primary_score["score"]:
    winner = challenger
    winner_score = challenger_score
    loser = primary
    loser_score = primary_score

merged_plugins = []
seen = set()


def append_plugins(report, score_value):
    for plugin in report.get("plugins", []):
        fingerprint = (
            str(plugin.get("name", "")).strip().lower(),
            str(plugin.get("instructions", "")).strip().lower(),
        )
        if fingerprint in seen:
            continue
        seen.add(fingerprint)
        payload = dict(plugin)
        payload["competition_score"] = score_value
        merged_plugins.append(payload)
        if len(merged_plugins) >= 8:
            return


append_plugins(winner, winner_score["score"])
if len(merged_plugins) < 8:
    append_plugins(loser, loser_score["score"])

objective_text = " ".join(str(objective_text).split()).strip()
if not objective_text:
    objective_text = "Improve Artificer self-improvement quality."

winner_lane = winner.get("lane", "artificer")
winner_model = winner.get("model", primary_model)
winner_domains = ", ".join(winner_score["domain_coverage"]) if winner_score["domain_coverage"] else "none"
opponent_score = challenger_score["score"] if winner_lane == "artificer" else primary_score["score"]
summary = (
    f"{winner_lane} lane won ({winner_score['score']:.2f} vs {opponent_score:.2f}). "
    f"Objective: {objective_text}. Covered domains: {winner_domains}. "
    f"Merged plugins: {len(merged_plugins)}."
)
summary = " ".join(summary.split())

try:
    evidence = json.loads(evidence_json) if evidence_json else {}
except Exception:
    evidence = {}
if not isinstance(evidence, dict):
    evidence = {}
counts = evidence.get("counts", {})
if not isinstance(counts, dict):
    counts = {}

result = {
    "summary": summary,
    "winner_lane": winner_lane,
    "winner_model": winner_model,
    "competition_enabled": competition_enabled,
    "lane_scores": {
        "artificer": primary_score["score"],
        "challenger": challenger_score["score"],
    },
    "lanes": [
        {
            "lane": primary.get("lane", "artificer"),
            "model": primary.get("model", primary_model),
            "summary": primary.get("summary", ""),
            "strategy": primary.get("strategy", ""),
            "error": primary.get("error", ""),
            "score": primary_score,
        },
        {
            "lane": challenger.get("lane", "challenger"),
            "model": challenger.get("model", challenger_model),
            "summary": challenger.get("summary", ""),
            "strategy": challenger.get("strategy", ""),
            "error": challenger.get("error", ""),
            "score": challenger_score,
        },
    ],
    "plugins": merged_plugins,
    "objective": objective_text,
    "evidence_counts": counts,
}
print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_store_report_and_plugins() {
  model_name=$1
  run_options_json=$2
  evidence_json=$3
  report_json=$4
  python3 - "$self_improve_plugins_dir" "$self_improve_last_run_file" "$model_name" "$run_options_json" "$evidence_json" "$report_json" <<'PY'
import datetime as dt
import json
import os
import re
import sys

plugins_dir, report_path, model_name, run_options_json, evidence_json, report_json = sys.argv[1:7]
os.makedirs(plugins_dir, exist_ok=True)


def parse_json(raw, fallback):
    try:
        payload = json.loads(raw) if raw else fallback
    except Exception:
        payload = fallback
    if isinstance(fallback, dict) and not isinstance(payload, dict):
        payload = fallback
    if isinstance(fallback, list) and not isinstance(payload, list):
        payload = fallback
    return payload


run_options = parse_json(run_options_json, {})
evidence = parse_json(evidence_json, {})
report = parse_json(report_json, {})

objective = " ".join(str(run_options.get("objective", "")).split()).strip()
competition_enabled = bool(run_options.get("competition_enabled", True))

papers = evidence.get("papers", []) if isinstance(evidence, dict) else []
if not isinstance(papers, list):
    papers = []
web_signals = evidence.get("web_signals", []) if isinstance(evidence, dict) else []
if not isinstance(web_signals, list):
    web_signals = []
evidence_counts = evidence.get("counts", {}) if isinstance(evidence, dict) else {}
if not isinstance(evidence_counts, dict):
    evidence_counts = {}

plugins = report.get("plugins", []) if isinstance(report, dict) else []
if not isinstance(plugins, list):
    plugins = []
summary = " ".join(str(report.get("summary", "")).split()).strip() if isinstance(report, dict) else ""
winner_lane = " ".join(str(report.get("winner_lane", "")).split()).strip() if isinstance(report, dict) else ""
winner_model = " ".join(str(report.get("winner_model", "")).split()).strip() if isinstance(report, dict) else ""
lane_scores = report.get("lane_scores", {}) if isinstance(report, dict) else {}
if not isinstance(lane_scores, dict):
    lane_scores = {}
lanes = report.get("lanes", []) if isinstance(report, dict) else []
if not isinstance(lanes, list):
    lanes = []

generated_at = dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
saved_ids = []
for index, plugin in enumerate(plugins, 1):
    if not isinstance(plugin, dict):
        continue
    base_id = str(plugin.get("id", "")).strip().lower()
    if not base_id:
        base_id = str(plugin.get("name", "")).strip().lower()
    base_id = re.sub(r"[^a-z0-9-]+", "-", base_id).strip("-")
    if not base_id:
        base_id = f"plugin-{index}"
    final_id = f"{generated_at[:10]}-{base_id}"
    suffix = 2
    while os.path.exists(os.path.join(plugins_dir, final_id + ".json")):
        final_id = f"{generated_at[:10]}-{base_id}-{suffix}"
        suffix += 1

    payload = dict(plugin)
    payload["id"] = final_id
    payload["enabled"] = True
    payload["generated_at"] = generated_at
    payload["source_model"] = str(payload.get("source_model", "")).strip() or model_name
    payload["source_lane"] = str(payload.get("source_lane", "")).strip()
    payload["risk_level"] = str(payload.get("risk_level", "medium")).strip().lower() or "medium"
    if payload["risk_level"] not in {"low", "medium", "high"}:
        payload["risk_level"] = "medium"
    domain_tags = payload.get("domain_tags", [])
    if not isinstance(domain_tags, list):
        domain_tags = []
    payload["domain_tags"] = [" ".join(str(tag).split()).strip() for tag in domain_tags[:6] if str(tag).strip()]
    evidence_refs = payload.get("evidence_refs", [])
    if not isinstance(evidence_refs, list):
        evidence_refs = []
    payload["evidence_refs"] = [" ".join(str(ref).split()).strip() for ref in evidence_refs[:8] if str(ref).strip()]
    admin_actions = payload.get("admin_actions", [])
    if not isinstance(admin_actions, list):
        admin_actions = []
    payload["admin_actions"] = [" ".join(str(action).split()).strip() for action in admin_actions[:8] if str(action).strip()]
    payload["objective"] = objective
    payload["papers"] = papers
    payload["web_signals"] = web_signals
    payload["evidence_counts"] = evidence_counts

    with open(os.path.join(plugins_dir, final_id + ".json"), "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
    saved_ids.append(final_id)

last_run = {
    "summary": summary,
    "generated_at": generated_at,
    "model": model_name,
    "papers": papers,
    "web_signals": web_signals,
    "objective": objective,
    "competition_enabled": competition_enabled,
    "winner_lane": winner_lane,
    "winner_model": winner_model or model_name,
    "lane_scores": lane_scores,
    "lanes": lanes,
    "evidence_counts": evidence_counts,
    "run_options": run_options,
    "plugin_ids": saved_ids,
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(last_run, handle, ensure_ascii=False, indent=2)
print(json.dumps(last_run, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_plugin_set_enabled_json() {
  plugin_id=$1
  enabled_value=$2
  python3 - "$self_improve_plugins_dir" "$plugin_id" "$enabled_value" <<'PY'
import json
import os
import sys

plugins_dir, plugin_id, enabled_value = sys.argv[1:4]
path = os.path.join(plugins_dir, plugin_id + ".json")
if not os.path.isfile(path):
    print(json.dumps({"success": False, "error": "plugin not found"}))
    sys.exit(0)
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
payload["enabled"] = str(enabled_value).strip() in {"1", "true", "True", "TRUE", "yes", "on"}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
print(json.dumps({"success": True, "plugin": payload}, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_plugin_delete_json() {
  plugin_id=$1
  target_file="$self_improve_plugins_dir/$plugin_id.json"
  if [ ! -f "$target_file" ]; then
    printf '{"success":false,"error":"plugin not found"}\n'
    return 0
  fi
  rm -f "$target_file"
  printf '{"success":true,"deleted_id":"%s"}\n' "$(json_escape "$plugin_id")"
}

active_self_improve_plugin_guidance() {
  if [ "${ARTIFICER_SKIP_SELF_IMPROVE_PLUGINS:-0}" = "1" ]; then
    return 0
  fi
  python3 - "$self_improve_plugins_dir" <<'PY'
import json
import os
import sys

plugins_dir = sys.argv[1]
lines = []
if os.path.isdir(plugins_dir):
    for name in sorted(os.listdir(plugins_dir)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(plugins_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            continue
        if not isinstance(payload, dict) or not payload.get("enabled", True):
            continue
        title = " ".join(str(payload.get("name", payload.get("id", ""))).split()).strip()
        instructions = " ".join(str(payload.get("instructions", "")).split()).strip()
        if title and instructions:
            lines.append(f"- {title}: {instructions}")
for line in lines[:8]:
    print(line)
PY
}

