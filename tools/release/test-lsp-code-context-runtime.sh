#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
api_path="$repo_root/hosted-web/cgi/artificer-api"
client="$repo_root/hosted-web/scripts/artificer-runtime-client"
mock_lsp_server="$repo_root/hosted-web/tests/fixtures/mock-lsp-server.py"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

json_query() {
  payload=$1
  query=$2
  JSON_PAYLOAD=$payload JSON_QUERY=$query python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("JSON_PAYLOAD", ""))
query = os.environ.get("JSON_QUERY", "")
value = eval(query, {"__builtins__": {"len": len}}, {"data": payload})
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
elif value is None:
    print("")
else:
    print(str(value))
PY
}

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-lsp-code-context.XXXXXX")
isolated_home="$tmp_root/home"
data_home="$tmp_root/data"
state_home="$tmp_root/state"
workspace_root="$tmp_root/workspace"
mkdir -p "$isolated_home" "$data_home" "$state_home" "$workspace_root"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

cat >"$workspace_root/demo.py" <<'EOF'
def demo_function():
    return "hello"
EOF

run_client() {
  ARTIFICER_API_SCRIPT="$api_path" \
  WIZARDRY_DIR="$wizardry_dir_real" \
  ARTIFICER_LSP_SERVER_CMD="python3 $mock_lsp_server" \
  HOME="$isolated_home" \
  XDG_DATA_HOME="$data_home" \
  XDG_STATE_HOME="$state_home" \
  ARTIFICER_STATE_ROOT="$state_home/artificer" \
  sh "$client" "$@"
}

project_json=$(run_client project add --path "$workspace_root" --name "LSP Demo")
workspace_id=$(json_query "$project_json" '((data.get("workspace") or {}).get("id") or "")')
[ -n "$workspace_id" ] || fail "project add missing workspace id"

context_json=$(run_client code-context file --workspace-id "$workspace_id" --path "demo.py")
[ "$(json_query "$context_json" 'data.get("success")')" = "true" ] || fail "code-context request failed"
[ "$(json_query "$context_json" '((data.get("context") or {}).get("success"))')" = "true" ] || fail "code-context should succeed through mock LSP server"
[ "$(json_query "$context_json" 'len(((data.get("context") or {}).get("diagnostics") or []))')" = "1" ] || fail "code-context should expose one diagnostic from mock LSP server"
[ "$(json_query "$context_json" 'len(((data.get("context") or {}).get("symbols") or []))')" = "1" ] || fail "code-context should expose one symbol from mock LSP server"
[ "$(json_query "$context_json" '((data.get("context") or {}).get("summary") or "")')" = "demo.py: 1 errors, 0 warnings, top symbols: mockFunction (via python3)" ] || fail "code-context summary should be compact and file-specific"

printf '%s\n' "ok lsp code context runtime: headless code-context action exposes mock LSP diagnostics and symbols"
