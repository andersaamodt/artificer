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
  if sed -n '/private struct AutomationsDetailView: View/,/private struct AutomationCreatePane: View/p' "$file" | grep -q 'Voice Commands\|Edit Voice Commands\|VoiceCommandsOverviewPane'; then
    printf '%s\n' "Automations panel should not expose voice command editing: $file" >&2
    exit 1
  fi
  grep -q 'VoiceControlPreferencesTab(model: model)' "$file" || {
    printf '%s\n' "Preferences should expose a dedicated Voice Control tab: $file" >&2
    exit 1
  }
  grep -q 'Label("Voice Control", systemImage: "waveform.circle")' "$file" || {
    printf '%s\n' "Preferences should label the dedicated voice settings tab clearly: $file" >&2
    exit 1
  }
  grep -q 'Save Local Actions' "$file" || {
    printf '%s\n' "Preferences should include a clear save control for local voice actions: $file" >&2
    exit 1
  }
  grep -q 'Play sound when command is recognized' "$file" || {
    printf '%s\n' "Preferences should expose recognized-command sound feedback: $file" >&2
    exit 1
  }
  grep -q 'voice_automation_sound' "$file" || {
    printf '%s\n' "Native UI should persist recognized-command sound feedback: $file" >&2
    exit 1
  }
  grep -q 'Use built-in Mac voice commands' "$file" || {
    printf '%s\n' "Native UI should expose built-in voice commands: $file" >&2
    exit 1
  }
  grep -q 'Allow dictation into the frontmost app' "$file" || {
    printf '%s\n' "Native UI should expose voice dictation into apps: $file" >&2
    exit 1
  }
  grep -q 'voice_builtin_commands' "$file" || {
    printf '%s\n' "Native UI should persist built-in voice command preference: $file" >&2
    exit 1
  }
  grep -q 'voice_dictation_commands' "$file" || {
    printf '%s\n' "Native UI should persist voice dictation preference: $file" >&2
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

grep -q 'voice_automation_sound' "$backend" || {
  printf '%s\n' "Native backend should persist recognized-command sound feedback" >&2
  exit 1
}

grep -q 'voice_builtin_commands' "$backend" || {
  printf '%s\n' "Native backend should persist built-in voice command preference" >&2
  exit 1
}

grep -q 'voice_dictation_commands' "$backend" || {
  printf '%s\n' "Native backend should persist voice dictation preference" >&2
  exit 1
}

grep -q 'play_recognition_sound' "$root/scripts/artificer-voice-automations.sh" || {
  printf '%s\n' "Voice listener should play feedback when a command is recognized" >&2
  exit 1
}

grep -q 'run_builtin_action' "$root/scripts/artificer-voice-automations.sh" || {
  printf '%s\n' "Voice listener should dispatch built-in macOS-style commands" >&2
  exit 1
}

grep -q 'read_notification' "$root/scripts/artificer-voice-builtins.sh" || {
  printf '%s\n' "Voice built-ins should support reading the current notification" >&2
  exit 1
}

grep -q 'start_dictation' "$root/scripts/artificer-voice-builtins.sh" || {
  printf '%s\n' "Voice built-ins should support dictation mode" >&2
  exit 1
}

grep -q 'syncVoiceAutomationLoop' "$template" || {
  printf '%s\n' "Native app should host the voice automation loop for microphone permission" >&2
  exit 1
}

grep -A3 'launchModel.loadDesktopPrefsForLaunch()' "$template" | grep -q 'launchModel.syncVoiceAutomationLoop()' || {
  printf '%s\n' "Native app should start voice automations during app launch, not only after a window opens" >&2
  exit 1
}

grep -q 'AVAudioRecorder' "$template" || {
  printf '%s\n' "Native app should capture voice automation audio itself" >&2
  exit 1
}

grep -q 'dictation-transcribe-file' "$template" || {
  printf '%s\n' "Native app should send captured voice automation audio to local transcription" >&2
  exit 1
}

grep -q 'processVoiceAutomationAudioDetached' "$template" || {
  printf '%s\n' "Native voice loop should process transcription without blocking the next capture" >&2
  exit 1
}

grep -q 'native transcription failed:' "$template" || {
  printf '%s\n' "Native voice loop should log transcription failures" >&2
  exit 1
}

grep -q 'app-hosted' "$backend" || {
  printf '%s\n' "Native backend should avoid launchd-hosted voice capture" >&2
  exit 1
}

empty_audio=$(mktemp "${TMPDIR:-/tmp}/artificer-empty-audio.XXXXXX")
transcribe_empty_out=$("$backend" dictation-transcribe-file "$empty_audio" auto)
rm -f "$empty_audio"
printf '%s\n' "$transcribe_empty_out" | grep -q '"success":false' || {
  printf '%s\n' "dictation-transcribe-file should return JSON for empty audio" >&2
  exit 1
}
printf '%s\n' "$transcribe_empty_out" | grep -q 'No audio was captured' || {
  printf '%s\n' "dictation-transcribe-file should report empty audio precisely" >&2
  exit 1
}

if grep -qi "$personal_display_pattern" "$backend" "$root/scripts/artificer-voice-automations.sh"; then
  printf '%s\n' "Native backend/listener must not hardcode personal display actions" >&2
  exit 1
fi

printf '%s\n' "ok native automations panel contract"
