#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

generated_paths='
hosted-web/static/artificer-app.js
hosted-web/cgi/actions/run_parts/run-part-004.sh
hosted-web/cgi/lib/reasoning/30c-reasoning-contracts.sh
'

for rel_path in $generated_paths; do
  if git -C "$repo_root" ls-files --error-unmatch "$rel_path" >/dev/null 2>&1; then
    printf '%s\n' "generated artifact is tracked in git: $rel_path" >&2
    exit 1
  fi
  if [ -e "$repo_root/$rel_path" ] && ! git -C "$repo_root" check-ignore -q "$rel_path"; then
    printf '%s\n' "generated artifact exists but is not ignored: $rel_path" >&2
    exit 1
  fi
done

run_action="$repo_root/hosted-web/cgi/actions/run.sh"
reasoning_programming="$repo_root/hosted-web/cgi/lib/30-reasoning-programming.sh"
index_md="$repo_root/hosted-web/pages/index.md"
index_html="$repo_root/hosted-web/pages/index.html"
backend_file="$repo_root/scripts/artificer-backend.sh"

if ! grep -q 'run-part-004-src/' "$run_action"; then
  printf '%s\n' "run action does not load run-part-004 source shards" >&2
  exit 1
fi
if grep -q 'run-part-004.sh' "$run_action"; then
  printf '%s\n' "run action still references generated run-part-004.sh" >&2
  exit 1
fi

if ! grep -q '30c-reasoning-contracts-src/' "$reasoning_programming"; then
  printf '%s\n' "reasoning programming runtime does not load 30c source shards" >&2
  exit 1
fi
if grep -q '30c-reasoning-contracts.sh' "$reasoning_programming"; then
  printf '%s\n' "reasoning programming runtime still references generated 30c-reasoning-contracts.sh" >&2
  exit 1
fi

if ! grep -q '/static/artificer-app-src/' "$index_md"; then
  printf '%s\n' "index.md does not load frontend source shards" >&2
  exit 1
fi
if ! grep -q 'loadBundleFallback' "$index_md"; then
  printf '%s\n' "index.md is missing runtime bundle fallback loader" >&2
  exit 1
fi

if ! grep -q '/static/artificer-app-src/' "$index_html"; then
  printf '%s\n' "index.html does not load frontend source shards" >&2
  exit 1
fi
if ! grep -q 'loadBundleFallback' "$index_html"; then
  printf '%s\n' "index.html is missing runtime bundle fallback loader" >&2
  exit 1
fi

if ! grep -q 'bundle_src_dir=.*artificer-app-src' "$backend_file"; then
  printf '%s\n' "backend ensure-site flow does not build runtime bundle from source shards" >&2
  exit 1
fi
if ! grep -q 'bundle_out=.*artificer-app.js' "$backend_file"; then
  printf '%s\n' "backend ensure-site flow does not write runtime bundle path" >&2
  exit 1
fi

printf '%s\n' "ok generated artifact policy: source shards are canonical and generated outputs are untracked"
