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
adoption_rank = {"adopted": 0, "trial": 1, "review": 2, "rejected": 3}
promotion_rank = {"priority": 0, "candidate": 1, "hold": 2}
operator_policy_set = {
    "auto",
    "force-adopted",
    "force-trial",
    "force-review",
    "force-rejected",
}


def safe_number(value):
    try:
        return float(value or 0)
    except Exception:
        return 0.0


def normalize_adoption_state(payload):
    adoption_state = str(payload.get("adoption_state", "")).strip().lower()
    if adoption_state in adoption_rank:
        return adoption_state
    if bool(payload.get("enabled", False)):
        return "trial"
    promotion_state = str(payload.get("promotion_state", "candidate")).strip().lower()
    if promotion_state == "hold":
        return "rejected"
    if payload.get("benchmark_family_targets"):
        return "review"
    return "rejected"


def normalize_operator_policy(value):
    policy = str(value or "").strip().lower()
    if policy in operator_policy_set:
        return policy
    return "auto"


def operator_policy_target(policy):
    mapping = {
        "force-adopted": "adopted",
        "force-trial": "trial",
        "force-review": "review",
        "force-rejected": "rejected",
    }
    return mapping.get(normalize_operator_policy(policy), "")


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
        payload.setdefault("benchmark_family_targets", [])
        payload.setdefault("targeted_capability_gaps", [])
        payload.setdefault("targeted_external_capability_gaps", [])
        payload.setdefault("targeted_persistent_external_capability_gaps", [])
        payload.setdefault("benchmark_alignment_score", 0.0)
        promotion_state = str(payload.get("promotion_state", "candidate")).strip().lower()
        if promotion_state not in promotion_rank:
            promotion_state = "candidate"
        payload["promotion_state"] = promotion_state
        payload.setdefault("promotion_reason", "")
        payload.setdefault("benchmark_compare_recommendation", "")
        payload["benchmark_candidate_promotable"] = bool(payload.get("benchmark_candidate_promotable", False))
        payload.setdefault("benchmark_recovered_family_hits", [])
        payload.setdefault("benchmark_improved_family_hits", [])
        payload.setdefault("benchmark_new_weak_family_hits", [])
        payload.setdefault("automatic_adoption_state", "")
        payload.setdefault("automatic_adoption_reason", "")
        payload["benchmark_compare_count"] = int(payload.get("benchmark_compare_count", 0) or 0)
        payload["benchmark_promotable_hit_count"] = int(payload.get("benchmark_promotable_hit_count", 0) or 0)
        payload["benchmark_hold_count"] = int(payload.get("benchmark_hold_count", 0) or 0)
        payload["benchmark_success_streak"] = int(payload.get("benchmark_success_streak", 0) or 0)
        payload["benchmark_hold_streak"] = int(payload.get("benchmark_hold_streak", 0) or 0)
        payload["last_benchmark_compare_count"] = int(payload.get("last_benchmark_compare_count", 0) or 0)
        payload["stale_compare_cycles"] = int(payload.get("stale_compare_cycles", 0) or 0)
        payload.setdefault("lineage_key", "")
        payload["operator_policy"] = normalize_operator_policy(payload.get("operator_policy", "auto"))
        payload["operator_lock"] = bool(payload.get("operator_lock", False)) and payload["operator_policy"] != "auto"
        payload.setdefault("operator_updated_at", "")
        payload["adoption_state"] = normalize_adoption_state(payload)
        payload.setdefault("adoption_reason", "")
        items.append(payload)
