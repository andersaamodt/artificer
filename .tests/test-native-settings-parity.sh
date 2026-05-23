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
  model-catalog \
  model-install-start \
  model-install-status \
  model-uninstall \
  llm-runtime-settings-get \
  llm-runtime-settings-set \
  dictation-language-get \
  dictation-prewarm-set \
  dictation-shortcuts-set \
  self-improve-run-options-set \
  self-improve-run \
  git-runtime-settings-get \
  git-runtime-settings-set
do
  grep -q "$action" "$backend" || {
    printf '%s\n' "Native backend should expose $action" >&2
    exit 1
  }
done

for file in "$template" "$generated"; do
  grep -q 'ModelCatalogRow' "$file" || {
    printf '%s\n' "Native Settings should expose curated model install rows: $file" >&2
    exit 1
  }
  grep -q 'Confirm Uninstall' "$file" || {
    printf '%s\n' "Native Settings should expose model uninstall confirmation: $file" >&2
    exit 1
  }
  grep -q 'model-install-start' "$file" || {
    printf '%s\n' "Native Settings should start model installs through the backend: $file" >&2
    exit 1
  }
  grep -q 'Run Match' "$file" || {
    printf '%s\n' "Native Self-improve settings should expose match runner controls: $file" >&2
    exit 1
  }
  grep -q 'self-improve-run-options-set' "$file" || {
    printf '%s\n' "Native Self-improve settings should persist run options through the backend: $file" >&2
    exit 1
  }
  grep -q 'sourcePlatform' "$file" || {
    printf '%s\n' "Native Self-improve settings should expose evidence source toggles: $file" >&2
    exit 1
  }
done

model_catalog_json=$("$backend" model-catalog)
printf '%s' "$model_catalog_json" | python3 -c 'import json,sys; payload=json.load(sys.stdin); assert payload["success"] is True; assert isinstance(payload.get("available"), list)' || {
  printf '%s\n' "Native backend should expose the hosted model catalog" >&2
  exit 1
}

grep -q 'XDG_STATE_HOME:-"$home/.local/state"}/wizardry/voice-recognition' "$backend" || {
  printf '%s\n' "Native backend should reuse the Wizardry voice-recognition install root" >&2
  exit 1
}

grep -q 'VOICE_RECOGNITION_ROOT_DIR="$voice_root"' "$backend" || {
  printf '%s\n' "Native backend should pass the voice-recognition root into Artificer CGI actions" >&2
  exit 1
}

grep -q 'WIZARDRY_VOICE_RECOGNITION_HF_HOME="$voice_hf_home"' "$backend" || {
  printf '%s\n' "Native backend should pass the voice-recognition model cache into Artificer CGI actions" >&2
  exit 1
}

grep -q '"$home/git/artificer-nonnative"' "$backend" || {
  printf '%s\n' "Native backend should prefer the current nonnative Artificer runtime checkout" >&2
  exit 1
}

prior_codex_work_check=$("$backend" self-improve-settings | python3 -c 'import json,sys; payload=json.load(sys.stdin); print("1" if payload.get("run_options", {}).get("codex_work_check_enabled") is True else "0")')
codex_toggle_json=$("$backend" self-improve-codex-work-check-set 1)
printf '%s' "$codex_toggle_json" | python3 -c 'import json,sys; payload=json.load(sys.stdin); assert payload["run_options"]["codex_work_check_enabled"] is True' || {
  printf '%s\n' "Codex work-check toggle should persist and return enabled state" >&2
  exit 1
}
"$backend" self-improve-codex-work-check-set "$prior_codex_work_check" >/dev/null

if "$backend" desktop-prefs-set 'bad
key' 1 >/tmp/artificer-native-settings-parity.out 2>/tmp/artificer-native-settings-parity.err; then
  printf '%s\n' "desktop preference keys with line breaks must be rejected" >&2
  exit 1
fi

printf '%s\n' "ok native settings parity contract"
