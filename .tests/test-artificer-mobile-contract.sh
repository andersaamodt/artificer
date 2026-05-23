#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
mobile="$root/artificer-mobile"
bridge="$root/scripts/artificer-mobile-bridge.sh"
backend="$root/scripts/artificer-native-backend.sh"
template="$root/templates/macos/App.swift.template"
renderer="$mobile/scripts/render-native-mobile.sh"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/artificer-mobile-contract.XXXXXX")
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

sh "$mobile/scripts/validate-native-mobile-ir.sh" "$mobile/app-blueprint/mobile.ir.yaml" "$mobile/schemas/native-mobile-ir-v1.json" >/dev/null

grep -q 'MobilePreferencesTab(model: model)' "$template" || {
  printf '%s\n' "desktop Preferences should include a Mobile tab" >&2
  exit 1
}

grep -q 'mobile-status' "$backend" || {
  printf '%s\n' "native backend should expose mobile bridge status" >&2
  exit 1
}

grep -q '127.0.0.1' "$bridge" || {
  printf '%s\n' "mobile bridge should default to localhost-only access" >&2
  exit 1
}

grep -q 'X-Artificer-Mobile-Token' "$bridge" || {
  printf '%s\n' "mobile bridge should require pairing-token auth" >&2
  exit 1
}

grep -q 'allow_execute' "$bridge" || {
  printf '%s\n' "mobile bridge should gate execution permission" >&2
  exit 1
}

grep -q 'path_exists' "$bridge" || {
  printf '%s\n' "mobile bridge should filter stale workspaces before mobile list rendering" >&2
  exit 1
}

XDG_CONFIG_HOME="$tmp_dir/config" XDG_STATE_HOME="$tmp_dir/state" sh "$bridge" set port 18765 >/dev/null
XDG_CONFIG_HOME="$tmp_dir/config" XDG_STATE_HOME="$tmp_dir/state" sh "$bridge" set bind_host 127.0.0.1 >/dev/null
XDG_CONFIG_HOME="$tmp_dir/config" XDG_STATE_HOME="$tmp_dir/state" sh "$bridge" status | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["port"] == "18765", p; assert p["bind_host"] == "127.0.0.1", p' || {
  printf '%s\n' "mobile bridge settings should round-trip through temp config" >&2
  exit 1
}

grep -q 'parsed.path == "/tree"' "$bridge" || {
  printf '%s\n' "mobile bridge should expose a full folder/chat tree endpoint" >&2
  exit 1
}

grep -q 'Search folders and chats' "$renderer" || {
  printf '%s\n' "mobile app should include folder/chat search" >&2
  exit 1
}

grep -q 'contextWindow' "$renderer" || {
  printf '%s\n' "Android mobile UI should render the runtime context window" >&2
  exit 1
}

grep -q 'ContextWindow' "$renderer" || {
  printf '%s\n' "iOS mobile UI should render the runtime context window" >&2
  exit 1
}

grep -q 'expandedProjectIds' "$renderer" || {
  printf '%s\n' "Android mobile UI should support expandable folder hierarchy" >&2
  exit 1
}

grep -q 'ProjectDisclosure' "$renderer" || {
  printf '%s\n' "iOS mobile UI should support expandable folder hierarchy" >&2
  exit 1
}

grep -q 'queueText' "$renderer" || {
  printf '%s\n' "Android mobile UI should show queue/running state" >&2
  exit 1
}

grep -q 'queueLabel' "$renderer" || {
  printf '%s\n' "iOS mobile UI should show queue/running state" >&2
  exit 1
}

grep -q 'No folders' "$renderer" || {
  printf '%s\n' "mobile app should include empty folder states" >&2
  exit 1
}

grep -q 'Refresh' "$renderer" || {
  printf '%s\n' "mobile app should include explicit refresh behavior" >&2
  exit 1
}

grep -q 'autoConnectIfPossible' "$renderer" || {
  printf '%s\n' "iOS mobile app should auto-connect when pairing details are saved" >&2
  exit 1
}

grep -q 'endpoint.trim().length() > 0 && token.trim().length() > 0' "$renderer" || {
  printf '%s\n' "Android mobile app should auto-connect when pairing details are saved" >&2
  exit 1
}

grep -q 'https://api.github.com/repos/andersaamodt/artificer/releases/latest' "$renderer" || {
  printf '%s\n' "mobile app should check GitHub releases for updates" >&2
  exit 1
}

grep -q 'REQUEST_INSTALL_PACKAGES' "$renderer" || {
  printf '%s\n' "Android mobile app should request package installer handoff for direct updates" >&2
  exit 1
}

grep -q 'ACTION_INSTALL_PACKAGE' "$renderer" || {
  printf '%s\n' "Android mobile app should launch the platform package installer for downloaded updates" >&2
  exit 1
}

grep -q 'MY_PACKAGE_REPLACED' "$renderer" || {
  printf '%s\n' "Android mobile app should relaunch after package replacement" >&2
  exit 1
}

grep -q 'Update' "$renderer" || {
  printf '%s\n' "mobile app should expose the blue Update pill/action when an update is available" >&2
  exit 1
}

grep -q 'ARTIFICER_MOBILE_ANDROID_KEYSTORE' "$mobile/generated/mobile/android/app/build.gradle" 2>/dev/null || grep -q 'ARTIFICER_MOBILE_ANDROID_KEYSTORE' "$renderer" || {
  printf '%s\n' "Android mobile release builds should support stable signing for self-updates" >&2
  exit 1
}

grep -q 'folderErrors' "$renderer" || {
  printf '%s\n' "mobile app should expose per-folder chat load retry state" >&2
  exit 1
}

grep -q 'isSending' "$renderer" || {
  printf '%s\n' "iOS mobile app should show send progress and prevent duplicate sends" >&2
  exit 1
}

grep -q 'artificer/artificer-mobile/generated/mobile/android' "$root/.github/workflows/build-artifacts.yml" || {
  printf '%s\n' "GitHub Actions should build the Artificer Mobile Android artifact" >&2
  exit 1
}

grep -q 'softprops/action-gh-release' "$root/.github/workflows/build-artifacts.yml" || {
  printf '%s\n' "GitHub Actions should attach mobile artifacts to tagged GitHub releases" >&2
  exit 1
}

printf '%s\n' "ok artificer mobile contract"
