#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

publish_surface_files='
.github/workflows/build-artificer.yml
tools/release/build-release-bundle.sh
tools/release/build-macos-app.sh
tools/release/build-release-artifacts.sh
tools/release/install-artificer.sh
tools/release/uninstall-artificer.sh
tools/release/audit-publish-surface.sh
'

publish_targets_blob=''
for rel_path in $publish_surface_files; do
  abs_path="$repo_root/$rel_path"
  [ -f "$abs_path" ] || {
    printf '%s\n' "missing publish-surface file: $rel_path" >&2
    exit 1
  }
  publish_targets_blob=$(
    {
      printf '%s\n' "$publish_targets_blob"
      printf '%s\n' "$abs_path"
    } | sed '/^$/d'
  )
done

if printf '%s\n' "$publish_targets_blob" | xargs grep -nE 'github\.com[:/][^/[:space:]]+/artificer(\.git)?' >/dev/null 2>&1; then
  printf '%s\n' "publish surface must not hardcode a GitHub owner/repo target for artificer" >&2
  printf '%s\n' "$publish_targets_blob" | xargs grep -nE 'github\.com[:/][^/[:space:]]+/artificer(\.git)?' >&2 || true
  exit 1
fi

if printf '%s\n' "$publish_targets_blob" | xargs grep -n 'andersaamodt/artificer' >/dev/null 2>&1; then
  printf '%s\n' "publish surface must not hardcode personal repository ownership" >&2
  printf '%s\n' "$publish_targets_blob" | xargs grep -n 'andersaamodt/artificer' >&2 || true
  exit 1
fi

workflow_file="$repo_root/.github/workflows/build-artificer.yml"
if grep -Eq '^[[:space:]]*repository:[[:space:]]*' "$workflow_file"; then
  printf '%s\n' "release workflow should not pin an explicit repository target" >&2
  exit 1
fi

if ! grep -q 'softprops/action-gh-release@' "$workflow_file"; then
  printf '%s\n' "release workflow must keep an explicit GitHub release publish action" >&2
  exit 1
fi

printf '%s\n' "ok publish surface defaults are neutral (no hardcoded Artificer publish owner/repo)"
