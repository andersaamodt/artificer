#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"

for file in "$template" "$generated"; do
  grep -q 'TerminalDockView(model: model)' "$file" || {
    printf '%s\n' "Native terminal should dock at the bottom of the main window: $file" >&2
    exit 1
  }
  grep -q 'TapGesture(count: 2)' "$file" || {
    printf '%s\n' "Native path widget should support double-click open: $file" >&2
    exit 1
  }
  grep -q 'Opening thread...' "$file" || {
    printf '%s\n' "Native session switching should show an opening overlay: $file" >&2
    exit 1
  }
  grep -q 'AppTheme(id: "technomancer"' "$file" || {
    printf '%s\n' "Native theme menu should include hosted theme names: $file" >&2
    exit 1
  }
  grep -q 'AppTheme(id: "wizard"' "$file" || {
    printf '%s\n' "Native theme menu should include the wizard hosted theme: $file" >&2
    exit 1
  }
done

printf '%s\n' "ok native polish parity"
