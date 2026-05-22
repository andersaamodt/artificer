#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

generated_paths='
hosted-web/static/artificer-app.js
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
run_module="$repo_root/hosted-web/cgi/actions/run_parts/run-part-004.sh"
reasoning_module="$repo_root/hosted-web/cgi/lib/reasoning/30c-reasoning-contracts.sh"

for canonical_file in "$run_module" "$reasoning_module"; do
  if [ ! -f "$canonical_file" ]; then
    printf '%s\n' "missing canonical runtime module: $canonical_file" >&2
    exit 1
  fi
done

if ! grep -q 'run-part-004.sh' "$run_action"; then
  printf '%s\n' "run action does not load canonical run-part-004 module" >&2
  exit 1
fi
if grep -q 'run-part-004-src/' "$run_action"; then
  printf '%s\n' "run action still references deprecated run-part-004 source fragments" >&2
  exit 1
fi

if ! grep -q '30c-reasoning-contracts.sh' "$reasoning_programming"; then
  printf '%s\n' "reasoning runtime does not load canonical 30c reasoning contracts module" >&2
  exit 1
fi
if grep -q '30c-reasoning-contracts-src/' "$reasoning_programming"; then
  printf '%s\n' "reasoning runtime still references deprecated 30c source fragments" >&2
  exit 1
fi

if ! grep -q '/static/artificer-app-modules/' "$index_md"; then
  printf '%s\n' "index.md does not load frontend source modules" >&2
  exit 1
fi
if ! grep -q 'loadBundleFallback' "$index_md"; then
  printf '%s\n' "index.md is missing runtime bundle fallback loader" >&2
  exit 1
fi

if ! grep -q '/static/artificer-app-modules/' "$index_html"; then
  printf '%s\n' "index.html does not load frontend source modules" >&2
  exit 1
fi
if ! grep -q 'loadBundleFallback' "$index_html"; then
  printf '%s\n' "index.html is missing runtime bundle fallback loader" >&2
  exit 1
fi

if ! grep -q 'bundle_src_dir=.*artificer-app-modules' "$backend_file"; then
  printf '%s\n' "backend ensure-site flow does not build runtime bundle from source modules" >&2
  exit 1
fi
if ! grep -q 'bundle_out=.*artificer-app.js' "$backend_file"; then
  printf '%s\n' "backend ensure-site flow does not write runtime bundle path" >&2
  exit 1
fi

printf '%s\n' "ok generated artifact policy: canonical source modules are tracked and frontend bundle output is untracked"
