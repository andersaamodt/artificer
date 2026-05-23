#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"

for file in "$template" "$generated"; do
  grep -q 'private struct ProjectPathToolbarItem: View' "$file" || {
    printf '%s\n' "Native toolbar should expose the selected project path widget: $file" >&2
    exit 1
  }
  grep -q 'copySelectedProjectPath' "$file" || {
    printf '%s\n' "Native project path widget should copy the selected path: $file" >&2
    exit 1
  }
  grep -q 'openSelectedProjectFolder' "$file" || {
    printf '%s\n' "Native project path widget should open the selected folder: $file" >&2
    exit 1
  }
  grep -q 'private struct FloatingIconButton: View' "$file" || {
    printf '%s\n' "Native composer should use unlabeled floating icon buttons: $file" >&2
    exit 1
  }
  grep -q 'prominence: .accent' "$file" || {
    printf '%s\n' "Native send button should be accent-colored and icon-only: $file" >&2
    exit 1
  }
  grep -q 'accentContrastColor' "$file" || {
    printf '%s\n' "Native send button should choose a contrasting icon color: $file" >&2
    exit 1
  }
  grep -q 'private struct ComposerOptionsBar: View' "$file" || {
    printf '%s\n' "Native composer should keep LLM options visible below the prompt: $file" >&2
    exit 1
  }
  grep -q 'private struct ComposerModelMenu: View' "$file" || {
    printf '%s\n' "Native composer should expose model selection below the prompt: $file" >&2
    exit 1
  }
  grep -q 'session-set-model' "$file" || {
    printf '%s\n' "Native model picker should persist the selected thread model: $file" >&2
    exit 1
  }
  grep -q '"instant", "auto", "programming", "pentest", "security-audit", "chat", "teacher", "report", "text-perfecter", "gui-testing", "assistant"' "$file" || {
    printf '%s\n' "Native run-mode menu should match hosted Artificer modes: $file" >&2
    exit 1
  }
  grep -q '"auto", "quick", "standard", "long", "until-complete"' "$file" || {
    printf '%s\n' "Native compute menu should match hosted Artificer budgets: $file" >&2
    exit 1
  }
  if sed -n '/private struct ComposerView: View/,/private struct AttachmentChip: View/p' "$file" | grep -q 'Label("Attach"\|Label("Queue"\|Label("Send"\|Label(model.isDictating ? "Stop" : "Dictate"'; then
    printf '%s\n' "Native composer buttons should not show icon labels: $file" >&2
    exit 1
  fi
  if sed -n '/\.toolbar {/,/\.safeAreaInset/p' "$file" | grep -q 'toggleDictation'; then
    printf '%s\n' "Native toolbar should not keep dictation in the top-right toolbar: $file" >&2
    exit 1
  fi
done

grep -q 'session-set-model WORKSPACE_ID CONVERSATION_ID MODEL' "$backend" || {
  printf '%s\n' "Native backend should document session-set-model" >&2
  exit 1
}

grep -q 'api_post set_model workspace_id "$workspace_id" conversation_id "$conversation_id" model "$model_name"' "$backend" || {
  printf '%s\n' "Native backend should persist selected thread model through hosted runtime API" >&2
  exit 1
}

if "$backend" session-set-model workspace conv 'bad
model' >/tmp/artificer-native-compose-parity.out 2>/tmp/artificer-native-compose-parity.err; then
  printf '%s\n' "session-set-model should reject line-break model values" >&2
  exit 1
fi

printf '%s\n' "ok native compose parity contract"
