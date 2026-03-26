#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

public_files='
README.md
CHANGELOG.md
CONTRIBUTING.md
docs/README.md
docs/GETTING_STARTED.md
docs/PROJECT_LAYOUT.md
docs/PUBLISHING_AUDIT.md
docs/release-notes/v0.1.0.md
artificer
run-artificer
install
uninstall
tools/release/common.sh
tools/release/install-artificer.sh
tools/release/uninstall-artificer.sh
tools/release/build-release-bundle.sh
tools/release/build-macos-app.sh
tools/release/build-release-artifacts.sh
scripts/artificer-automations.sh
.github/workflows/build-artificer.yml
'

gui_files='
hosted-web/pages/index.md
hosted-web/pages/index.html
hosted-web/static/style.css
hosted-web/static/artificer-app.js
'

printf '%s\n' '== public surface: personal paths or names =='
printf '%s\n' "$public_files" \
  | sed '/^$/d' \
  | sed "s#^#$repo_root/#" \
  | xargs grep -nE '/Users/[^/[:space:]]+|/home/[^/[:space:]]+' \
  || true

printf '\n%s\n' '== internal legacy naming =='
printf '%s\n' "$gui_files" \
  | sed '/^$/d' \
  | sed "s#^#$repo_root/#" \
  | xargs grep -n 'forge-shell' \
  || true
