#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
cg_root="$repo_root/hosted-web/cgi"
mock_lsp_server="$repo_root/hosted-web/tests/fixtures/mock-lsp-server.py"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-tool-hooks.XXXXXX")
isolated_home="$tmp_root/home"
data_home="$tmp_root/data"
state_home="$tmp_root/state"
workspace_root="$tmp_root/workspace"
hook_log="$state_home/tool-hooks.jsonl"
mkdir -p "$isolated_home" "$data_home" "$state_home" "$workspace_root"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cd "$workspace_root"
git init >/dev/null 2>&1
git config user.name "Artificer Release Test"
git config user.email "artificer@example.invalid"
cat > demo.py <<'EOF'
def demo_function():
    return "first"
EOF
git add demo.py
git commit -m "init" >/dev/null 2>&1
cat > demo.py <<'EOF'
def demo_function():
    return "second"
EOF

evidence_file="$tmp_root/evidence.txt"
WORKSPACE_ROOT="$workspace_root" \
EVIDENCE_FILE="$evidence_file" \
WIZARDRY_DIR="$wizardry_dir_real" \
ARTIFICER_LSP_SERVER_CMD="python3 $mock_lsp_server" \
ARTIFICER_TOOL_HOOK_LOG_FILE="$hook_log" \
HOME="$isolated_home" \
XDG_DATA_HOME="$data_home" \
XDG_STATE_HOME="$state_home" \
ARTIFICER_STATE_ROOT="$state_home/artificer" \
sh -c '
set -eu
. "$1" >/dev/null 2>&1
evidence=$(artificer_structured_prompt_evidence_block "$WORKSPACE_ROOT" "Inspect demo.py and explain the failure." "" "programming")
printf "%s\n" "$evidence" > "$EVIDENCE_FILE"
pre_json=$(artificer_tool_hook_pre_json "ws-test" "$WORKSPACE_ROOT" "cat demo.py" "cat demo.py" "default" "allow" "runtime-policy")
artificer_tool_hook_append_json "$pre_json"
output_file=$(mktemp "${TMPDIR:-/tmp}/artificer-hook-output.XXXXXX")
printf "%s\n" "ok demo output" > "$output_file"
post_json=$(artificer_tool_hook_post_json "ws-test" "cat demo.py" "ok" "$output_file")
artificer_tool_hook_append_json "$post_json"
rm -f "$output_file"
' "$cg_root/runtime-test-dummy" "$cg_root/artificer-api-lib.sh"

[ -f "$evidence_file" ] || fail "structured evidence output file missing"
[ -f "$hook_log" ] || fail "tool hook log file missing"

if ! grep -q 'Git status snapshot:' "$evidence_file"; then
  fail "structured evidence should include git status for tracked workspace changes"
fi
if ! grep -q 'LSP coding context:' "$evidence_file"; then
  fail "structured evidence should include LSP context when a referenced file can be probed"
fi
if ! grep -q 'demo.py: 1 errors, 0 warnings, top symbols: mockFunction (via python3)' "$evidence_file"; then
  fail "structured evidence should include compact LSP summary"
fi

line_count=$(wc -l < "$hook_log" | tr -d ' ')
[ "$line_count" = "2" ] || fail "tool hook log should record pre and post events"

python3 - <<'PY' "$hook_log"
import json
import sys
from pathlib import Path

hook_log = Path(sys.argv[1])
entries = [json.loads(line) for line in hook_log.read_text().splitlines() if line.strip()]
if len(entries) != 2:
    raise SystemExit("unexpected hook entry count")
pre, post = entries
if pre.get("phase") != "pre":
    raise SystemExit("missing pre hook entry")
if post.get("phase") != "post":
    raise SystemExit("missing post hook entry")
if pre.get("policy_decision") != "allow":
    raise SystemExit("pre hook should preserve policy decision")
if len(pre.get("code_context") or []) != 1:
    raise SystemExit("pre hook should carry one code-context probe")
if (pre.get("code_context") or [{}])[0].get("summary") != "demo.py: 1 errors, 0 warnings, top symbols: mockFunction (via python3)":
    raise SystemExit("pre hook should include compact code-context summary")
if post.get("status") != "ok":
    raise SystemExit("post hook should preserve command status")
if "ok demo output" not in (post.get("output_preview") or ""):
    raise SystemExit("post hook should preserve output preview")
PY

printf '%s\n' "ok tool hooks and structured evidence: git/LSP enrichment and pre/post hook logging stay wired"
