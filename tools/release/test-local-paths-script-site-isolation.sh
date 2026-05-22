#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

result=$(
  unset WIZARDRY_SITES_DIR
  unset WIZARDRY_SITE_NAME
  . "$repo_root/hosted-web/scripts/artificer-local-paths.sh"
  artificer_ensure_local_dirs
  printf '%s|%s|%s|%s\n' \
    "$WIZARDRY_SITES_DIR" \
    "$WIZARDRY_SITE_NAME" \
    "$ARTIFICER_SCRIPT_SITES_ROOT" \
    "$ARTIFICER_REPO_ROOT"
)

wizardry_sites_dir=$(printf '%s' "$result" | awk -F'|' '{print $1}')
wizardry_site_name=$(printf '%s' "$result" | awk -F'|' '{print $2}')
script_sites_root=$(printf '%s' "$result" | awk -F'|' '{print $3}')
repo_root_reported=$(printf '%s' "$result" | awk -F'|' '{print $4}')

expected_sites_root="${XDG_STATE_HOME:-$HOME/.local/state}/artificer/sites"
if [ "$wizardry_sites_dir" != "$expected_sites_root" ]; then
  printf '%s\n' "unexpected WIZARDRY_SITES_DIR default: got '$wizardry_sites_dir' expected '$expected_sites_root'" >&2
  exit 1
fi

if [ "$script_sites_root" != "$expected_sites_root" ]; then
  printf '%s\n' "unexpected ARTIFICER_SCRIPT_SITES_ROOT default: got '$script_sites_root' expected '$expected_sites_root'" >&2
  exit 1
fi

if [ "$wizardry_site_name" != "artificer-assay" ]; then
  printf '%s\n' "unexpected WIZARDRY_SITE_NAME default: '$wizardry_site_name'" >&2
  exit 1
fi

case "$wizardry_sites_dir/" in
  "$repo_root_reported/"*|"$repo_root_reported")
    printf '%s\n' "WIZARDRY_SITES_DIR should not resolve inside repo root: $wizardry_sites_dir" >&2
    exit 1
    ;;
esac

if [ ! -d "$wizardry_sites_dir" ]; then
  printf '%s\n' "expected isolated script sites root to exist: $wizardry_sites_dir" >&2
  exit 1
fi

printf '%s\n' "ok local-paths defaults isolate script site data from main site store"
