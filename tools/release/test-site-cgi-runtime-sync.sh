#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

sh "$repo_root/artificer" ensure-site >/dev/null

sites_root=${WEB_WIZARDRY_ROOT:-$HOME/sites}
site_root="$sites_root/artificer"

required_paths='
cgi/artificer-api
cgi/artificer-api-lib.sh
cgi/actions/_default.sh
cgi/lib/00-bootstrap.sh
cgi/lib/runtime/40g-state-ui.sh
'

for rel_path in $required_paths; do
  abs_path="$site_root/$rel_path"
  if [ ! -f "$abs_path" ]; then
    printf '%s\n' "missing deployed CGI runtime file: $abs_path" >&2
    exit 1
  fi
done

out_file=$(mktemp "${TMPDIR:-/tmp}/artificer-cgi-sync.out.XXXXXX")
err_file=$(mktemp "${TMPDIR:-/tmp}/artificer-cgi-sync.err.XXXXXX")
trap 'rm -f "$out_file" "$err_file"' EXIT INT HUP TERM

REQUEST_METHOD=GET \
QUERY_STRING='action=state&level=light&cached=0' \
SCRIPT_NAME='/cgi/artificer-api' \
SCRIPT_FILENAME="$site_root/cgi/artificer-api" \
GATEWAY_INTERFACE='CGI/1.1' \
SERVER_PROTOCOL='HTTP/1.1' \
HTTP_HOST='localhost:8082' \
WIZARDRY_SITE_NAME='artificer' \
sh "$site_root/cgi/artificer-api" >"$out_file" 2>"$err_file"

if [ -s "$err_file" ]; then
  printf '%s\n' "CGI stderr is not empty after ensure-site sync:" >&2
  sed -n '1,80p' "$err_file" >&2
  exit 1
fi

if ! grep -q '^Status: 200 OK' "$out_file"; then
  printf '%s\n' "state CGI response did not return Status: 200 OK" >&2
  sed -n '1,80p' "$out_file" >&2
  exit 1
fi

if ! grep -q '"success":true' "$out_file"; then
  printf '%s\n' "state CGI response did not include success=true payload" >&2
  sed -n '1,80p' "$out_file" >&2
  exit 1
fi

printf '%s\n' "ok deployed CGI runtime tree is synchronized and executable"
