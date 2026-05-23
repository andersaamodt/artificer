#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
template="$root/templates/macos/App.swift.template"
generated="$root/generated/macos/Sources/App/App.swift"
backend="$root/scripts/artificer-native-backend.sh"
runtime_client="$root/hosted-web/scripts/artificer-runtime-client"
control_sessions="$root/hosted-web/cgi/actions/control_plane_sessions.sh"
queue_enqueue="$root/hosted-web/cgi/actions/queue_enqueue.sh"
queue_take="$root/hosted-web/cgi/actions/queue_take.sh"
queue_lib="$root/hosted-web/cgi/lib/runtime/40a-core-queue.sh"
run_part="$root/hosted-web/cgi/actions/run_parts/run-part-001.sh"

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
  grep -q '"low", "medium", "high", "extra-high"' "$file" || {
    printf '%s\n' "Native reasoning menu should match hosted Artificer reasoning depths: $file" >&2
    exit 1
  }
  grep -q 'ComposerOptionMenu(systemImage: "brain.head.profile", title: "Reasoning depth"' "$file" || {
    printf '%s\n' "Native composer should expose reasoning depth below the prompt: $file" >&2
    exit 1
  }
  grep -q 'reasoningEffort' "$file" || {
    printf '%s\n' "Native composer should pass reasoning depth through message enqueue: $file" >&2
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

grep -q 'session-message WORKSPACE_ID CONVERSATION_ID PROMPT RUN_MODE COMPUTE_BUDGET COMMAND_EXEC_MODE PERMISSION_MODE PROGRAMMER_REVIEW PROGRAMMER_REVIEW_ROUNDS REFLEXIVE_KNOWLEDGE SELF_ACTUATION \[ATTACHMENT_IDS\] \[REASONING_EFFORT\]' "$backend" || {
  printf '%s\n' "Native backend should document session-message reasoning effort" >&2
  exit 1
}

grep -q -- '--reasoning-effort "$reasoning_effort"' "$backend" || {
  printf '%s\n' "Native backend should pass reasoning effort to the runtime client" >&2
  exit 1
}

grep -q -- '--reasoning-effort <low|medium|high|extra-high>' "$runtime_client" || {
  printf '%s\n' "Runtime client should document reasoning effort" >&2
  exit 1
}

grep -q '"reasoning_effort" "$reasoning_effort"' "$control_sessions" || {
  printf '%s\n' "Control-plane sessions should forward reasoning effort to queue enqueue" >&2
  exit 1
}

grep -q 'reasoning_effort_raw=$(trim "$(param "reasoning_effort")")' "$queue_enqueue" || {
  printf '%s\n' "Queue enqueue should read reasoning effort" >&2
  exit 1
}

grep -q 'queue_meta_reasoning_effort_from_file' "$queue_lib" || {
  printf '%s\n' "Queue metadata should persist reasoning effort" >&2
  exit 1
}

grep -q '"reasoning_effort":"%s"' "$queue_take" || {
  printf '%s\n' "Queue take should expose reasoning effort" >&2
  exit 1
}

grep -q 'queue_reasoning_effort_override=$(queue_meta_reasoning_effort_from_file' "$run_part" || {
  printf '%s\n' "Run should restore reasoning effort from queue metadata" >&2
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
