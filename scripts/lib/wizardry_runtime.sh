#!/bin/sh
set -eu

wizardry_bootstrap_or_install() {
  app_root=$1
  home_dir=${2-"$HOME"}

  release_common="$app_root/tools/release/common.sh"
  if [ -f "$release_common" ]; then
    # shellcheck disable=SC1090
    . "$release_common"
  fi

  wiz="${WIZARDRY_DIR:-$home_dir/.wizardry}"
  iw="$wiz/spells/.imps/sys/invoke-wizardry"

  if [ ! -f "$iw" ]; then
    if command -v ensure_wizardry_installed >/dev/null 2>&1; then
      wiz=$(ensure_wizardry_installed "$home_dir" 2>/dev/null || printf '%s' "$home_dir/.wizardry")
    else
      wiz="$home_dir/.wizardry"
    fi
    iw="$wiz/spells/.imps/sys/invoke-wizardry"
  fi

  [ -f "$iw" ] || {
    printf 'wizardry runtime missing (%s)\n' "$iw" >&2
    return 127
  }

  WIZARDRY_DIR="$wiz"
  export WIZARDRY_DIR
  . "$iw" >/dev/null 2>&1 || {
    printf 'wizardry runtime initialization failed\n' >&2
    return 127
  }
}
