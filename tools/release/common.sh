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
