#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/artificer-voice-builtins-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT INT HUP TERM

home_dir="$tmp_dir/home"
bin_dir="$tmp_dir/bin"
log_file="$tmp_dir/actions.log"
clipboard_file="$tmp_dir/clipboard.txt"
mkdir -p "$home_dir/.config/artificer" "$bin_dir"
: > "$log_file"
: > "$clipboard_file"

cat > "$home_dir/.config/artificer/ui-prefs.env" <<'PREFS'
voice_automations=1
voice_automation_sound=0
voice_builtin_commands=1
voice_dictation_commands=1
voice_automation_llm_prompts=0
voice_automation_llm_actions=0
PREFS

cat > "$bin_dir/open" <<EOF
#!/bin/sh
printf 'open %s\n' "\$*" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/osascript" <<EOF
#!/bin/sh
script_text=''
if [ "\${1-}" = "-" ] || [ "\$#" -eq 0 ]; then
  script_text=\$(cat 2>/dev/null || true)
fi
printf 'osascript %s\n' "\$*" >> "$log_file"
if printf '%s %s\n' "\$*" "\$script_text" | grep -q 'Finder'; then
  printf '%s\n' '0, 0, 900, 900'
elif [ -n "\${ARTIFICER_STUB_NOTIFICATION-}" ]; then
  printf '%s\n' "\$ARTIFICER_STUB_NOTIFICATION"
fi
exit 0
EOF

cat > "$bin_dir/say" <<EOF
#!/bin/sh
printf 'say %s\n' "\$*" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/afplay" <<EOF
#!/bin/sh
printf 'afplay %s\n' "\$*" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/pmset" <<EOF
#!/bin/sh
printf 'pmset %s\n' "\$*" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/cliclick" <<EOF
#!/bin/sh
printf 'cliclick %s\n' "\$*" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/pbcopy" <<EOF
#!/bin/sh
cat > "$clipboard_file"
printf 'pbcopy %s\n' "\$(cat "$clipboard_file")" >> "$log_file"
exit 0
EOF

cat > "$bin_dir/pbpaste" <<EOF
#!/bin/sh
cat "$clipboard_file"
exit 0
EOF

cat > "$bin_dir/local-latency-action" <<EOF
#!/bin/sh
sleep 0.05
printf '%s\n' 'local-action' >> "$log_file"
exit 0
EOF

