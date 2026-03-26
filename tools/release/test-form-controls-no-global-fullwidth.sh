#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
style_file="$repo_root/hosted-web/static/style.css"

if [ ! -f "$style_file" ]; then
  printf '%s\n' "missing style.css at $style_file" >&2
  exit 1
fi

if perl -0777 -ne 'exit((/input\s*,\s*textarea\s*,\s*select\s*\{[^}]*width\s*:\s*100%/s)?0:1)' "$style_file"; then
  printf '%s\n' "global input/textarea/select rule still forces width: 100%" >&2
  exit 1
fi

if perl -0777 -ne 'exit((/(^|\n)\s*select\s*\{[^}]*width\s*:\s*100%/s)?0:1)' "$style_file"; then
  printf '%s\n' "global select rule still forces width: 100%" >&2
  exit 1
fi

if perl -0777 -ne 'exit((/(^|\n)\s*input\s*\{[^}]*width\s*:\s*100%/s)?0:1)' "$style_file"; then
  printf '%s\n' "global input rule still forces width: 100%" >&2
  exit 1
fi

printf '%s\n' "ok form control width policy: no global full-width input/select rules"
