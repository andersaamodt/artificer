#!/bin/sh
set -eu

# Extract JSON payload from mixed CGI output.
json_only() {
  awk 'BEGIN{p=0} /^\{/ {p=1} p {print}'
}

urlenc() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
value = sys.argv[1] if len(sys.argv) > 1 else ""
print(urllib.parse.quote(value, safe=""))
PY
}

# Build application/x-www-form-urlencoded key/value body from pairs.
form_body() {
  out=""
  while [ "$#" -ge 2 ]; do
    key=$1
    val=$2
    shift 2
    pair="$(urlenc "$key")=$(urlenc "$val")"
    if [ -n "$out" ]; then
      out="$out&$pair"
    else
      out="$pair"
    fi
  done
  printf '%s' "$out"
}
