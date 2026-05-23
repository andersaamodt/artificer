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
  grep -q 'VoiceControlPreferencesTab(model: model)' "$file" || {
    printf '%s\n' "Native Settings should expose voice controls in their own tab: $file" >&2
    exit 1
  }
  grep -q 'ApprovalRulesPreferencesTab(model: model)' "$file" || {
    printf '%s\n' "Native Settings should expose command approval rules in their own tab: $file" >&2
    exit 1
  }
  grep -q 'CommandRulesGroup(title: "Global defaults"' "$file" || {
    printf '%s\n' "Native Settings should show global command approval defaults: $file" >&2
    exit 1
  }
  grep -q 'CommandRulesGroup(title: "Remembered project rules"' "$file" || {
    printf '%s\n' "Native Settings should show remembered project command rules: $file" >&2
    exit 1
  }
  grep -q 'Clear Remembered' "$file" || {
    printf '%s\n' "Native Settings should clear remembered command approval rules: $file" >&2
    exit 1
  }
  grep -q 'command-rules-list' "$file" || {
    printf '%s\n' "Native Settings should load command approval rules through the backend: $file" >&2
    exit 1
  }
  grep -q 'Use built-in Mac voice commands' "$file" || {
    printf '%s\n' "Native Settings should expose built-in Mac voice commands: $file" >&2
    exit 1
  }
  grep -q 'Allow dictation into the frontmost app' "$file" || {
    printf '%s\n' "Native Settings should expose voice dictation into apps: $file" >&2
    exit 1
  }
  if sed -n '/private struct AutomationsPreferencesTab: View/,/private struct VoiceControlPreferencesTab: View/p' "$file" | grep -q 'Voice automations\|Save Local Actions'; then
    printf '%s\n' "Native Settings should not bury voice command editing in Automations: $file" >&2
    exit 1
  fi
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
  git-runtime-settings-set \
  command-rules-list \
  command-rules-clear \
  command-rule-delete
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

rules_tmp=$(mktemp -d "${TMPDIR:-/tmp}/artificer-native-rules-test.XXXXXX")
cleanup_rules_tmp() {
  rm -rf "$rules_tmp"
}
trap cleanup_rules_tmp EXIT INT TERM
mkdir -p "$rules_tmp/home" "$rules_tmp/state" "$rules_tmp/config" "$rules_tmp/project"

rules_backend() {
  HOME="$rules_tmp/home" \
    XDG_STATE_HOME="$rules_tmp/state" \
    XDG_CONFIG_HOME="$rules_tmp/config" \
    ARTIFICER_STATE_ROOT="$rules_tmp/state/artificer" \
    ARTIFICER_CORE_ROOT="$root" \
    "$backend" "$@"
}

rules_backend project-add "$rules_tmp/project" "Native Rules Contract" ask-all > "$rules_tmp/project.json"
rules_workspace_id=$(python3 - "$rules_tmp/project.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
workspace = payload.get("workspace") or {}
print(workspace.get("id") or payload.get("workspace_id") or payload.get("id") or "")
PY
)
[ -n "$rules_workspace_id" ] || {
  printf '%s\n' "Native backend command rules contract could not create an isolated workspace" >&2
  exit 1
}

rules_backend session-create "$rules_workspace_id" "Rules Contract" default > "$rules_tmp/session.json"
rules_conversation_id=$(python3 - "$rules_tmp/session.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
session = payload.get("session") or payload.get("conversation") or {}
print(session.get("id") or payload.get("conversation_id") or payload.get("id") or "")
PY
)
[ -n "$rules_conversation_id" ] || {
  printf '%s\n' "Native backend command rules contract could not create an isolated session" >&2
  exit 1
}

rules_backend approval-answer "$rules_workspace_id" "$rules_conversation_id" deny remember exact "printf contract-smoke" "printf contract-smoke" > "$rules_tmp/answer.json"
rules_backend command-rules-list "$rules_workspace_id" > "$rules_tmp/list.json"
python3 - "$rules_tmp/list.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload.get("success") is True, payload
assert isinstance(payload.get("global_defaults"), list), payload
remembered = payload.get("remembered") or []
assert any(rule.get("decision") == "deny" and rule.get("pattern") == "printf contract-smoke" for rule in remembered), payload
PY

rules_backend command-rule-delete "$rules_workspace_id" remember 1 > "$rules_tmp/delete.json"
python3 - "$rules_tmp/delete.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload.get("success") is True and payload.get("deleted") is True, payload
PY

rules_backend command-rules-list "$rules_workspace_id" > "$rules_tmp/list-after-delete.json"
python3 - "$rules_tmp/list-after-delete.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload.get("success") is True, payload
assert not any(rule.get("pattern") == "printf contract-smoke" for rule in (payload.get("remembered") or [])), payload
PY

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