chmod +x "$bin_dir"/*

run_voice() {
  HOME="$home_dir" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  ARTIFICER_NATIVE_STATE_ROOT="$tmp_dir/state" \
  PATH="$bin_dir:/usr/bin:/bin" \
  sh "$repo_root/scripts/artificer-voice-automations.sh" handle-text "$1"
}

dictation_active() {
  HOME="$home_dir" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  ARTIFICER_NATIVE_STATE_ROOT="$tmp_dir/state" \
  PATH="$bin_dir:/usr/bin:/bin" \
  sh "$repo_root/scripts/artificer-voice-builtins.sh" dictation-active >/dev/null 2>&1
}

run_voice "switch to Safari" | grep -q '"status":"triggered"' || {
  printf '%s\n' "switch-to app phrase should trigger a built-in command" >&2
  exit 1
}
grep -q 'open -a safari' "$log_file" || {
  printf '%s\n' "switch-to app phrase should activate the named app" >&2
  exit 1
}

run_voice "show grid" >/dev/null
run_voice "click 5" >/dev/null
grep -q 'cliclick c:450,450' "$log_file" || {
  printf '%s\n' "show grid followed by click 5 should click the center grid cell" >&2
  exit 1
}

ARTIFICER_STUB_NOTIFICATION='Messages
Alice
Dinner is ready' run_voice "read it" >/dev/null
run_voice "read it" >/dev/null
grep -q 'say Messages. Alice. Dinner is ready' "$log_file" || {
  printf '%s\n' "read it should read the cached notification text" >&2
  exit 1
}

run_voice "start dictation" >/dev/null
run_voice "hello comma world" >/dev/null
run_voice "stop dictation" >/dev/null
grep -q 'pbcopy hello, world' "$log_file" || {
  printf '%s\n' "dictation mode should type normalized dictated text" >&2
  exit 1
}

run_voice "start listening" >/dev/null
run_voice "listening phrase period" >/dev/null
run_voice "show grid" >/dev/null
run_voice "click 5" >/dev/null
run_voice "stop listening" >/dev/null
grep -q 'pbcopy listening phrase.' "$log_file" || {
  printf '%s\n' "start listening should enter dictation mode until stop listening" >&2
  exit 1
}
grep -q 'cliclick c:450,450' "$log_file" || {
  printf '%s\n' "show grid and click should still work while dictation mode is active" >&2
  exit 1
}

run_voice "dictate" >/dev/null
dictation_active || {
  printf '%s\n' "bare dictate should start dictation mode" >&2
  exit 1
}
run_voice "stop listening" >/dev/null
run_voice "dictate here is a sentence" >/dev/null
dictation_active || {
  printf '%s\n' "dictate with inline text should leave dictation mode active" >&2
  exit 1
}
run_voice "and it continues period" >/dev/null
run_voice "stop dictating" >/dev/null
if dictation_active; then
  printf '%s\n' "stop dictating should leave dictation mode" >&2
  exit 1
fi
grep -q 'pbcopy here is a sentence' "$log_file" || {
  printf '%s\n' "dictate with inline text should type the inline phrase immediately" >&2
  exit 1
}
grep -q 'pbcopy and it continues.' "$log_file" || {
  printf '%s\n' "dictate with inline text should keep dictating follow-on phrases" >&2
  exit 1
}

cat > "$home_dir/.config/artificer/ui-prefs.env" <<'EOF'
voice_automations=1
voice_automation_sound=1
voice_builtin_commands=1
voice_dictation_commands=1
voice_automation_llm_prompts=0
voice_automation_llm_actions=0
EOF
: > "$log_file"
run_voice "start listening" >/dev/null
: > "$log_file"
run_voice "background fan word" >/dev/null
sleep 0.1
if grep -q '^afplay ' "$log_file"; then
  printf '%s\n' "ordinary dictated text should not play the recognized-command sound" >&2
  exit 1
fi
run_voice "stop listening" >/dev/null

unmatched_json=$(run_voice "you")
printf '%s\n' "$unmatched_json" | grep -q '"status":"listening"' || {
  printf '%s\n' "unmatched phrases should leave voice automations listening" >&2
  exit 1
}
printf '%s\n' "$unmatched_json" | grep -q 'No voice automation phrase matched' || {
  printf '%s\n' "unmatched phrases should not report a built-in command failure" >&2
  exit 1
}
printf '%s\n' "$unmatched_json" | grep -q '"last_action":"unmatched"' || {
  printf '%s\n' "unmatched phrases should not keep the previous built-in action label" >&2
  exit 1
}

cat > "$home_dir/.config/artificer/ui-prefs.env" <<EOF
voice_automations=1
voice_automation_sound=1
voice_builtin_commands=1
voice_dictation_commands=1
voice_automation_llm_prompts=0
voice_automation_llm_actions=0
voice_local_action_1_name=Latency check
voice_local_action_1_command=$bin_dir/local-latency-action
voice_local_action_1_phrases=latency check
EOF
: > "$log_file"
run_voice "latency check" >/dev/null
sleep 0.1
first_feedback_lines=$(grep -E '^(afplay|local-action)' "$log_file" | head -2 | tr '\n' ' ')
case "$first_feedback_lines" in
  afplay*" local-action "*) ;;
  *)
    printf '%s\n' "recognized-command sound should start before a matched local action runs" >&2
    printf '%s\n' "$first_feedback_lines" >&2
    exit 1
    ;;
esac

grep -q 'voice_builtin_commands' "$repo_root/scripts/artificer-native-backend.sh" || {
  printf '%s\n' "native backend should persist built-in voice command preference" >&2
  exit 1
}

grep -q 'voice_dictation_commands' "$repo_root/templates/macos/App.swift.template" || {
  printf '%s\n' "native Preferences should expose voice dictation preference" >&2
  exit 1
}

grep -q 'voiceAutomationCaptureSeconds: TimeInterval = 2.2' "$repo_root/templates/macos/App.swift.template" || {
  printf '%s\n' "native voice listener should use shorter capture windows for lower command latency" >&2
  exit 1
}

grep -q 'voiceAutomationLoopPauseNanoseconds: UInt64 = 80_000_000' "$repo_root/templates/macos/App.swift.template" || {
  printf '%s\n' "native voice listener should leave only a short gap between capture windows" >&2
  exit 1
}

grep -q 'waitForVoiceAutomationCaptureWindow' "$repo_root/templates/macos/App.swift.template" || {
  printf '%s\n' "native voice listener should stop capture early after speech falls silent" >&2
  exit 1
}

grep -q 'recorder.isMeteringEnabled = true' "$repo_root/templates/macos/App.swift.template" || {
  printf '%s\n' "native voice listener should enable metering for speech-end latency tuning" >&2
  exit 1
}

printf '%s\n' "ok voice built-ins"
