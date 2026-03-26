#!/bin/sh
set -eu

wizardry_invoke_path() {
  wiz_dir=${1-}
  [ -n "$wiz_dir" ] || return 1
  printf '%s\n' "$wiz_dir/spells/.imps/sys/invoke-wizardry"
}

wizardry_bootstrap_or_install() {
  app_root=$1
  home_dir=${2-"$HOME"}

  release_common="$app_root/tools/release/common.sh"
  if [ -f "$release_common" ]; then
    # shellcheck disable=SC1090
    . "$release_common"
  fi

  preferred_wiz=${WIZARDRY_DIR:-}
  home_wiz="$home_dir/.wizardry"
  wiz=''
  iw=''

  if [ -n "$preferred_wiz" ]; then
    iw=$(wizardry_invoke_path "$preferred_wiz")
    if [ -f "$iw" ]; then
      wiz="$preferred_wiz"
    fi
  fi

  if [ -z "$wiz" ]; then
    iw=$(wizardry_invoke_path "$home_wiz")
    if [ -f "$iw" ]; then
      wiz="$home_wiz"
    fi
  fi

  if [ -z "$wiz" ]; then
    if [ -n "$preferred_wiz" ]; then
      wiz="$preferred_wiz"
    else
      wiz="$home_wiz"
    fi
    iw=$(wizardry_invoke_path "$wiz")
  fi

  if [ ! -f "$iw" ]; then
    if command -v ensure_wizardry_installed >/dev/null 2>&1; then
      target_wiz="$home_wiz"
      wiz=$(WIZARDRY_DIR="$target_wiz" ensure_wizardry_installed "$home_dir" 2>/dev/null || printf '%s' "$target_wiz")
    else
      wiz="$home_wiz"
    fi
    iw=$(wizardry_invoke_path "$wiz")
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
