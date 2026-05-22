#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'Generate compact thread titles' "$file" || {
    printf '%s\n' "Native Settings should restore smart thread title control: $file" >&2
    exit 1
  }
  grep -q 'Keep dictation warm' "$file" || {
    printf '%s\n' "Native Settings should restore dictation prewarm control: $file" >&2
    exit 1
  }
  grep -q 'Hold-to-talk' "$file" || {
    printf '%s\n' "Native Settings should restore dictation shortcut controls: $file" >&2
    exit 1
  }
  grep -q 'GitPreferencesTab(model: model)' "$file" || {
    printf '%s\n' "Native Settings should restore Git policy controls: $file" >&2
    exit 1
  }
  grep -q 'Allow self-reschedule' "$file" || {
    printf '%s\n' "Native automation creation should restore self-reschedule control: $file" >&2
    exit 1
  }
  grep -q 'automationDraftRunMode' "$file" || {
    printf '%s\n' "Native automation creation should restore run policy controls: $file" >&2
    exit 1
  }
done

for action in \
  models \
  llm-runtime-settings-get \
  llm-runtime-settings-set \
  dictation-language-get \
  dictation-prewarm-set \
  dictation-shortcuts-set \
  git-runtime-settings-get \
  git-runtime-settings-set
do
  grep -q "$action" "$backend" || {
    printf '%s\n' "Native backend should expose $action" >&2
    exit 1
  }
done

if "$backend" desktop-prefs-set 'bad
key' 1 >/tmp/artificer-native-settings-parity.out 2>/tmp/artificer-native-settings-parity.err; then
  printf '%s\n' "desktop preference keys with line breaks must be rejected" >&2
  exit 1
fi

printf '%s\n' "ok native settings parity contract"