items.sort(
    key=lambda payload: (
        adoption_rank.get(payload.get("adoption_state", "review"), 4),
        -safe_number(payload.get("benchmark_success_streak", 0)),
        promotion_rank.get(payload.get("promotion_state", "candidate"), 3),
        -safe_number(payload.get("benchmark_alignment_score", 0)),
        -safe_number(payload.get("competition_score", 0)),
        str(payload.get("name", payload.get("id", ""))).strip().lower(),
    )
)
print(json.dumps(items, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_plugin_inventory_json() {
  python3 - "$self_improve_plugins_dir" <<'PY'
import json
import os
import sys

plugins_dir = sys.argv[1]
archive_dir = os.path.join(plugins_dir, "archive")
inventory = {
    "active_count": 0,
    "archived_count": 0,
    "archived_auto_stale_count": 0,
}

if os.path.isdir(plugins_dir):
    for name in os.listdir(plugins_dir):
        if name.endswith(".json"):
            inventory["active_count"] += 1

if os.path.isdir(archive_dir):
    for name in os.listdir(archive_dir):
        if not name.endswith(".json"):
            continue
        inventory["archived_count"] += 1
        path = os.path.join(archive_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            payload = {}
        if str(payload.get("archived_via", "")).strip() == "stale-benchmark-prune":
            inventory["archived_auto_stale_count"] += 1

print(json.dumps(inventory, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_archived_plugins_json() {
  python3 - "$self_improve_plugins_dir" <<'PY'
import json
import os
import sys

plugins_dir = sys.argv[1]
archive_dir = os.path.join(plugins_dir, "archive")
items = []

if os.path.isdir(archive_dir):
    for name in sorted(os.listdir(archive_dir)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(archive_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            continue
        if not isinstance(payload, dict):
            continue
        archive_entry_id = os.path.splitext(name)[0]
        item = {
            "archive_entry_id": archive_entry_id,
            "id": " ".join(str(payload.get("id", archive_entry_id)).split()).strip() or archive_entry_id,
            "name": " ".join(str(payload.get("name", payload.get("id", archive_entry_id))).split()).strip() or archive_entry_id,
            "description": " ".join(str(payload.get("description", "")).split()).strip(),
            "rationale": " ".join(str(payload.get("rationale", "")).split()).strip(),
            "instructions": " ".join(str(payload.get("instructions", "")).split()).strip(),
            "implementation_plan": " ".join(str(payload.get("implementation_plan", "")).split()).strip(),
            "source_model": " ".join(str(payload.get("source_model", "")).split()).strip(),
            "source_lane": " ".join(str(payload.get("source_lane", "")).split()).strip(),
            "risk_level": " ".join(str(payload.get("risk_level", "medium")).split()).strip() or "medium",
            "lineage_key": " ".join(str(payload.get("lineage_key", "")).split()).strip(),
            "benchmark_family_targets": payload.get("benchmark_family_targets", []) if isinstance(payload.get("benchmark_family_targets", []), list) else [],
            "targeted_capability_gaps": payload.get("targeted_capability_gaps", []) if isinstance(payload.get("targeted_capability_gaps", []), list) else [],
            "targeted_external_capability_gaps": payload.get("targeted_external_capability_gaps", []) if isinstance(payload.get("targeted_external_capability_gaps", []), list) else [],
            "targeted_persistent_external_capability_gaps": payload.get("targeted_persistent_external_capability_gaps", []) if isinstance(payload.get("targeted_persistent_external_capability_gaps", []), list) else [],
            "archived_at": " ".join(str(payload.get("archived_at", "")).split()).strip(),
            "archived_via": " ".join(str(payload.get("archived_via", "")).split()).strip(),
            "archived_reason": " ".join(str(payload.get("archived_reason", "")).split()).strip(),
            "archived_from_state": " ".join(str(payload.get("archived_from_state", payload.get("adoption_state", ""))).split()).strip().lower(),
            "archived_after_compare_cycles": int(payload.get("archived_after_compare_cycles", 0) or 0),
        }
        items.append(item)

items.sort(
    key=lambda item: (
        item.get("archived_at", ""),
        item.get("name", "").lower(),
    ),
    reverse=True,
)
print(json.dumps(items, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_last_run_json() {
  if [ ! -f "$self_improve_last_run_file" ]; then
    printf '{"summary":"","generated_at":"","model":"","papers":[],"web_signals":[],"objective":"","competition_enabled":false,"winner_lane":"","winner_model":"","lane_scores":{},"evidence_counts":{},"run_options":{},"lanes":[],"plugin_ids":[],"capability_benchmark":{"latest_recommendation":"","compare_recommendation":"","candidate_promotable":false,"weak_family_ids":[],"recovered_families":[],"new_weak_families":[],"scorecard_count":0,"compare_count":0,"external_compare_count":0,"external_compare_recommendation":"","candidate_beats_external":false,"external_gap_family_ids":[],"persistent_external_gap_family_ids":[],"external_baseline_name":"","external_adapter_count":0,"external_adapters":[]}}'
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
payload.setdefault("archived_plugin_ids", [])
payload.setdefault("objective", "")
payload.setdefault("competition_enabled", False)
payload.setdefault("winner_lane", "")
payload.setdefault("winner_model", "")
payload.setdefault("lane_scores", {})
payload.setdefault("evidence_counts", {})
payload.setdefault("run_options", {})
payload.setdefault("lanes", [])
payload.setdefault("capability_benchmark", {})
if not isinstance(payload["capability_benchmark"], dict):
    payload["capability_benchmark"] = {}
payload["capability_benchmark"].setdefault("latest_recommendation", "")
payload["capability_benchmark"].setdefault("compare_recommendation", "")
payload["capability_benchmark"].setdefault("candidate_promotable", False)
payload["capability_benchmark"].setdefault("weak_family_ids", [])
payload["capability_benchmark"].setdefault("recovered_families", [])
payload["capability_benchmark"].setdefault("new_weak_families", [])
payload["capability_benchmark"].setdefault("scorecard_count", 0)
payload["capability_benchmark"].setdefault("compare_count", 0)
payload["capability_benchmark"].setdefault("external_compare_count", 0)
payload["capability_benchmark"].setdefault("external_compare_recommendation", "")
payload["capability_benchmark"].setdefault("candidate_beats_external", False)
payload["capability_benchmark"].setdefault("external_gap_family_ids", [])
payload["capability_benchmark"].setdefault("persistent_external_gap_family_ids", [])
payload["capability_benchmark"].setdefault("external_baseline_name", "")
payload["capability_benchmark"].setdefault("external_adapter_count", 0)
payload["capability_benchmark"].setdefault("external_adapters", [])
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_settings_json() {
  selected_model=$(self_improve_selected_model)
  plugins_json=$(self_improve_plugins_json)
  archived_plugins_json=$(self_improve_archived_plugins_json)
  plugin_inventory_json=$(self_improve_plugin_inventory_json)
  last_run_json=$(self_improve_last_run_json)
  run_options_json=$(self_improve_run_options_json)
  printf '{"success":true,"selected_model":"%s","run_options":%s,"plugins":%s,"archived_plugins":%s,"plugin_inventory":%s,"last_run":%s}\n' \
    "$(json_escape "$selected_model")" \
    "$run_options_json" \
    "$plugins_json" \
    "$archived_plugins_json" \
    "$plugin_inventory_json" \
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
  capability_benchmark_json='{"manifest_path":"","family_count":0,"scorecard_count":0,"compare_count":0,"external_compare_count":0,"latest_scorecard":{},"latest_compare":{},"latest_external_compare":{},"high_leverage_gaps":[],"external_gap_families":[],"persistent_external_gaps":[],"external_registry_path":"","external_adapter_count":0,"external_adapters":[]}'

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

  capability_benchmark_json=$(self_improve_capability_benchmark_summary_json)

  RUNTIME_CONTROLLER_JSON=$controller_json RUNTIME_BENCHMARK_JSON=$capability_benchmark_json python3 - "$mode_runtime_root" "$failure_summary" "$quality_summary" "$proposal_summary" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
failure_summary = " ".join(str(sys.argv[2]).split()).strip() or "none"
quality_summary = " ".join(str(sys.argv[3]).split()).strip() or "none"
proposal_summary = " ".join(str(sys.argv[4]).split()).strip() or "none"
controller_raw = os.environ.get("RUNTIME_CONTROLLER_JSON", "{}")
benchmark_raw = os.environ.get("RUNTIME_BENCHMARK_JSON", "{}")


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

try:
    benchmark_state = json.loads(benchmark_raw)
    if not isinstance(benchmark_state, dict):
        benchmark_state = {}
except Exception:
    benchmark_state = {}

benchmark_scorecard_count = 0
benchmark_compare_count = 0
benchmark_external_compare_count = 0
try:
    benchmark_scorecard_count = int(benchmark_state.get("scorecard_count", 0))
except Exception:
    benchmark_scorecard_count = 0
try:
    benchmark_compare_count = int(benchmark_state.get("compare_count", 0))
except Exception:
    benchmark_compare_count = 0
try:
    benchmark_external_compare_count = int(benchmark_state.get("external_compare_count", 0))
except Exception:
    benchmark_external_compare_count = 0

payload = {
    "failure_summary": failure_summary,
    "quality_summary": quality_summary,
    "proposal_summary": proposal_summary,
    "controller_variants": controller_state,
    "capability_benchmark": benchmark_state,
    "counts": {
        "failure_events": failure_events,
        "quality_entries": quality_entries,
        "proposal_items": proposal_count,
        "capability_benchmark_scorecards": benchmark_scorecard_count,
        "capability_benchmark_compares": benchmark_compare_count,
        "capability_benchmark_external_compares": benchmark_external_compare_count,
    },
}
print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_capability_benchmark_summary_json() {
  manifest_path="$ARTIFICER_SCRIPT_DIR/../tests/fixtures/artificer-capability-benchmark-manifest-v1.tsv"
  external_registry_path="$ARTIFICER_SCRIPT_DIR/../tests/fixtures/artificer-capability-external-adapters-v1.tsv"
  python3 - "$ARTIFICER_ASSAY_REPORTS_DIR" "$manifest_path" "$external_registry_path" <<'PY'
import csv
import json
import pathlib
import sys

reports_dir = pathlib.Path(sys.argv[1]).expanduser()
manifest_path = pathlib.Path(sys.argv[2]).expanduser()
external_registry_path = pathlib.Path(sys.argv[3]).expanduser()


def parse_json(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except Exception:
        payload = {}
    return payload if isinstance(payload, dict) else {}


def latest(paths):
    if not paths:
        return None
    return max(paths, key=lambda item: (item.stat().st_mtime, item.name))


def load_external_adapters(path):
    adapters = []
    if not path.is_file():
        return adapters
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            if not row:
                continue
            adapter_id = str(row.get("adapter_id", "")).strip()
            if not adapter_id or adapter_id.startswith("#"):
                continue
            adapters.append(
                {
                    "adapter_id": adapter_id,
                    "name": " ".join(str(row.get("name", adapter_id)).split()).strip() or adapter_id,
                    "kind": " ".join(str(row.get("kind", "")).split()).strip(),
                    "model": " ".join(str(row.get("model", "")).split()).strip(),
                    "notes": " ".join(str(row.get("notes", "")).split()).strip(),
                }
            )
    return adapters


scorecard_paths = []
compare_paths = []
external_compare_paths = []
if reports_dir.is_dir():
    scorecard_paths = sorted(reports_dir.glob("*-capability-benchmark-scorecard.json"))
    compare_paths = sorted(reports_dir.glob("*-capability-benchmark-compare.json"))
    external_compare_paths = sorted(reports_dir.glob("*-capability-benchmark-external-compare.json"))

latest_scorecard_path = latest(scorecard_paths)
latest_compare_path = latest(compare_paths)
latest_external_compare_path = latest(external_compare_paths)
latest_scorecard = parse_json(latest_scorecard_path) if latest_scorecard_path else {}
latest_compare = parse_json(latest_compare_path) if latest_compare_path else {}
latest_external_compare = parse_json(latest_external_compare_path) if latest_external_compare_path else {}

high_leverage_gaps = []
external_gap_families = []
persistent_external_gaps = []
weak_families = latest_scorecard.get("weak_families", []) if isinstance(latest_scorecard, dict) else []
if isinstance(weak_families, list):
    for item in weak_families[:4]:
        if not isinstance(item, dict):
            continue
        high_leverage_gaps.append(
            {
                "id": str(item.get("id", "")).strip(),
                "score": item.get("score", 0),
                "critical": bool(item.get("critical", False)),
                "reason": str(item.get("reason", "")).strip(),
            }
        )

candidate_gap_families = latest_external_compare.get("candidate_gap_families", []) if isinstance(latest_external_compare, dict) else []
if isinstance(candidate_gap_families, list):
    for item in candidate_gap_families[:4]:
        if not isinstance(item, dict):
            continue
        external_gap_families.append(
            {
                "id": str(item.get("id", "")).strip(),
                "score_delta": item.get("score_delta", 0),
                "candidate_score": item.get("candidate_score", 0),
                "external_score": item.get("external_score", 0),
                "critical": bool(item.get("candidate_critical", False)),
                "reason": "external-baseline-ahead",
            }
        )

gap_history = {}
if external_compare_paths:
    recent_external_compare_paths = sorted(
        external_compare_paths,
        key=lambda item: (item.stat().st_mtime, item.name),
        reverse=True,
    )[:6]
    for compare_path in recent_external_compare_paths:
        payload = parse_json(compare_path)
        candidate_gap_items = payload.get("candidate_gap_families", []) if isinstance(payload, dict) else []
        if not isinstance(candidate_gap_items, list):
            continue
        for item in candidate_gap_items:
            if not isinstance(item, dict):
                continue
            family_id = str(item.get("id", "")).strip()
            if not family_id:
                continue
            existing = gap_history.get(
                family_id,
                {
                    "id": family_id,
                    "occurrence_count": 0,
                    "critical": False,
                    "score_delta_total": 0.0,
                    "latest_score_delta": 0.0,
                },
            )
            existing["occurrence_count"] += 1
            existing["critical"] = bool(existing.get("critical", False) or item.get("candidate_critical", False))
            try:
                score_delta = float(item.get("score_delta", 0) or 0)
            except Exception:
                score_delta = 0.0
            existing["score_delta_total"] += score_delta
            if existing["occurrence_count"] == 1:
                existing["latest_score_delta"] = score_delta
            gap_history[family_id] = existing

for family_id, item in gap_history.items():
    occurrence_count = int(item.get("occurrence_count", 0) or 0)
    if occurrence_count <= 0:
        continue
    avg_score_delta = round(float(item.get("score_delta_total", 0.0) or 0.0) / occurrence_count, 2)
    persistent_external_gaps.append(
        {
            "id": family_id,
            "occurrence_count": occurrence_count,
            "critical": bool(item.get("critical", False)),
            "avg_score_delta": avg_score_delta,
            "latest_score_delta": round(float(item.get("latest_score_delta", 0.0) or 0.0), 2),
            "reason": "persistent-external-baseline-gap",
        }
    )

persistent_external_gaps.sort(
    key=lambda item: (
        -int(item.get("occurrence_count", 0) or 0),
        not item.get("critical", False),
        float(item.get("avg_score_delta", 0) or 0),
        item.get("id", ""),
    )
)
persistent_external_gaps = persistent_external_gaps[:4]

payload = {
    "manifest_path": str(manifest_path) if manifest_path.is_file() else "",
    "family_count": int(latest_scorecard.get("family_count", 0) or 0) if isinstance(latest_scorecard, dict) else 0,
    "scorecard_count": len(scorecard_paths),
    "compare_count": len(compare_paths),
    "external_compare_count": len(external_compare_paths),
    "latest_scorecard": latest_scorecard,
    "latest_compare": latest_compare,
    "latest_external_compare": latest_external_compare,
    "high_leverage_gaps": high_leverage_gaps,
    "external_gap_families": external_gap_families,
    "persistent_external_gaps": persistent_external_gaps,
    "external_registry_path": str(external_registry_path) if external_registry_path.is_file() else "",
    "external_adapters": load_external_adapters(external_registry_path)[:8],
}
payload["external_adapter_count"] = len(payload["external_adapters"])
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
  runtime_json='{"failure_summary":"none","quality_summary":"none","proposal_summary":"none","controller_variants":{},"capability_benchmark":{"manifest_path":"","family_count":0,"scorecard_count":0,"compare_count":0,"external_compare_count":0,"latest_scorecard":{},"latest_compare":{},"latest_external_compare":{},"high_leverage_gaps":[],"external_gap_families":[],"persistent_external_gaps":[],"external_registry_path":"","external_adapter_count":0,"external_adapters":[]},"counts":{"failure_events":0,"quality_entries":0,"proposal_items":0,"capability_benchmark_scorecards":0,"capability_benchmark_compares":0,"capability_benchmark_external_compares":0}}'
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
    "capability_benchmark_scorecards": to_int(runtime_counts.get("capability_benchmark_scorecards", 0)),
    "capability_benchmark_compares": to_int(runtime_counts.get("capability_benchmark_compares", 0)),
    "capability_benchmark_external_compares": to_int(runtime_counts.get("capability_benchmark_external_compares", 0)),
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
- Include benchmark_family_targets from: research_integration, planning_architecture, coding_mutation, review_document, teaching_reassessment, admin_env_repair when you can identify which benchmark family the plugin is meant to improve.
- Include concise evidence references and any admin/setup actions needed.
- If runtime_signals.capability_benchmark is present, prioritize weak critical families and propose changes that can be measured against those benchmark families.
- If runtime_signals.capability_benchmark.external_gap_families is present, also prioritize families where an external baseline still outperforms Artificer.
- If runtime_signals.capability_benchmark.persistent_external_gaps is present, treat those recurring external deficits as especially high-leverage targets.
- If runtime_signals.capability_benchmark.external_adapters is present, prefer improvements that can be checked directly against those named external adapters.
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
      "benchmark_family_targets": ["coding_mutation"],
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

    benchmark_family_targets = item.get("benchmark_family_targets", [])
    if not isinstance(benchmark_family_targets, list):
        benchmark_family_targets = []
    clean_targets = []
    for target in benchmark_family_targets:
        token = re.sub(r"[^a-z0-9-]+", "_", str(target).strip().lower()).strip("_")
        if not token:
            continue
        if token in {"research", "research_integration", "knowledge_integration"}:
            token = "research_integration"
        elif token in {"planning", "planning_architecture", "architecture"}:
            token = "planning_architecture"
        elif token in {"coding", "coding_mutation", "programming"}:
            token = "coding_mutation"
        elif token in {"review", "review_document", "document"}:
            token = "review_document"
        elif token in {"teaching", "teaching_reassessment", "reassessment"}:
            token = "teaching_reassessment"
        elif token in {"admin", "admin_env_repair", "env_repair"}:
            token = "admin_env_repair"
        if token not in {"research_integration", "planning_architecture", "coding_mutation", "review_document", "teaching_reassessment", "admin_env_repair"}:
            continue
        if token not in clean_targets:
            clean_targets.append(token)

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
            "benchmark_family_targets": clean_targets[:4],
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
benchmark_family_ids = [
    "research_integration",
    "planning_architecture",
    "coding_mutation",
    "review_document",
    "teaching_reassessment",
    "admin_env_repair",
]
doc_review_keywords = ["document", "review", "runbook", "postmortem", "rewrite", "edit", "guide", "report"]
teaching_keywords = ["teach", "teaching", "mentor", "mentoring", "curriculum", "explain", "reassess", "reassessment", "long-context"]


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


def normalize_benchmark_family_id(value):
    token = re.sub(r"[^a-z0-9-]+", "_", str(value).strip().lower()).strip("_")
    if token in {"research", "research_integration", "knowledge_integration"}:
        return "research_integration"
    if token in {"planning", "planning_architecture", "architecture"}:
        return "planning_architecture"
    if token in {"coding", "coding_mutation", "programming"}:
        return "coding_mutation"
    if token in {"review", "review_document", "document"}:
        return "review_document"
    if token in {"teaching", "teaching_reassessment", "reassessment"}:
        return "teaching_reassessment"
    if token in {"admin", "admin_env_repair", "env_repair"}:
        return "admin_env_repair"
    return ""


evidence = parse_json(evidence_json, {})
runtime_signals = evidence.get("runtime_signals", {}) if isinstance(evidence, dict) else {}
if not isinstance(runtime_signals, dict):
    runtime_signals = {}
capability_benchmark = runtime_signals.get("capability_benchmark", {})
if not isinstance(capability_benchmark, dict):
    capability_benchmark = {}
latest_scorecard = capability_benchmark.get("latest_scorecard", {})
if not isinstance(latest_scorecard, dict):
    latest_scorecard = {}
weak_family_map = {}
for source_items in [capability_benchmark.get("high_leverage_gaps", []), latest_scorecard.get("weak_families", [])]:
    if not isinstance(source_items, list):
        continue
    for item in source_items:
        if not isinstance(item, dict):
            continue
        family_id = normalize_benchmark_family_id(item.get("id", ""))
        if not family_id:
            continue
        existing = weak_family_map.get(family_id, {"id": family_id, "critical": False, "reason": "", "score": 0})
        existing["critical"] = bool(existing.get("critical", False) or item.get("critical", False))
        reason_text = " ".join(str(item.get("reason", "")).split()).strip()
        if reason_text:
            existing["reason"] = reason_text
        try:
            score_value = float(item.get("score", existing.get("score", 0)) or 0)
        except Exception:
            score_value = float(existing.get("score", 0) or 0)
        existing["score"] = score_value
        weak_family_map[family_id] = existing
weak_family_ids = sorted(weak_family_map.keys())
latest_external_compare = capability_benchmark.get("latest_external_compare", {})
if not isinstance(latest_external_compare, dict):
    latest_external_compare = {}
external_gap_map = {}
for source_items in [capability_benchmark.get("external_gap_families", []), latest_external_compare.get("candidate_gap_families", [])]:
    if not isinstance(source_items, list):
        continue
    for item in source_items:
        if not isinstance(item, dict):
            continue
        family_id = normalize_benchmark_family_id(item.get("id", ""))
        if not family_id:
            continue
        existing = external_gap_map.get(family_id, {"id": family_id, "critical": False, "score_delta": 0.0, "reason": "external-baseline-ahead"})
        existing["critical"] = bool(existing.get("critical", False) or item.get("critical", False) or item.get("candidate_critical", False))
        reason_text = " ".join(str(item.get("reason", "")).split()).strip() or "external-baseline-ahead"
        existing["reason"] = reason_text
        try:
            delta_value = float(item.get("score_delta", existing.get("score_delta", 0)) or 0)
        except Exception:
            delta_value = float(existing.get("score_delta", 0) or 0)
        existing["score_delta"] = delta_value
        external_gap_map[family_id] = existing
external_gap_ids = sorted(external_gap_map.keys())
persistent_external_gap_map = {}
for source_items in [capability_benchmark.get("persistent_external_gaps", [])]:
    if not isinstance(source_items, list):
        continue
    for item in source_items:
        if not isinstance(item, dict):
            continue
        family_id = normalize_benchmark_family_id(item.get("id", ""))
        if not family_id:
            continue
        existing = persistent_external_gap_map.get(
            family_id,
            {
                "id": family_id,
                "critical": False,
                "occurrence_count": 0,
                "avg_score_delta": 0.0,
                "latest_score_delta": 0.0,
                "reason": "persistent-external-baseline-gap",
            },
        )
        existing["critical"] = bool(existing.get("critical", False) or item.get("critical", False))
        try:
            occurrence_count = int(item.get("occurrence_count", existing.get("occurrence_count", 0)) or 0)
        except Exception:
            occurrence_count = int(existing.get("occurrence_count", 0) or 0)
        existing["occurrence_count"] = occurrence_count
        try:
            avg_score_delta = float(item.get("avg_score_delta", existing.get("avg_score_delta", 0)) or 0)
        except Exception:
            avg_score_delta = float(existing.get("avg_score_delta", 0) or 0)
        existing["avg_score_delta"] = avg_score_delta
        try:
            latest_score_delta = float(item.get("latest_score_delta", existing.get("latest_score_delta", 0)) or 0)
        except Exception:
            latest_score_delta = float(existing.get("latest_score_delta", 0) or 0)
        existing["latest_score_delta"] = latest_score_delta
        reason_text = " ".join(str(item.get("reason", "")).split()).strip() or "persistent-external-baseline-gap"
        existing["reason"] = reason_text
        persistent_external_gap_map[family_id] = existing
persistent_external_gap_ids = sorted(persistent_external_gap_map.keys())


def infer_benchmark_targets(plugin_copy):
    combined = " ".join([
        str(plugin_copy.get("name", "")),
        str(plugin_copy.get("description", "")),
        str(plugin_copy.get("instructions", "")),
        str(plugin_copy.get("implementation_plan", "")),
        str(plugin_copy.get("rationale", "")),
    ]).lower()
    domains = plugin_copy.get("domain_tags", [])
    if not isinstance(domains, list):
        domains = []
    domain_set = {str(item).strip() for item in domains if str(item).strip()}
    targets = []

    raw_targets = plugin_copy.get("benchmark_family_targets", [])
    if isinstance(raw_targets, list):
        for raw_target in raw_targets:
            token = normalize_benchmark_family_id(raw_target)
            if token and token not in targets:
                targets.append(token)

    if ("web-research" in domain_set or "knowledge-integration" in domain_set) and "research_integration" not in targets:
        targets.append("research_integration")
    if ("planning" in domain_set or "architecture" in domain_set) and "planning_architecture" not in targets:
        targets.append("planning_architecture")
    if "programming" in domain_set and "coding_mutation" not in targets:
        targets.append("coding_mutation")
    if "admin-setup" in domain_set and "admin_env_repair" not in targets:
        targets.append("admin_env_repair")
    if any(keyword in combined for keyword in teaching_keywords) and "teaching_reassessment" not in targets:
        targets.append("teaching_reassessment")
    if "verification" in domain_set:
        if any(keyword in combined for keyword in doc_review_keywords):
            if "review_document" not in targets:
                targets.append("review_document")
        elif "coding_mutation" not in targets:
            targets.append("coding_mutation")

    if any(keyword in combined for keyword in ["benchmark", "web research", "retrieval", "source quality", "search"]) and "research_integration" not in targets:
        targets.append("research_integration")
    if any(keyword in combined for keyword in ["architecture", "tradeoff", "design review", "planning gate", "decision checkpoint"]) and "planning_architecture" not in targets:
        targets.append("planning_architecture")
    if any(keyword in combined for keyword in ["mutation", "patch", "regression", "bounded coding", "verification pass"]) and "coding_mutation" not in targets:
        targets.append("coding_mutation")
    if any(keyword in combined for keyword in doc_review_keywords) and "review_document" not in targets:
        targets.append("review_document")
    if any(keyword in combined for keyword in ["install", "dependency", "environment repair", "bootstrap", "ollama runtime"]) and "admin_env_repair" not in targets:
        targets.append("admin_env_repair")

    return [target for target in targets if target in benchmark_family_ids][:4]


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
        benchmark_targets = infer_benchmark_targets(plugin_copy)
        targeted_gaps = [family_id for family_id in benchmark_targets if family_id in weak_family_map]
        targeted_external_gaps = [family_id for family_id in benchmark_targets if family_id in external_gap_map]
        targeted_persistent_external_gaps = [family_id for family_id in benchmark_targets if family_id in persistent_external_gap_map]
        critical_hits = [family_id for family_id in targeted_gaps if weak_family_map.get(family_id, {}).get("critical")]
        critical_external_hits = [family_id for family_id in targeted_external_gaps if external_gap_map.get(family_id, {}).get("critical")]
        critical_persistent_external_hits = [family_id for family_id in targeted_persistent_external_gaps if persistent_external_gap_map.get(family_id, {}).get("critical")]
        persistence_bonus = sum(min(3.0, float(persistent_external_gap_map.get(family_id, {}).get("occurrence_count", 0) or 0)) for family_id in targeted_persistent_external_gaps)
        alignment_score = (len(benchmark_targets) * 1.5) + (len(targeted_gaps) * 5.0) + (len(critical_hits) * 3.0) + (len(targeted_external_gaps) * 3.5) + (len(critical_external_hits) * 2.0) + (len(targeted_persistent_external_gaps) * 4.5) + (len(critical_persistent_external_hits) * 2.0) + persistence_bonus
        if risk_level == "high":
            alignment_score -= 2.0
        if alignment_score < 0:
            alignment_score = 0.0
        if targeted_gaps and targeted_persistent_external_gaps:
            promotion_state = "priority"
            promotion_reason = "Targets current benchmark weak families and persistent external-baseline gaps."
        elif targeted_persistent_external_gaps:
            promotion_state = "priority"
            promotion_reason = "Targets persistent families where an external baseline is still ahead."
        elif targeted_gaps and targeted_external_gaps:
            promotion_state = "priority"
            promotion_reason = "Targets current benchmark weak families and external-baseline gaps."
        elif targeted_gaps:
            promotion_state = "priority"
            promotion_reason = "Targets current benchmark weak families."
        elif targeted_external_gaps:
            promotion_state = "priority"
            promotion_reason = "Targets families where an external baseline is still ahead."
        elif benchmark_targets:
            promotion_state = "candidate"
            promotion_reason = "Maps to benchmark families but not the current weak-gap set."
        else:
            promotion_state = "hold"
            promotion_reason = "Does not map cleanly to a measured benchmark family yet."
        plugin_copy["benchmark_family_targets"] = benchmark_targets
        plugin_copy["targeted_capability_gaps"] = targeted_gaps
        plugin_copy["targeted_external_capability_gaps"] = targeted_external_gaps
        plugin_copy["targeted_persistent_external_capability_gaps"] = targeted_persistent_external_gaps
        plugin_copy["benchmark_alignment_score"] = round(alignment_score, 2)
        plugin_copy["promotion_state"] = promotion_state
        plugin_copy["promotion_reason"] = promotion_reason
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
    benchmark_target_coverage = []
    targeted_weak_gaps = []
    targeted_external_gaps = []
    targeted_persistent_external_gaps = []
    critical_weak_gap_hits = 0
    critical_external_gap_hits = 0
    critical_persistent_external_gap_hits = 0
    benchmark_alignment_sum = 0.0
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
        benchmark_targets = plugin.get("benchmark_family_targets", [])
        if isinstance(benchmark_targets, list):
            for family_id in benchmark_targets:
                if family_id in benchmark_family_ids and family_id not in benchmark_target_coverage:
                    benchmark_target_coverage.append(family_id)
        targeted_gaps = plugin.get("targeted_capability_gaps", [])
        if isinstance(targeted_gaps, list):
            for family_id in targeted_gaps:
                if family_id in weak_family_map and family_id not in targeted_weak_gaps:
                    targeted_weak_gaps.append(family_id)
                    if weak_family_map.get(family_id, {}).get("critical"):
                        critical_weak_gap_hits += 1
        external_targets = plugin.get("targeted_external_capability_gaps", [])
        if isinstance(external_targets, list):
            for family_id in external_targets:
                if family_id in external_gap_map and family_id not in targeted_external_gaps:
                    targeted_external_gaps.append(family_id)
                    if external_gap_map.get(family_id, {}).get("critical"):
                        critical_external_gap_hits += 1
        persistent_external_targets = plugin.get("targeted_persistent_external_capability_gaps", [])
        if isinstance(persistent_external_targets, list):
            for family_id in persistent_external_targets:
                if family_id in persistent_external_gap_map and family_id not in targeted_persistent_external_gaps:
                    targeted_persistent_external_gaps.append(family_id)
                    if persistent_external_gap_map.get(family_id, {}).get("critical"):
                        critical_persistent_external_gap_hits += 1
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
        try:
            benchmark_alignment_sum += float(plugin.get("benchmark_alignment_score", 0) or 0)
        except Exception:
            benchmark_alignment_sum += 0.0
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
    persistent_external_focus_bonus = sum(min(2.5, float(persistent_external_gap_map.get(family_id, {}).get("occurrence_count", 0) or 0)) for family_id in targeted_persistent_external_gaps)
    benchmark_focus_score = min(24.0, len(targeted_weak_gaps) * 6.0 + critical_weak_gap_hits * 2.5 + len(targeted_external_gaps) * 4.0 + critical_external_gap_hits * 1.5 + len(targeted_persistent_external_gaps) * 5.0 + critical_persistent_external_gap_hits * 1.5 + persistent_external_focus_bonus + len(benchmark_target_coverage) * 1.2)
    instruction_quality = 0.0
    if avg_instruction_words >= 14:
        instruction_quality = min(10.0, avg_instruction_words / 2.0)
    risk_penalty = max(0, risk_balance["high"] - max(1, plugin_count // 3)) * 1.5
    duplicate_penalty_score = duplicate_penalty * 3.0
    weak_gap_miss_penalty = 0.0
    if weak_family_ids and not targeted_weak_gaps:
        weak_gap_miss_penalty = 8.0
    external_gap_miss_penalty = 0.0
    if external_gap_ids and not targeted_external_gaps:
        external_gap_miss_penalty = 4.0
    persistent_external_gap_miss_penalty = 0.0
    if persistent_external_gap_ids and not targeted_persistent_external_gaps:
        persistent_external_gap_miss_penalty = 6.0

    total_score = coverage_score + plugin_count_score + evidence_score + implementation_score + benchmark_focus_score + instruction_quality
    total_score -= (risk_penalty + duplicate_penalty_score + weak_gap_miss_penalty + external_gap_miss_penalty + persistent_external_gap_miss_penalty)
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
        "benchmark_target_coverage": sorted(benchmark_target_coverage),
        "targeted_weak_gaps": sorted(targeted_weak_gaps),
        "targeted_external_gaps": sorted(targeted_external_gaps),
        "targeted_persistent_external_gaps": sorted(targeted_persistent_external_gaps),
        "critical_weak_gap_hits": critical_weak_gap_hits,
        "critical_external_gap_hits": critical_external_gap_hits,
        "critical_persistent_external_gap_hits": critical_persistent_external_gap_hits,
        "benchmark_alignment_score": round(benchmark_alignment_sum, 2),
        "weak_gap_miss": bool(weak_gap_miss_penalty > 0),
        "external_gap_miss": bool(external_gap_miss_penalty > 0),
        "persistent_external_gap_miss": bool(persistent_external_gap_miss_penalty > 0),
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


append_plugins(winner, winner_score["score"])
append_plugins(loser, loser_score["score"])

promotion_rank = {"priority": 0, "candidate": 1, "hold": 2}
risk_rank = {"low": 0, "medium": 1, "high": 2}
merged_plugins.sort(
    key=lambda payload: (
        promotion_rank.get(str(payload.get("promotion_state", "candidate")).strip().lower(), 3),
        -len(payload.get("targeted_capability_gaps", []) if isinstance(payload.get("targeted_capability_gaps", []), list) else []),
        -sum(1 for family_id in (payload.get("targeted_capability_gaps", []) if isinstance(payload.get("targeted_capability_gaps", []), list) else []) if weak_family_map.get(family_id, {}).get("critical")),
        -len(payload.get("targeted_persistent_external_capability_gaps", []) if isinstance(payload.get("targeted_persistent_external_capability_gaps", []), list) else []),
        -sum(1 for family_id in (payload.get("targeted_persistent_external_capability_gaps", []) if isinstance(payload.get("targeted_persistent_external_capability_gaps", []), list) else []) if persistent_external_gap_map.get(family_id, {}).get("critical")),
        -len(payload.get("targeted_external_capability_gaps", []) if isinstance(payload.get("targeted_external_capability_gaps", []), list) else []),
        -sum(1 for family_id in (payload.get("targeted_external_capability_gaps", []) if isinstance(payload.get("targeted_external_capability_gaps", []), list) else []) if external_gap_map.get(family_id, {}).get("critical")),
        -float(payload.get("benchmark_alignment_score", 0) or 0),
        -float(payload.get("competition_score", 0) or 0),
        risk_rank.get(str(payload.get("risk_level", "medium")).strip().lower(), 3),
        str(payload.get("name", "")).strip().lower(),
    )
)
merged_plugins = merged_plugins[:8]

objective_text = " ".join(str(objective_text).split()).strip()
if not objective_text:
    objective_text = "Improve Artificer self-improvement quality."

winner_lane = winner.get("lane", "artificer")
winner_model = winner.get("model", primary_model)
winner_domains = ", ".join(winner_score["domain_coverage"]) if winner_score["domain_coverage"] else "none"
opponent_score = challenger_score["score"] if winner_lane == "artificer" else primary_score["score"]
weak_family_text = ", ".join(weak_family_ids) if weak_family_ids else "none"
summary = (
    f"{winner_lane} lane won ({winner_score['score']:.2f} vs {opponent_score:.2f}). "
    f"Objective: {objective_text}. Covered domains: {winner_domains}. "
    f"Benchmark weak families: {weak_family_text}. "
    f"Merged plugins: {len(merged_plugins)}."
)
summary = " ".join(summary.split())

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
    "capability_benchmark_focus": {
        "latest_recommendation": str(latest_scorecard.get("recommendation", "")).strip(),
        "weak_family_ids": weak_family_ids,
        "weak_families": [weak_family_map[family_id] for family_id in weak_family_ids],
        "external_gap_family_ids": external_gap_ids,
        "external_gap_families": [external_gap_map[family_id] for family_id in external_gap_ids],
        "persistent_external_gap_family_ids": persistent_external_gap_ids,
        "persistent_external_gaps": [persistent_external_gap_map[family_id] for family_id in persistent_external_gap_ids],
    },
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
capability_benchmark_focus = report.get("capability_benchmark_focus", {}) if isinstance(report, dict) else {}
if not isinstance(capability_benchmark_focus, dict):
    capability_benchmark_focus = {}
runtime_signals = evidence.get("runtime_signals", {}) if isinstance(evidence, dict) else {}
if not isinstance(runtime_signals, dict):
    runtime_signals = {}
benchmark_runtime = runtime_signals.get("capability_benchmark", {})
if not isinstance(benchmark_runtime, dict):
    benchmark_runtime = {}
latest_compare = benchmark_runtime.get("latest_compare", {})
if not isinstance(latest_compare, dict):
    latest_compare = {}
latest_external_compare = benchmark_runtime.get("latest_external_compare", {})
if not isinstance(latest_external_compare, dict):
    latest_external_compare = {}
operator_policy_set = {
    "auto",
    "force-adopted",
    "force-trial",
    "force-review",
    "force-rejected",
}
weak_family_ids = capability_benchmark_focus.get("weak_family_ids", [])
if not isinstance(weak_family_ids, list):
    weak_family_ids = []
weak_family_ids = [" ".join(str(item).split()).strip() for item in weak_family_ids if str(item).strip()]
external_gap_family_ids = capability_benchmark_focus.get("external_gap_family_ids", [])
if not isinstance(external_gap_family_ids, list):
    external_gap_family_ids = []
external_gap_family_ids = [" ".join(str(item).split()).strip() for item in external_gap_family_ids if str(item).strip()]
persistent_external_gap_family_ids = capability_benchmark_focus.get("persistent_external_gap_family_ids", [])
if not isinstance(persistent_external_gap_family_ids, list):
    persistent_external_gap_family_ids = []
persistent_external_gap_family_ids = [" ".join(str(item).split()).strip() for item in persistent_external_gap_family_ids if str(item).strip()]
compare_recommendation = " ".join(str(latest_compare.get("recommendation", "")).split()).strip()
candidate_promotable = bool(latest_compare.get("candidate_promotable", False))
external_compare_recommendation = " ".join(str(latest_external_compare.get("recommendation", "")).split()).strip()
candidate_beats_external = bool(latest_external_compare.get("candidate_beats_external", False))
external_baseline = latest_external_compare.get("external_baseline", {})
if not isinstance(external_baseline, dict):
    external_baseline = {}
external_baseline_name = " ".join(str(external_baseline.get("name", "")).split()).strip()
current_benchmark_compare_count = int(benchmark_runtime.get("compare_count", 0) or 0)


def clean_family_ids(values):
    clean = []
    if not isinstance(values, list):
        return clean
    for item in values:
        value = ""
        if isinstance(item, dict):
            value = item.get("id", "")
        else:
            value = item
        text = " ".join(str(value).split()).strip()
        if text and text not in clean:
            clean.append(text)
    return clean


def normalize_operator_policy(value):
    policy = str(value or "").strip().lower()
    if policy in operator_policy_set:
        return policy
    return "auto"


def operator_policy_target(policy):
    mapping = {
        "force-adopted": "adopted",
        "force-trial": "trial",
        "force-review": "review",
        "force-rejected": "rejected",
    }
    return mapping.get(normalize_operator_policy(policy), "")


def normalize_lineage_key(value):
    text = " ".join(str(value or "").split()).strip().lower()
    if not text:
        return ""
    text = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", text)
    text = re.sub(r"[^a-z0-9-]+", "-", text).strip("-")
    return text


def lineage_key_for_payload(payload):
    if not isinstance(payload, dict):
        return ""
    for value in [payload.get("lineage_key", ""), payload.get("name", ""), payload.get("id", "")]:
        line = normalize_lineage_key(value)
        if line:
            return line
    return ""


def current_timestamp():
    return dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def normalize_existing_adoption_state(payload):
    adoption_state = " ".join(str(payload.get("adoption_state", "")).split()).strip().lower()
    if adoption_state in {"adopted", "trial", "review", "rejected"}:
        return adoption_state
    if bool(payload.get("enabled", False)):
        return "trial"
    if payload.get("benchmark_family_targets"):
        return "review"
    return "rejected"


def report_plugin_lineage_key(plugin, index):
    if not isinstance(plugin, dict):
        return ""
    base_id = str(plugin.get("id", "")).strip().lower()
    if not base_id:
        base_id = str(plugin.get("name", "")).strip().lower()
    base_id = re.sub(r"[^a-z0-9-]+", "-", base_id).strip("-")
    if not base_id:
        base_id = f"plugin-{index}"
    return base_id


def prior_lineage_records(plugins_dir, lineage_key):
    records = []
    if not lineage_key or not os.path.isdir(plugins_dir):
        return records
    for name in os.listdir(plugins_dir):
        if not name.endswith(".json"):
            continue
        path = os.path.join(plugins_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            continue
        if lineage_key_for_payload(payload) != lineage_key:
            continue
        sort_key = " ".join(str(payload.get("generated_at", "")).split()).strip() or name
        records.append((sort_key, path, payload))
    records.sort(key=lambda item: item[0], reverse=True)
    return records


def archive_payload(archive_dir, source_name, payload):
    archive_name = source_name
    archive_path = os.path.join(archive_dir, archive_name)
    suffix = 2
    while os.path.exists(archive_path):
        archive_base = os.path.splitext(source_name)[0]
        archive_name = f"{archive_base}-{suffix}.json"
        archive_path = os.path.join(archive_dir, archive_name)
        suffix += 1
    with open(archive_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
    return archive_name


def prune_stale_plugins(plugins_dir, compare_count, incoming_lineage_keys, archived_at):
    archived_ids = []
    if compare_count <= 0 or not os.path.isdir(plugins_dir):
        return archived_ids
    archive_dir = os.path.join(plugins_dir, "archive")
    os.makedirs(archive_dir, exist_ok=True)
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
        lineage_key = lineage_key_for_payload(payload)
        if lineage_key and lineage_key in incoming_lineage_keys:
            continue
        operator_policy = normalize_operator_policy(payload.get("operator_policy", "auto"))
        if operator_policy != "auto":
            continue
        adoption_state = normalize_existing_adoption_state(payload)
        if adoption_state not in {"review", "rejected"}:
            continue
        last_compare_count = int(payload.get("last_benchmark_compare_count", 0) or 0)
        if last_compare_count <= 0:
            payload["last_benchmark_compare_count"] = compare_count
            payload["stale_compare_cycles"] = 0
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=2)
            continue
        stale_compare_cycles = compare_count - last_compare_count
        if stale_compare_cycles < 0:
            stale_compare_cycles = 0
        payload["stale_compare_cycles"] = stale_compare_cycles
        archive_threshold = 3 if adoption_state == "review" else 2
        if stale_compare_cycles < archive_threshold:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=2)
            continue
        payload["archived"] = True
        payload["archived_at"] = archived_at
        payload["archived_via"] = "stale-benchmark-prune"
        payload["archived_from_state"] = adoption_state
        payload["archived_after_compare_cycles"] = stale_compare_cycles
        payload["archived_reason"] = f"Automatic archive after {stale_compare_cycles} later benchmark compare cycles left this {adoption_state} plugin stale without operator intervention."
        archive_payload(archive_dir, name, payload)
        try:
            os.remove(path)
        except OSError:
            continue
        archived_ids.append(" ".join(str(payload.get("id", os.path.splitext(name)[0])).split()).strip() or os.path.splitext(name)[0])
    return archived_ids


recovered_families = clean_family_ids(latest_compare.get("recovered_families", []))
improved_families = clean_family_ids(latest_compare.get("improved_families", []))
new_weak_families = clean_family_ids(latest_compare.get("new_weak_families", []))

generated_at = current_timestamp()
incoming_lineage_keys = set()
for index, plugin in enumerate(plugins, 1):
    lineage_key = report_plugin_lineage_key(plugin, index)
    if lineage_key:
        incoming_lineage_keys.add(lineage_key)
archived_plugin_ids = prune_stale_plugins(plugins_dir, current_benchmark_compare_count, incoming_lineage_keys, generated_at)
saved_ids = []
for index, plugin in enumerate(plugins, 1):
    if not isinstance(plugin, dict):
        continue
    base_id = report_plugin_lineage_key(plugin, index)
    lineage_key = base_id
    prior_records = prior_lineage_records(plugins_dir, lineage_key)
    prior_payload = prior_records[0][2] if prior_records else {}
    final_id = f"{generated_at[:10]}-{base_id}"
    suffix = 2
    while os.path.exists(os.path.join(plugins_dir, final_id + ".json")):
        final_id = f"{generated_at[:10]}-{base_id}-{suffix}"
        suffix += 1

    payload = dict(plugin)
    payload["id"] = final_id
    payload["lineage_key"] = lineage_key
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
    benchmark_family_targets = payload.get("benchmark_family_targets", [])
    if not isinstance(benchmark_family_targets, list):
        benchmark_family_targets = []
    payload["benchmark_family_targets"] = [" ".join(str(tag).split()).strip() for tag in benchmark_family_targets[:6] if str(tag).strip()]
    targeted_capability_gaps = payload.get("targeted_capability_gaps", [])
    if not isinstance(targeted_capability_gaps, list):
        targeted_capability_gaps = []
    payload["targeted_capability_gaps"] = [" ".join(str(tag).split()).strip() for tag in targeted_capability_gaps[:6] if str(tag).strip()]
    targeted_external_capability_gaps = payload.get("targeted_external_capability_gaps", [])
    if not isinstance(targeted_external_capability_gaps, list):
        targeted_external_capability_gaps = []
    payload["targeted_external_capability_gaps"] = [" ".join(str(tag).split()).strip() for tag in targeted_external_capability_gaps[:6] if str(tag).strip()]
    targeted_persistent_external_capability_gaps = payload.get("targeted_persistent_external_capability_gaps", [])
    if not isinstance(targeted_persistent_external_capability_gaps, list):
        targeted_persistent_external_capability_gaps = []
    payload["targeted_persistent_external_capability_gaps"] = [" ".join(str(tag).split()).strip() for tag in targeted_persistent_external_capability_gaps[:6] if str(tag).strip()]
    try:
        payload["benchmark_alignment_score"] = round(float(payload.get("benchmark_alignment_score", 0) or 0), 2)
    except Exception:
        payload["benchmark_alignment_score"] = 0.0
    promotion_state = " ".join(str(payload.get("promotion_state", "")).split()).strip().lower()
    if promotion_state not in {"priority", "candidate", "hold"}:
        if payload["targeted_capability_gaps"] or payload["targeted_external_capability_gaps"] or payload["targeted_persistent_external_capability_gaps"]:
            promotion_state = "priority"
        elif payload["benchmark_family_targets"]:
            promotion_state = "candidate"
        else:
            promotion_state = "hold"
    payload["promotion_state"] = promotion_state
    payload["promotion_reason"] = " ".join(str(payload.get("promotion_reason", "")).split()).strip()
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
    payload["benchmark_compare_recommendation"] = compare_recommendation
    payload["benchmark_candidate_promotable"] = candidate_promotable
    benchmark_targets_set = set(payload["benchmark_family_targets"])
    payload["benchmark_recovered_family_hits"] = [family_id for family_id in recovered_families if family_id in benchmark_targets_set]
    payload["benchmark_improved_family_hits"] = [family_id for family_id in improved_families if family_id in benchmark_targets_set and family_id not in payload["benchmark_recovered_family_hits"]]
    payload["benchmark_new_weak_family_hits"] = [family_id for family_id in new_weak_families if family_id in benchmark_targets_set]
    compare_present = bool(compare_recommendation)
    direct_compare_win = bool(payload["benchmark_recovered_family_hits"] or payload["benchmark_improved_family_hits"])
    previous_compare_count = int(prior_payload.get("benchmark_compare_count", 0) or 0)
    previous_promotable_hit_count = int(prior_payload.get("benchmark_promotable_hit_count", 0) or 0)
    previous_hold_count = int(prior_payload.get("benchmark_hold_count", 0) or 0)
    previous_success_streak = int(prior_payload.get("benchmark_success_streak", 0) or 0)
    previous_hold_streak = int(prior_payload.get("benchmark_hold_streak", 0) or 0)
    payload["benchmark_compare_count"] = previous_compare_count + (1 if compare_present else 0)
    payload["benchmark_promotable_hit_count"] = previous_promotable_hit_count + (1 if direct_compare_win else 0)
    payload["benchmark_hold_count"] = previous_hold_count + (1 if compare_present and (not candidate_promotable or payload["benchmark_new_weak_family_hits"]) else 0)
    payload["last_benchmark_compare_count"] = current_benchmark_compare_count if current_benchmark_compare_count > 0 else int(prior_payload.get("last_benchmark_compare_count", 0) or 0)
    payload["stale_compare_cycles"] = 0
    if direct_compare_win:
        payload["benchmark_success_streak"] = previous_success_streak + 1
        payload["benchmark_hold_streak"] = 0
    elif compare_present and (not candidate_promotable or payload["benchmark_new_weak_family_hits"]):
        payload["benchmark_success_streak"] = 0
        payload["benchmark_hold_streak"] = previous_hold_streak + 1
    elif compare_present:
        payload["benchmark_success_streak"] = 0
        payload["benchmark_hold_streak"] = 0
    else:
        payload["benchmark_success_streak"] = previous_success_streak
        payload["benchmark_hold_streak"] = previous_hold_streak
    if not payload["benchmark_family_targets"]:
        adoption_state = "rejected"
        adoption_reason = "No measurable benchmark family mapping."
    elif payload["benchmark_new_weak_family_hits"]:
        if payload["benchmark_hold_streak"] >= 2:
            adoption_state = "rejected"
            adoption_reason = "Two consecutive benchmark compares still showed the targeted family as weak."
        else:
            adoption_state = "review"
            adoption_reason = "Latest benchmark compare still shows the targeted family as weak; one more failed compare will reject it."
    elif direct_compare_win:
        if payload["benchmark_success_streak"] >= 2:
            adoption_state = "adopted"
            adoption_reason = "Two consecutive promotable benchmark compares improved this plugin's targeted families."
        else:
            adoption_state = "trial"
            adoption_reason = "One promotable benchmark compare improved this plugin's targeted families; one more consecutive promotable compare is required before adoption."
    elif compare_recommendation:
        if candidate_promotable and (payload["targeted_capability_gaps"] or payload["targeted_external_capability_gaps"] or payload["targeted_persistent_external_capability_gaps"]):
            adoption_state = "trial"
            adoption_reason = "Latest benchmark compare is promotable overall, but this plugin still needs direct family-level proof."
        elif payload["benchmark_hold_streak"] >= 2:
            adoption_state = "rejected"
            adoption_reason = "Two consecutive benchmark compares failed to prove this plugin improves its mapped families."
        elif payload["benchmark_family_targets"]:
            adoption_state = "review"
            adoption_reason = "Latest benchmark compare did not yet prove this plugin should stay active."
        else:
            adoption_state = "rejected"
            adoption_reason = "No measurable benchmark family mapping."
    else:
        if payload["targeted_capability_gaps"]:
            adoption_state = "trial"
            adoption_reason = "Targets current benchmark weak families and is waiting for measured compare evidence."
        elif payload["targeted_persistent_external_capability_gaps"]:
            adoption_state = "trial"
            adoption_reason = "Targets recurring families where an external baseline is still ahead and is waiting for measured compare evidence."
        elif payload["targeted_external_capability_gaps"]:
            adoption_state = "trial"
            adoption_reason = "Targets families where an external baseline is still ahead and is waiting for measured compare evidence."
        elif payload["benchmark_family_targets"]:
            adoption_state = "review"
            adoption_reason = "Maps to benchmark families and is waiting for measured compare evidence."
        else:
            adoption_state = "rejected"
            adoption_reason = "No measurable benchmark family mapping."
    payload["automatic_adoption_state"] = adoption_state
    payload["automatic_adoption_reason"] = adoption_reason
    payload["operator_policy"] = normalize_operator_policy(prior_payload.get("operator_policy", "auto") if isinstance(prior_payload, dict) and bool(prior_payload.get("operator_lock", False)) else "auto")
    payload["operator_lock"] = bool(prior_payload.get("operator_lock", False)) and payload["operator_policy"] != "auto"
    payload["operator_updated_at"] = " ".join(str(prior_payload.get("operator_updated_at", "")).split()).strip() if payload["operator_lock"] else ""
    operator_target = operator_policy_target(payload["operator_policy"])
    if operator_target:
        payload["adoption_state"] = operator_target
        payload["adoption_reason"] = f"Operator override forced {operator_target} state while benchmark automation remains available for reference."
        payload["enabled"] = operator_target in {"adopted", "trial"}
    else:
        payload["adoption_state"] = adoption_state
        payload["adoption_reason"] = adoption_reason
        payload["enabled"] = adoption_state in {"adopted", "trial"}
    payload["capability_benchmark"] = {
        "latest_recommendation": " ".join(str(benchmark_runtime.get("latest_scorecard", {}).get("recommendation", "")).split()).strip() if isinstance(benchmark_runtime.get("latest_scorecard", {}), dict) else "",
        "compare_recommendation": compare_recommendation,
        "candidate_promotable": candidate_promotable,
        "weak_family_ids": weak_family_ids,
        "recovered_families": recovered_families,
        "new_weak_families": new_weak_families,
        "external_compare_recommendation": external_compare_recommendation,
        "candidate_beats_external": candidate_beats_external,
        "external_gap_family_ids": external_gap_family_ids,
        "persistent_external_gap_family_ids": persistent_external_gap_family_ids,
        "external_baseline_name": external_baseline_name,
    }

    for _, old_path, _ in prior_records:
        try:
            os.remove(old_path)
        except OSError:
            pass
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
    "archived_plugin_ids": archived_plugin_ids,
    "capability_benchmark": {
        "latest_recommendation": " ".join(str(benchmark_runtime.get("latest_scorecard", {}).get("recommendation", "")).split()).strip() if isinstance(benchmark_runtime.get("latest_scorecard", {}), dict) else "",
        "compare_recommendation": compare_recommendation,
        "candidate_promotable": candidate_promotable,
        "weak_family_ids": weak_family_ids,
        "recovered_families": recovered_families,
        "new_weak_families": new_weak_families,
        "scorecard_count": int(benchmark_runtime.get("scorecard_count", 0) or 0),
        "compare_count": int(benchmark_runtime.get("compare_count", 0) or 0),
        "external_compare_count": int(benchmark_runtime.get("external_compare_count", 0) or 0),
        "external_compare_recommendation": external_compare_recommendation,
        "candidate_beats_external": candidate_beats_external,
        "external_gap_family_ids": external_gap_family_ids,
        "persistent_external_gap_family_ids": persistent_external_gap_family_ids,
        "external_baseline_name": external_baseline_name,
    },
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(last_run, handle, ensure_ascii=False, indent=2)
print(json.dumps(last_run, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_plugin_set_json() {
  plugin_id=$1
  enabled_value=$2
  operator_policy_value=${3-}
  operator_lock_value=${4-}
  python3 - "$self_improve_plugins_dir" "$plugin_id" "$enabled_value" "$operator_policy_value" "$operator_lock_value" <<'PY'
import json
import os
import sys

plugins_dir, plugin_id, enabled_value, operator_policy_value, operator_lock_value = sys.argv[1:6]
operator_policy_set = {
    "auto",
    "force-adopted",
    "force-trial",
    "force-review",
    "force-rejected",
}


def normalize_operator_policy(value):
    policy = str(value or "").strip().lower()
    if policy in operator_policy_set:
        return policy
    return "auto"


def operator_policy_target(policy):
    mapping = {
        "force-adopted": "adopted",
        "force-trial": "trial",
        "force-review": "review",
        "force-rejected": "rejected",
    }
    return mapping.get(normalize_operator_policy(policy), "")


path = os.path.join(plugins_dir, plugin_id + ".json")
if not os.path.isfile(path):
    print(json.dumps({"success": False, "error": "plugin not found"}))
    sys.exit(0)
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
payload["enabled"] = str(enabled_value).strip() in {"1", "true", "True", "TRUE", "yes", "on"}
operator_policy = normalize_operator_policy(operator_policy_value)
operator_lock = str(operator_lock_value).strip() in {"1", "true", "True", "TRUE", "yes", "on"}
if operator_policy == "auto":
    operator_lock = False
payload["operator_policy"] = operator_policy
payload["operator_lock"] = operator_lock
payload["operator_updated_at"] = current_timestamp = __import__("datetime").datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
operator_target = operator_policy_target(operator_policy)
if operator_target:
    payload["adoption_state"] = operator_target
    payload["adoption_reason"] = f"Operator override forced {operator_target} state while benchmark automation remains available for reference."
    payload["enabled"] = operator_target in {"adopted", "trial"}
elif payload.get("automatic_adoption_state"):
    payload["adoption_state"] = str(payload.get("automatic_adoption_state", "")).strip().lower() or str(payload.get("adoption_state", "")).strip().lower()
    payload["adoption_reason"] = " ".join(str(payload.get("automatic_adoption_reason", payload.get("adoption_reason", ""))).split()).strip()
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

self_improve_archived_plugin_restore_json() {
  archive_entry_id=$1
  python3 - "$self_improve_plugins_dir" "$self_improve_last_run_file" "$archive_entry_id" <<'PY'
import datetime as dt
import json
import os
import re
import sys

plugins_dir, last_run_file, archive_entry_id = sys.argv[1:4]
archive_dir = os.path.join(plugins_dir, "archive")
archive_path = os.path.join(archive_dir, archive_entry_id + ".json")

if not os.path.isfile(archive_path):
    print(json.dumps({"success": False, "error": "archived plugin not found"}))
    sys.exit(0)

try:
    with open(archive_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    print(json.dumps({"success": False, "error": "archived plugin is unreadable"}))
    sys.exit(0)

if not isinstance(payload, dict):
    print(json.dumps({"success": False, "error": "archived plugin is invalid"}))
    sys.exit(0)


def current_timestamp():
    return dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def normalize_lineage_key(value):
    text = " ".join(str(value or "").split()).strip().lower()
    if not text:
        return ""
    text = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", text)
    text = re.sub(r"[^a-z0-9-]+", "-", text).strip("-")
    return text


def lineage_key_for_payload(item):
    if not isinstance(item, dict):
        return ""
    for value in [item.get("lineage_key", ""), item.get("name", ""), item.get("id", "")]:
        key = normalize_lineage_key(value)
        if key:
            return key
    return ""


lineage_key = lineage_key_for_payload(payload)
if not lineage_key:
    lineage_key = normalize_lineage_key(archive_entry_id) or archive_entry_id

for name in sorted(os.listdir(plugins_dir)) if os.path.isdir(plugins_dir) else []:
    if not name.endswith(".json"):
        continue
    path = os.path.join(plugins_dir, name)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            active_payload = json.load(handle)
    except Exception:
        continue
    if lineage_key_for_payload(active_payload) == lineage_key:
        print(json.dumps({"success": False, "error": "an active plugin with this lineage already exists"}))
        sys.exit(0)

current_compare_count = 0
if os.path.isfile(last_run_file):
    try:
        with open(last_run_file, "r", encoding="utf-8") as handle:
            last_run_payload = json.load(handle)
    except Exception:
        last_run_payload = {}
    if isinstance(last_run_payload, dict):
        benchmark_payload = last_run_payload.get("capability_benchmark", {})
        if isinstance(benchmark_payload, dict):
            current_compare_count = int(benchmark_payload.get("compare_count", 0) or 0)

generated_at = current_timestamp()
restored = dict(payload)
base_id = lineage_key or normalize_lineage_key(restored.get("id", "")) or archive_entry_id
final_id = f"{generated_at[:10]}-{base_id}-restored"
suffix = 2
while os.path.exists(os.path.join(plugins_dir, final_id + ".json")):
    final_id = f"{generated_at[:10]}-{base_id}-restored-{suffix}"
    suffix += 1

for key in [
    "archived",
    "archived_at",
    "archived_via",
    "archived_from_state",
    "archived_after_compare_cycles",
    "archived_reason",
]:
    restored.pop(key, None)

restored["id"] = final_id
restored["lineage_key"] = lineage_key
restored["generated_at"] = generated_at
restored["enabled"] = False
restored["stale_compare_cycles"] = 0
restored["last_benchmark_compare_count"] = current_compare_count
restored["operator_policy"] = "force-review"
restored["operator_lock"] = True
restored["operator_updated_at"] = generated_at
restored["adoption_state"] = "review"
restored["adoption_reason"] = "Restored from archive for manual re-evaluation."
restored["restored_from_archive_entry_id"] = archive_entry_id
restored["restored_at"] = generated_at

automatic_state = " ".join(str(restored.get("automatic_adoption_state", "")).split()).strip().lower()
if automatic_state not in {"adopted", "trial", "review", "rejected"}:
    automatic_state = " ".join(str(payload.get("archived_from_state", "")).split()).strip().lower() or "review"
restored["automatic_adoption_state"] = automatic_state
restored["automatic_adoption_reason"] = " ".join(str(restored.get("automatic_adoption_reason", "")).split()).strip() or "Previously archived benchmark state preserved for reference."

with open(os.path.join(plugins_dir, final_id + ".json"), "w", encoding="utf-8") as handle:
    json.dump(restored, handle, ensure_ascii=False, indent=2)
os.remove(archive_path)

print(json.dumps({"success": True, "plugin": restored}, ensure_ascii=False, separators=(",", ":")))
PY
}

self_improve_archived_plugin_delete_json() {
  archive_entry_id=$1
  archive_file="$self_improve_plugins_dir/archive/$archive_entry_id.json"
  if [ ! -f "$archive_file" ]; then
    printf '{"success":false,"error":"archived plugin not found"}\n'
    return 0
  fi
  rm -f "$archive_file"
  printf '{"success":true,"deleted_archive_entry_id":"%s"}\n' "$(json_escape "$archive_entry_id")"
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
items = []
adoption_rank = {"adopted": 0, "trial": 1, "review": 2, "rejected": 3}
promotion_rank = {"priority": 0, "candidate": 1, "hold": 2}


def safe_number(value):
    try:
        return float(value or 0)
    except Exception:
        return 0.0


def normalize_adoption_state(payload):
    adoption_state = str(payload.get("adoption_state", "")).strip().lower()
    if adoption_state in adoption_rank:
        return adoption_state
    if bool(payload.get("enabled", False)):
        return "trial"
    promotion_state = str(payload.get("promotion_state", "candidate")).strip().lower()
    if promotion_state == "hold":
        return "rejected"
    if payload.get("benchmark_family_targets"):
        return "review"
    return "rejected"


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
        promotion_state = str(payload.get("promotion_state", "candidate")).strip().lower()
        if promotion_state not in promotion_rank:
            promotion_state = "candidate"
        payload["promotion_state"] = promotion_state
        payload["adoption_state"] = normalize_adoption_state(payload)
        payload["benchmark_success_streak"] = int(payload.get("benchmark_success_streak", 0) or 0)
        items.append(payload)
items.sort(
    key=lambda payload: (
        adoption_rank.get(payload.get("adoption_state", "review"), 4),
        -safe_number(payload.get("benchmark_success_streak", 0)),
        promotion_rank.get(payload.get("promotion_state", "candidate"), 3),
        -safe_number(payload.get("benchmark_alignment_score", 0)),
        str(payload.get("name", payload.get("id", ""))).strip().lower(),
    )
)
for payload in items:
    title = " ".join(str(payload.get("name", payload.get("id", ""))).split()).strip()
    instructions = " ".join(str(payload.get("instructions", "")).split()).strip()
    if not title or not instructions:
        continue
    targets = payload.get("benchmark_family_targets", [])
    if not isinstance(targets, list):
        targets = []
    target_text = ", ".join([" ".join(str(target).split()).strip() for target in targets if str(target).strip()][:3])
    promotion_state = " ".join(str(payload.get("promotion_state", "")).split()).strip()
    adoption_state = " ".join(str(payload.get("adoption_state", "")).split()).strip()
    label_bits = []
    if adoption_state:
        label_bits.append(adoption_state)
    if promotion_state:
        label_bits.append(promotion_state)
    if target_text:
        label_bits.append(f"targets {target_text}")
    if label_bits:
        lines.append(f"- {title} [{'; '.join(label_bits)}]: {instructions}")
    elif promotion_state:
        lines.append(f"- {title} [{promotion_state}]: {instructions}")
    else:
        lines.append(f"- {title}: {instructions}")
for line in lines[:8]:
    print(line)
PY
}
