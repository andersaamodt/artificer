#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-runtime-alias.XXXXXX")
sites_root="$tmp_root/sites"
state_home="$tmp_root/state"
isolated_home="$tmp_root/home"
project_dir="$tmp_root/project"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}
mkdir -p "$sites_root" "$state_home" "$isolated_home" "$project_dir"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

urlenc() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse

value = sys.argv[1] if len(sys.argv) > 1 else ""
print(urllib.parse.quote_plus(value), end="")
PY
}

extract_json_body() {
  response_file=$1
  awk '
    BEGIN {
      in_body = 0
      last = ""
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (in_body == 0) {
        if (line == "") {
          in_body = 1
        }
        next
      }
      if (line != "") {
        last = line
      }
    }
    END {
      print last
    }
  ' "$response_file"
}

invoke_cgi_post() {
  body=$1
  out_file=$2
  err_file=$3
  body_length=$(printf '%s' "$body" | wc -c | tr -d ' ')
  (
    REQUEST_METHOD=POST
    CONTENT_TYPE='application/x-www-form-urlencoded'
    CONTENT_LENGTH=$body_length
    QUERY_STRING=''
    SCRIPT_NAME='/cgi/artificer-api'
    SCRIPT_FILENAME=$api_path
    GATEWAY_INTERFACE='CGI/1.1'
    SERVER_PROTOCOL='HTTP/1.1'
    HTTP_HOST='localhost:8082'
    WIZARDRY_SITE_NAME='artificer'
    WIZARDRY_SITES_DIR=$sites_root
    WEB_WIZARDRY_ROOT=$sites_root
    WIZARDRY_DIR=$wizardry_dir_real
    HOME=$isolated_home
    PATH="/usr/bin:/bin"
    XDG_STATE_HOME=$state_home
    ARTIFICER_STATE_ROOT="$state_home/artificer"
    export REQUEST_METHOD CONTENT_TYPE CONTENT_LENGTH QUERY_STRING SCRIPT_NAME SCRIPT_FILENAME GATEWAY_INTERFACE SERVER_PROTOCOL HTTP_HOST
    export WIZARDRY_SITE_NAME WIZARDRY_SITES_DIR WEB_WIZARDRY_ROOT WIZARDRY_DIR HOME PATH XDG_STATE_HOME ARTIFICER_STATE_ROOT
    printf '%s' "$body" | sh "$api_path"
  ) >"$out_file" 2>"$err_file"
}

WEB_WIZARDRY_ROOT="$sites_root" \
WIZARDRY_SITES_DIR="$sites_root" \
XDG_STATE_HOME="$state_home" \
ARTIFICER_STATE_ROOT="$state_home/artificer" \
sh "$repo_root/artificer" ensure-site >/dev/null

site_root="$sites_root/artificer"
api_path="$site_root/cgi/artificer-api"
[ -f "$api_path" ] || fail "missing CGI entrypoint"

post_out="$tmp_root/post.out"
post_err="$tmp_root/post.err"

invoke_cgi_post "action=add_workspace&path=$(urlenc "$project_dir")&name=alias-contract" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "add_workspace emitted stderr"
workspace_json=$(extract_json_body "$post_out")
workspace_id=$(WORKSPACE_JSON="$workspace_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("WORKSPACE_JSON", ""))
assert payload.get("success") is True
workspace = payload.get("workspace") or {}
workspace_id = str(workspace.get("id") or "")
assert workspace_id, "workspace id missing"
print(workspace_id, end="")
PY
)

invoke_cgi_post "action=new_conversation&workspace_id=$(urlenc "$workspace_id")&title=Alias%20Contract&model=mistral%3Alatest" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "new_conversation emitted stderr"
conversation_json=$(extract_json_body "$post_out")
conversation_id=$(CONVERSATION_JSON="$conversation_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("CONVERSATION_JSON", ""))
assert payload.get("success") is True
conversation = payload.get("conversation") or {}
conversation_id = str(conversation.get("id") or "")
assert conversation_id, "conversation id missing"
print(conversation_id, end="")
PY
)

invoke_cgi_post "action=queue_enqueue&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&prompt=alias-check&run_mode=team&compute_budget=standard&command_exec_mode=ask&permission_mode=full-access" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "queue_enqueue emitted stderr"
queue_enqueue_json=$(extract_json_body "$post_out")
QUEUE_ENQUEUE_JSON="$queue_enqueue_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("QUEUE_ENQUEUE_JSON", ""))
assert payload.get("success") is True
assert payload.get("item_id"), "queue item id missing"
PY

invoke_cgi_post "action=queue_take&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "queue_take emitted stderr"
queue_take_json=$(extract_json_body "$post_out")
QUEUE_TAKE_JSON="$queue_take_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("QUEUE_TAKE_JSON", ""))
assert payload.get("success") is True
assert payload.get("has_item") is True
item = payload.get("item") or {}
assert item.get("run_mode") == "assistant", f"run_mode not canonicalized: {item.get('run_mode')!r}"
assert item.get("command_exec_mode") == "ask-some", f"command_exec_mode not canonicalized: {item.get('command_exec_mode')!r}"
assert item.get("permission_mode") == "default", f"permission_mode not canonicalized: {item.get('permission_mode')!r}"
PY

invoke_cgi_post "action=automation_upsert&workspace_id=$(urlenc "$workspace_id")&conversation_id=$(urlenc "$conversation_id")&name=alias-nightly&prompt=alias-prompt&schedule_kind=interval&schedule_value=900&run_mode=teams&command_exec_mode=ask&permission_mode=full-access" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "automation_upsert emitted stderr"
automation_json=$(extract_json_body "$post_out")
AUTOMATION_JSON="$automation_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("AUTOMATION_JSON", ""))
assert payload.get("success") is True
automation = payload.get("automation") or {}
assert automation.get("run_mode") == "assistant", f"automation run_mode not canonicalized: {automation.get('run_mode')!r}"
assert automation.get("command_exec_mode") == "ask-some", f"automation command_exec_mode not canonicalized: {automation.get('command_exec_mode')!r}"
assert automation.get("permission_mode") == "default", f"automation permission_mode not canonicalized: {automation.get('permission_mode')!r}"
automations = payload.get("automations") or {}
items = automations.get("items") or []
assert items, "automation state payload missing items"
latest = items[0] or {}
assert latest.get("run_mode") == "assistant"
assert latest.get("command_exec_mode") == "ask-some"
assert latest.get("permission_mode") == "default"
PY

invoke_cgi_post "action=command_policy_set&workspace_id=$(urlenc "$workspace_id")&mode=ask" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "command_policy_set emitted stderr"
command_set_json=$(extract_json_body "$post_out")
COMMAND_SET_JSON="$command_set_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("COMMAND_SET_JSON", ""))
assert payload.get("success") is True
assert payload.get("mode") == "ask-some", f"command policy set mode not canonicalized: {payload.get('mode')!r}"
PY

invoke_cgi_post "action=command_policy_get&workspace_id=$(urlenc "$workspace_id")" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "command_policy_get emitted stderr"
command_get_json=$(extract_json_body "$post_out")
COMMAND_GET_JSON="$command_get_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("COMMAND_GET_JSON", ""))
assert payload.get("success") is True
assert payload.get("mode") == "ask-some", f"command policy get mode mismatch: {payload.get('mode')!r}"
PY

printf '%s\n' "ok runtime alias normalization contract: queue, automations, and command policy canonicalize aliases consistently"
