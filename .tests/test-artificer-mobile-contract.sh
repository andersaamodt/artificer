#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
mobile="$root/artificer-mobile"
bridge="$root/scripts/artificer-mobile-bridge.sh"
backend="$root/scripts/artificer-native-backend.sh"
template="$root/templates/macos/App.swift.template"

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

grep -q 'artificer/artificer-mobile/generated/mobile/android' "$root/.github/workflows/build-artifacts.yml" || {
  printf '%s\n' "GitHub Actions should build the Artificer Mobile Android artifact" >&2
  exit 1
}

printf '%s\n' "ok artificer mobile contract"
