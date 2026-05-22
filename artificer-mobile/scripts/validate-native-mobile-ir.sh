#!/bin/sh

set -eu

ir_path=${1:-app-blueprint/mobile.ir.yaml}
schema_path=${2:-schemas/native-mobile-ir-v1.json}
nl='
'

case "$ir_path" in *"$nl"*) printf '%s\n' "native-mobile-ir: IR path must not contain line breaks." >&2; exit 2 ;; esac
case "$schema_path" in *"$nl"*) printf '%s\n' "native-mobile-ir: schema path must not contain line breaks." >&2; exit 2 ;; esac

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "native-mobile-ir: jq is required to validate the canonical IR." >&2
  exit 1
}

[ -f "$ir_path" ] || { printf '%s\n' "native-mobile-ir: IR file not found: $ir_path" >&2; exit 1; }
[ -f "$schema_path" ] || { printf '%s\n' "native-mobile-ir: schema file not found: $schema_path" >&2; exit 1; }

jq -e . "$ir_path" >/dev/null || {
  printf '%s\n' "native-mobile-ir: canonical IR must stay valid YAML 1.2 JSON-compatible syntax." >&2
  exit 1
}

jq -e '.version == "native-mobile-ir/v1"' "$ir_path" >/dev/null || {
  printf '%s\n' "native-mobile-ir: version must be native-mobile-ir/v1." >&2
  exit 1
}

jq -e '.app.id and .app.name and (.app.targets | length > 0) and (.app.screens | length > 0)' "$ir_path" >/dev/null || {
  printf '%s\n' "native-mobile-ir: app.id, app.name, app.targets, and app.screens are required." >&2
  exit 1
}

jq -e '.app.targets | all(. == "android" or . == "ios")' "$ir_path" >/dev/null || {
  printf '%s\n' "native-mobile-ir: app.targets must contain android, ios, or both." >&2
  exit 1
}

jq -e '
  [
    .app.id,
    .app.name,
    (.app.screens[]?.id),
    (.app.screens[]?.title)
  ] | all(type == "string" and (test("[\\r\\n]") | not))
' "$ir_path" >/dev/null || {
  printf '%s\n' "native-mobile-ir: app and screen text must be render-safe." >&2
  exit 1
}

printf '%s\n' "native-mobile-ir: ok"
