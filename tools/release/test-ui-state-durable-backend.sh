#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/artificer-ui-state.XXXXXX")
sites_root="$tmp_root/sites"
state_home="$tmp_root/state"
isolated_home="$tmp_root/home"
wizardry_dir_real=${WIZARDRY_DIR:-$HOME/.wizardry}
mkdir -p "$sites_root" "$state_home" "$isolated_home"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT INT HUP TERM

fail() {
  printf '%s\n' "$1" >&2
  exit 1
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

invoke_cgi_get() {
  query=$1
  out_file=$2
  err_file=$3
  (
    REQUEST_METHOD=GET
    QUERY_STRING=$query
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
    export REQUEST_METHOD QUERY_STRING SCRIPT_NAME SCRIPT_FILENAME GATEWAY_INTERFACE SERVER_PROTOCOL HTTP_HOST
    export WIZARDRY_SITE_NAME WIZARDRY_SITES_DIR WEB_WIZARDRY_ROOT WIZARDRY_DIR HOME PATH XDG_STATE_HOME ARTIFICER_STATE_ROOT
    sh "$api_path"
  ) >"$out_file" 2>"$err_file"
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
get_out="$tmp_root/get.out"
get_err="$tmp_root/get.err"

invoke_cgi_post "action=ui_state_set&key=workspace_order&value=%5B%22ws-a%22%2C%22ws-b%22%5D" "$post_out" "$post_err"
[ ! -s "$post_err" ] || fail "ui_state_set emitted stderr"

post_json=$(extract_json_body "$post_out")
POST_JSON="$post_json" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("POST_JSON", ""))
assert payload.get("success") is True
assert payload.get("key") == "workspace_order"
PY

ui_state_file=$(find "$sites_root" -type f -path '*/ui-state/workspace-order.json' | sed -n '1p')
[ -n "$ui_state_file" ] || fail "ui_state_set did not create workspace order file"
stored_value=$(cat "$ui_state_file")
[ "$stored_value" = '["ws-a","ws-b"]' ] || fail "unexpected persisted workspace order payload"

invoke_cgi_get "action=ui_state_get&key=workspace_order" "$get_out" "$get_err"
[ ! -s "$get_err" ] || fail "ui_state_get emitted stderr"

get_json=$(extract_json_body "$get_out")
GET_JSON="$get_json" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("GET_JSON", ""))
assert payload.get("success") is True
assert payload.get("key") == "workspace_order"
assert payload.get("value") == '["ws-a","ws-b"]'
PY

js_state_file="$repo_root/hosted-web/static/artificer-app-modules/01b-runtime-state-and-automation.js"
sync_file="$repo_root/hosted-web/static/artificer-app-modules/05-api-and-state-sync.js"

grep -q 'hydrateDurableUiStateFromBackend' "$js_state_file" || fail "missing durable ui state hydration helper"
grep -q 'queueDurableUiStateWrite' "$js_state_file" || fail "missing durable ui state queue helper"
grep -q 'ui_state_set' "$js_state_file" || fail "durable ui writes are not routed through ui_state_set"
grep -q 'hydrateDurableUiStateFromBackend' "$sync_file" || fail "refreshAll is not hydrating durable ui state"

printf '%s\n' "ok durable ui state backend: ui_state actions and frontend wire-up validated"
