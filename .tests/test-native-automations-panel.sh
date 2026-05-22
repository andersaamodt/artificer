#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"
blueprint="$root/app-blueprint/app.ir.yaml"

personal_display_pattern='main'' screen\|main-''screen'

for file in "$template" "$generated"; do
  grep -q 'AutomationsDetailView(model: model)' "$file" || {
    printf '%s\n' "Automations should render in the main detail panel: $file" >&2
    exit 1
  }
  grep -q 'Task { await model.selectAutomationsPanel() }' "$file" || {
    printf '%s\n' "Sidebar Automations row should select the panel: $file" >&2
    exit 1
  }
  grep -q 'private struct AutomationCreatePane: View' "$file" || {
    printf '%s\n' "Automations panel should include an add form: $file" >&2
    exit 1
  }
  grep -q 'private struct AutomationListPane: View' "$file" || {
    printf '%s\n' "Automations panel should include the automation list: $file" >&2
    exit 1
  }
  grep -q 'func createAutomationFromDraft() async' "$file" || {
    printf '%s\n' "Automations panel should create automations through the model: $file" >&2
    exit 1
  }
  grep -q 'VoiceCommandsOverviewPane(model: model)' "$file" || {
    printf '%s\n' "Automations panel should expose voice commands: $file" >&2
    exit 1
  }
  grep -q 'Edit Voice Commands' "$file" || {
    printf '%s\n' "Automations panel should point users to voice command editing: $file" >&2
    exit 1
  }
  grep -q 'Save Local Actions' "$file" || {
    printf '%s\n' "Preferences should include a clear save control for local voice actions: $file" >&2
    exit 1
  }
  grep -q 'voice_local_action_1_phrases' "$file" || {
    printf '%s\n' "Native UI should load and save local action voice phrases: $file" >&2
    exit 1
  }
  grep -q 'voice_local_action_1_command' "$file" || {
    printf '%s\n' "Native UI should load and save local action commands: $file" >&2
    exit 1
  }
  grep -q 'voiceLocalAction2Phrases' "$file" || {
    printf '%s\n' "Native UI should expose a second local action slot: $file" >&2
    exit 1
  }
  if grep -qi "$personal_display_pattern" "$file"; then
    printf '%s\n' "Native voice automation UI must not hardcode personal display actions: $file" >&2
    exit 1
  fi
done

for file in "$template" "$generated" "$blueprint"; do
  if grep -q 'Run Tick Now' "$file"; then
    printf '%s\n' "User-facing automation controls should not say Run Tick Now: $file" >&2
    exit 1
  fi
done

grep -q 'Run Due Automations' "$template" || {
  printf '%s\n' "Template should use a clear run-due-automations label" >&2
  exit 1
}

grep -q 'Run Due Automations' "$blueprint" || {
  printf '%s\n' "Blueprint should use a clear run-due-automations label" >&2
  exit 1
}

if sed -n '/private struct AutomationSidebarRow: View/,/private struct OpenPreferencesButton: View/p' "$template" | grep -q 'openWindow(id: "preferences")'; then
  printf '%s\n' "Sidebar Automations row must not open Preferences" >&2
  exit 1
fi

grep -q 'automation-upsert WORKSPACE_ID CONVERSATION_ID NAME PROMPT SCHEDULE_KIND SCHEDULE_VALUE ENABLED ALLOW_SELF_RESCHEDULE RUN_MODE COMPUTE_BUDGET COMMAND_EXEC_MODE PERMISSION_MODE PROGRAMMER_REVIEW PROGRAMMER_REVIEW_ROUNDS NEXT_RUN' "$backend" || {
  printf '%s\n' "Native backend should expose automation-upsert" >&2
  exit 1
}

grep -q 'runtime_client automation upsert' "$backend" || {
  printf '%s\n' "Native backend should call runtime automation upsert" >&2
  exit 1
}

grep -q 'desktop-value-set KEY VALUE' "$backend" || {
  printf '%s\n' "Native backend should expose text desktop preference updates" >&2
  exit 1
}

grep -q 'voice_local_action_1_phrases' "$backend" || {
  printf '%s\n' "Native backend should persist local action phrases" >&2
  exit 1
}

grep -q 'voice_local_action_1_command' "$backend" || {
  printf '%s\n' "Native backend should persist local action commands" >&2
  exit 1
}

if grep -qi "$personal_display_pattern" "$backend" "$root/scripts/artificer-voice-automations.sh"; then
  printf '%s\n' "Native backend/listener must not hardcode personal display actions" >&2
  exit 1
fi

printf '%s\n' "ok native automations panel contract"
