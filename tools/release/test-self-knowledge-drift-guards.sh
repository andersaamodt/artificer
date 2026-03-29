#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

registry_file="$repo_root/hosted-web/cgi/lib/runtime/self_knowledge/40h1-registry.sh"
prompt_file="$repo_root/hosted-web/cgi/lib/runtime/self_knowledge/40h2-state-and-prompts.sh"
index_file="$repo_root/hosted-web/pages/index.md"
appctl_file="$repo_root/hosted-web/scripts/artificer-appctl"
allow_file="$repo_root/hosted-web/cgi/lib/runtime/intelligence_core/40e1-model-routing-events.sh"
run_part_file="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004-modules/10-runtime-and-finalization.sh"

for file_path in "$registry_file" "$prompt_file" "$index_file" "$appctl_file" "$allow_file" "$run_part_file"; do
  [ -f "$file_path" ] || {
    printf '%s\n' "missing drift-guard dependency: $file_path" >&2
    exit 1
  }
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/artificer-self-knowledge-drift.XXXXXX")
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT HUP TERM

topics_registry_file="$tmp_dir/topics-registry.txt"
topics_prompt_file="$tmp_dir/topics-prompt.txt"
gui_labels_file="$tmp_dir/gui-labels.txt"

python3 - "$registry_file" > "$topics_registry_file" <<'PY'
import json
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
m = re.search(r"self_knowledge_topics_json\(\)\s*\{\s*printf '%s' '([^']+)'", text, re.S)
if not m:
    raise SystemExit("failed to parse self_knowledge_topics_json")
topics = json.loads(m.group(1))
for topic in topics:
    print(topic)
PY

python3 - "$prompt_file" > "$topics_prompt_file" <<'PY'
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
m = re.search(
    r"Grounded knowledge topics \(use these exact names\):\n(.*?)\n\nSelf-knowledge behavior contract:",
    text,
    re.S,
)
if not m:
    raise SystemExit("failed to parse reflexive prompt topic block")
for raw_line in m.group(1).splitlines():
    line = raw_line.strip()
    if not line.startswith("- "):
        continue
    print(line[2:].strip())
PY

if ! diff -u "$topics_registry_file" "$topics_prompt_file" >/dev/null; then
  printf '%s\n' "self-knowledge topic drift detected between registry and reflexive prompt block" >&2
  exit 1
fi

python3 - "$registry_file" > "$gui_labels_file" <<'PY'
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
m = re.search(r"self_knowledge_gui_text\(\)\s*\{\s*cat <<'EOF'\n(.*?)\nEOF", text, re.S)
if not m:
    raise SystemExit("failed to parse self_knowledge_gui_text block")
seen = set()
for label in re.findall(r'"([^"]+)"', m.group(1)):
    if label in seen:
        continue
    seen.add(label)
    print(label)
PY

[ -s "$gui_labels_file" ] || {
  printf '%s\n' "self_knowledge_gui_text did not produce quoted GUI labels for drift checks" >&2
  exit 1
}

while IFS= read -r label || [ -n "$label" ]; do
  [ -n "$label" ] || continue
  if ! grep -Fq "$label" "$index_file"; then
    printf '%s\n' "GUI label documented in self_knowledge_gui_text is missing in index.md: $label" >&2
    exit 1
  fi
done < "$gui_labels_file"

for usage_snippet in \
  'project add' \
  'project list' \
  'project rename' \
  'project delete' \
  'thread new' \
  'thread list' \
  'thread archive' \
  'automation upsert' \
  'automation list' \
  'automation toggle' \
  'automation run-now' \
  'automation delete' \
  'knowledge show' \
  'knowledge teach'
do
  if ! grep -Fq "$usage_snippet" "$appctl_file"; then
    printf '%s\n' "appctl usage surface drift: missing command snippet '$usage_snippet'" >&2
    exit 1
  fi
done

for allow_snippet in \
  'project:add' \
  'project:list' \
  'project:rename' \
  'project:delete' \
  'thread:new' \
  'thread:list' \
  'thread:archive' \
  'automation:upsert' \
  'automation:list' \
  'automation:toggle' \
  'automation:run-now' \
  'automation:delete' \
  'knowledge:show' \
  'knowledge:teach'
do
  if ! grep -Fq "$allow_snippet" "$allow_file"; then
    printf '%s\n' "allowlist surface drift: missing command branch '$allow_snippet'" >&2
    exit 1
  fi
done

for guidance_snippet in \
  'project list --json' \
  'automation list --json' \
  'thread list --workspace-id <id> --json' \
  'project add|rename|delete' \
  'thread new|archive' \
  'automation upsert|toggle|run-now|delete'
do
  if ! grep -Fq "$guidance_snippet" "$run_part_file"; then
    printf '%s\n' "runtime controller guidance drift: missing self-actuation guidance '$guidance_snippet'" >&2
    exit 1
  fi
done

if ! grep -Fq 'overview|gui|architecture|llm-foundations|ollama-runtime|ollama-contributing|self-actuation' "$prompt_file"; then
  printf '%s\n' "knowledge teach topic guidance drift: prompt topic list is not synchronized" >&2
  exit 1
fi

printf '%s\n' "ok drift guards: self-knowledge topics, GUI labels, and appctl/allowlist/guidance command surfaces remain synchronized"
