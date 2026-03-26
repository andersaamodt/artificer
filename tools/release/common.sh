#!/bin/sh
set -eu

artificer_version() {
  root=${1-}
  [ -n "$root" ] || return 1
  if [ -f "$root/VERSION" ]; then
    sed -n '1p' "$root/VERSION"
    return 0
  fi
  printf '%s\n' '0.0.0'
}

artificer_stage_runtime() {
  root=${1-}
  dest=${2-}
  [ -n "$root" ] || {
    printf '%s\n' 'artificer_stage_runtime: ROOT required' >&2
    exit 2
  }
  [ -n "$dest" ] || {
    printf '%s\n' 'artificer_stage_runtime: DEST required' >&2
    exit 2
  }
  rm -rf "$dest"
  mkdir -p "$dest"

  for entry in \
    VERSION \
    LICENSE \
    README.md \
    CHANGELOG.md \
    artificer \
    run-artificer \
    install \
    uninstall \
    assets \
    docs \
    hosted-web \
    scripts \
    tools/release; do
    [ -e "$root/$entry" ] || continue
    parent=$(dirname "$entry")
    [ "$parent" = "." ] || mkdir -p "$dest/$parent"
    cp -R "$root/$entry" "$dest/$entry"
  done

  find "$dest" -name '.DS_Store' -delete
  rm -rf "$dest/hosted-web/.assay-reports" \
         "$dest/hosted-web/.playwright-browsers" \
         "$dest/hosted-web/.tmp-gui-probe-sites" \
         "$dest/hosted-web/.venv-gui-playwright" \
         "$dest/.assay-runs" \
         "$dest/.git" \
         "$dest/packaging" \
         "$dest/.github"
  chmod +x "$dest/artificer" "$dest/run-artificer" "$dest/install" "$dest/uninstall"
  find "$dest/scripts" "$dest/tools/release" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
}

wizardry_invoke_path_for_dir() {
  wiz_dir=${1-}
  [ -n "$wiz_dir" ] || return 1
  printf '%s\n' "$wiz_dir/spells/.imps/sys/invoke-wizardry"
}

wizardry_runtime_present_for_dir() {
  wiz_dir=${1-}
  [ -n "$wiz_dir" ] || return 1
  invoke_path=$(wizardry_invoke_path_for_dir "$wiz_dir")
  [ -f "$invoke_path" ]
}

wizardry_clone_repo() {
  target_dir=$1
  repo_url=$2
  branch=${3-main}
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi
  git clone --depth=1 --branch="$branch" "$repo_url" "$target_dir" >/dev/null 2>&1
}

wizardry_download_repo_tarball() {
  target_dir=$1
  repo_url=$2
  branch=${3-main}
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/artificer-wizardry.XXXXXX")
  archive="$tmp_dir/wizardry.tar.gz"
  extract_root="$tmp_dir/extract"
  mkdir -p "$extract_root"

  tar_url="$repo_url/archive/refs/heads/$branch.tar.gz"
  fetched=0
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$tar_url" -o "$archive"; then
      fetched=1
    fi
  fi
  if [ "$fetched" -ne 1 ] && command -v wget >/dev/null 2>&1; then
    if wget -qO "$archive" "$tar_url"; then
      fetched=1
    fi
  fi
  if [ "$fetched" -ne 1 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! tar -xzf "$archive" -C "$extract_root"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  extracted_dir=$(find "$extract_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$target_dir"
  mkdir -p "$(dirname "$target_dir")"
  mv "$extracted_dir" "$target_dir"
  rm -rf "$tmp_dir"
}

ensure_wizardry_installed() {
  home_dir=${1-"$HOME"}
  repo_url=${ARTIFICER_WIZARDRY_REPO_URL:-https://github.com/andersaamodt/wizardry}
  repo_branch=${ARTIFICER_WIZARDRY_REPO_BRANCH:-main}
  wiz_dir=${WIZARDRY_DIR:-$home_dir/.wizardry}

  if wizardry_runtime_present_for_dir "$wiz_dir"; then
    printf '%s\n' "$wiz_dir"
    return 0
  fi

  mkdir -p "$(dirname "$wiz_dir")"
  if [ ! -d "$wiz_dir" ] || [ ! -f "$wiz_dir/install" ]; then
    if ! wizardry_clone_repo "$wiz_dir" "$repo_url" "$repo_branch"; then
      if ! wizardry_download_repo_tarball "$wiz_dir" "$repo_url" "$repo_branch"; then
        printf '%s\n' "failed to download wizardry from $repo_url" >&2
        return 1
      fi
    fi
  fi

  if [ ! -x "$wiz_dir/install" ] && [ -f "$wiz_dir/install" ]; then
    chmod +x "$wiz_dir/install" 2>/dev/null || true
  fi
  if [ ! -f "$wiz_dir/install" ]; then
    printf '%s\n' "wizardry install script missing at $wiz_dir/install" >&2
    return 1
  fi

  WIZARDRY_INSTALL_DIR="$wiz_dir" sh "$wiz_dir/install" >/dev/null </dev/null || {
    printf '%s\n' "wizardry installer failed at $wiz_dir/install" >&2
    return 1
  }

  if ! wizardry_runtime_present_for_dir "$wiz_dir"; then
    printf '%s\n' "wizardry runtime still missing after install at $wiz_dir" >&2
    return 1
  fi
  printf '%s\n' "$wiz_dir"
}
