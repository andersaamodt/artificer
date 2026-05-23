#!/bin/sh

set -eu

home=${HOME:?}
state_root=${ARTIFICER_NATIVE_STATE_ROOT:-${XDG_STATE_HOME:-"$home/.local/state"}/artificer-native}
state_dir=${ARTIFICER_VOICE_STATE_DIR:-"$state_root/voice-automations"}
numbers_file="$state_dir/numbered-targets.tsv"
dictation_file="$state_dir/dictation-mode"
last_notification_file="$state_dir/last-notification.txt"
PATH="${PATH:-/usr/bin:/bin}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

usage() {
  cat <<'USAGE'
Usage: artificer-voice-builtins.sh handle PHRASE
       artificer-voice-builtins.sh cache-notification
       artificer-voice-builtins.sh dictation-active

Handles Artificer's built-in macOS-style voice commands.
USAGE
}

ensure_state_dir() {
  mkdir -p "$state_dir"
}

normalize_phrase() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1] if len(sys.argv) > 1 else ""
text = text.lower()
text = re.sub(r"[^a-z0-9 ]+", " ", text)
text = re.sub(r"\s+", " ", text).strip()
print(text)
PY
}

say_async() {
  text=$1
  [ -n "$text" ] || return 0
  if command -v say >/dev/null 2>&1; then
    say "$text" >/dev/null 2>&1 &
  fi
}

notify_user() {
  title=$1
  body=$2
  if command -v osascript >/dev/null 2>&1; then
    osascript - "$title" "$body" <<'OSA' >/dev/null 2>&1 || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
  fi
}

message() {
  printf '%s\n' "$1"
}

run_open_app() {
  app_name=$1
  open -a "$app_name" >/dev/null 2>&1
}

activate_app() {
  app_name=$1
  if run_open_app "$app_name"; then
    message "Switched to $app_name."
    return 0
  fi
  osascript - "$app_name" <<'OSA' >/dev/null
on run argv
  tell application (item 1 of argv) to activate
end run
OSA
  message "Switched to $app_name."
}

quit_app() {
  app_name=$1
  osascript - "$app_name" <<'OSA' >/dev/null
on run argv
  tell application (item 1 of argv) to quit
end run
OSA
  message "Quit $app_name."
}

hide_app() {
  app_name=$1
  osascript - "$app_name" <<'OSA' >/dev/null
on run argv
  tell application "System Events"
    set visible of process (item 1 of argv) to false
  end tell
end run
OSA
  message "Hid $app_name."
}

front_window_menu_item() {
  item_name=$1
  osascript - "$item_name" <<'OSA' >/dev/null
on run argv
  set targetItem to item 1 of argv
  tell application "System Events"
    set frontProcess to first application process whose frontmost is true
    tell frontProcess
      click menu item targetItem of menu "Window" of menu bar 1
    end tell
  end tell
end run
OSA
}

modifiers_script_text() {
  modifiers=$1
  out=""
  for word in $modifiers; do
    case "$word" in
      command|cmd)
        [ -z "$out" ] || out="$out, "
        out="${out}command down"
        ;;
      control|ctrl)
        [ -z "$out" ] || out="$out, "
        out="${out}control down"
        ;;
      option|alt)
        [ -z "$out" ] || out="$out, "
        out="${out}option down"
        ;;
      shift)
        [ -z "$out" ] || out="$out, "
        out="${out}shift down"
        ;;
    esac
  done
  [ -n "$out" ] || return 1
  printf '{%s}\n' "$out"
}

key_code_for() {
  case "$1" in
    escape|esc) printf '53\n' ;;
    return|enter) printf '36\n' ;;
    tab) printf '48\n' ;;
    space) printf '49\n' ;;
    delete|backspace) printf '51\n' ;;
    forward-delete|fwd-delete) printf '117\n' ;;
    left|arrow-left) printf '123\n' ;;
    right|arrow-right) printf '124\n' ;;
    down|arrow-down) printf '125\n' ;;
    up|arrow-up) printf '126\n' ;;
    home) printf '115\n' ;;
    end) printf '119\n' ;;
    page-up) printf '116\n' ;;
    page-down) printf '121\n' ;;
    grave|backtick) printf '50\n' ;;
    f1) printf '122\n' ;;
    f2) printf '120\n' ;;
    f3) printf '99\n' ;;
    f4) printf '118\n' ;;
    f5) printf '96\n' ;;
    f6) printf '97\n' ;;
    f7) printf '98\n' ;;
    f8) printf '100\n' ;;
    f9) printf '101\n' ;;
    f10) printf '109\n' ;;
    f11) printf '103\n' ;;
    f12) printf '111\n' ;;
    *) return 1 ;;
  esac
}

press_key_code() {
  code=$1
  modifiers=${2-}
  if using=$(modifiers_script_text "$modifiers" 2>/dev/null); then
    osascript -e "tell application \"System Events\" to key code $code using $using" >/dev/null
  else
    osascript -e "tell application \"System Events\" to key code $code" >/dev/null
  fi
}

press_keystroke() {
  key_text=$1
  modifiers=${2-}
  if using=$(modifiers_script_text "$modifiers" 2>/dev/null); then
    osascript - "$key_text" "$using" <<'OSA' >/dev/null
on run argv
  tell application "System Events" to keystroke (item 1 of argv) using (run script (item 2 of argv))
end run
OSA
  else
    osascript - "$key_text" <<'OSA' >/dev/null
on run argv
  tell application "System Events" to keystroke (item 1 of argv)
end run
OSA
  fi
}

perform_key() {
  key_name=$1
  modifiers=${2-}
  if code=$(key_code_for "$key_name" 2>/dev/null); then
    press_key_code "$code" "$modifiers"
  else
    press_keystroke "$key_name" "$modifiers"
  fi
}

parse_key_spec() {
  python3 - "$1" <<'PY'
import sys

spec = sys.argv[1] if len(sys.argv) > 1 else ""
spec = spec.replace("page up", "page-up")
spec = spec.replace("page down", "page-down")
spec = spec.replace("forward delete", "forward-delete")
spec = spec.replace("arrow up", "arrow-up")
spec = spec.replace("arrow down", "arrow-down")
spec = spec.replace("arrow left", "arrow-left")
spec = spec.replace("arrow right", "arrow-right")
words = [w for w in spec.split() if w]
mod_words = {"command", "cmd", "control", "ctrl", "option", "alt", "shift"}
mods = []
keys = []
for word in words:
    if word in mod_words and not keys:
        mods.append(word)
    else:
        keys.append(word)
if not keys:
    print("\t")
else:
    print(keys[-1] + "\t" + " ".join(mods))
PY
}

press_key_spec() {
  spec=$1
  parsed=$(parse_key_spec "$spec")
  key_name=$(printf '%s\n' "$parsed" | awk -F '	' '{print $1}')
  modifiers=$(printf '%s\n' "$parsed" | awk -F '	' '{print $2}')
  [ -n "$key_name" ] || return 1
  perform_key "$key_name" "$modifiers"
  message "Pressed $spec."
}

type_text() {
  text=$1
  [ -n "$text" ] || return 0
  if command -v pbcopy >/dev/null 2>&1 && command -v pbpaste >/dev/null 2>&1; then
    clip_file=$(mktemp "${TMPDIR:-/tmp}/artificer-voice-clip.XXXXXX")
    pbpaste > "$clip_file" 2>/dev/null || :
    printf '%s' "$text" | pbcopy
    if command -v cliclick >/dev/null 2>&1; then
      cliclick kd:cmd t:v ku:cmd >/dev/null
    else
      perform_key v command
    fi
    sleep 0.08
    pbcopy < "$clip_file" 2>/dev/null || :
    rm -f "$clip_file"
  else
    osascript - "$text" <<'OSA' >/dev/null
on run argv
  tell application "System Events" to keystroke (item 1 of argv)
end run
OSA
  fi
}

dictation_text_from_phrase() {
  python3 - "$1" <<'PY'
import sys

words = (sys.argv[1] if len(sys.argv) > 1 else "").split()
multi = {
    ("new", "line"): "\n",
    ("new", "paragraph"): "\n\n",
    ("question", "mark"): "?",
    ("exclamation", "mark"): "!",
    ("exclamation", "point"): "!",
    ("full", "stop"): ".",
    ("open", "parenthesis"): "(",
    ("close", "parenthesis"): ")",
    ("open", "quote"): "\"",
    ("close", "quote"): "\"",
}
single = {
    "comma": ",",
    "period": ".",
    "colon": ":",
    "semicolon": ";",
    "dash": "-",
    "hyphen": "-",
    "slash": "/",
}
out = []
i = 0
capitalize_next = False
while i < len(words):
    pair = tuple(words[i:i + 2])
    if pair in multi:
        token = multi[pair]
        i += 2
    else:
        word = words[i]
        i += 1
        if word == "capital" and i < len(words):
            capitalize_next = True
            continue
        token = single.get(word, word)
    if capitalize_next and token.isalpha():
        token = token[:1].upper() + token[1:]
        capitalize_next = False
    if token in {",", ".", "?", "!", ":", ";"}:
        if out:
            out[-1] = out[-1].rstrip() + token + " "
        else:
            out.append(token + " ")
    elif token in {")", "\""}:
        if out:
            out[-1] = out[-1].rstrip() + token + " "
        else:
            out.append(token + " ")
    elif token in {"(", "\n", "\n\n"}:
        out.append(token)
    elif token == "-":
        if out:
            out[-1] = out[-1].rstrip() + "-"
        else:
            out.append("-")
    else:
        out.append(token + " ")
print("".join(out), end="")
PY
}

dictation_active() {
  [ -f "$dictation_file" ]
}

dictation_allowed() {
  case "${ARTIFICER_VOICE_DICTATION_ENABLED:-1}" in
    1|true|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

start_dictation() {
  dictation_allowed || {
    message "Voice dictation is disabled in Preferences."
    return 1
  }
  ensure_state_dir
  date +%s > "$dictation_file"
  say_async "Dictation on."
  message "Dictation mode on."
}

stop_dictation() {
  rm -f "$dictation_file"
  say_async "Dictation off."
  message "Dictation mode off."
}

handle_dictation_phrase() {
  phrase=$1
  dictation_allowed || {
    stop_dictation
    return 1
  }
  case "$phrase" in
    "stop dictation"|"stop dictating"|"end dictation"|"command mode"|"cancel dictation"|"stop listening")
      stop_dictation
      return 0
      ;;
    "start dictation"|"start listening"|"dictation mode"|"begin dictation")
      message "Dictation mode already on."
      return 0
      ;;
    "dictate")
      message "Dictation mode already on."
      return 0
      ;;
    "new line")
      type_text "$(printf '\n')"
      message "Typed newline."
      return 0
      ;;
    "new paragraph")
      type_text "$(printf '\n\n')"
      message "Typed paragraph break."
      return 0
      ;;
    "delete word")
      perform_key delete option
      message "Deleted word."
      return 0
      ;;
    "delete sentence"|"delete line")
      perform_key delete command
      message "Deleted line."
      return 0
      ;;
    "show numbers"|"show names")
      show_numbered_targets
      return 0
      ;;
    "hide numbers"|"hide grid")
      rm -f "$numbers_file"
      message "Hid voice targets."
      return 0
      ;;
    "show grid")
      show_grid_targets screen
      return 0
      ;;
    "show window grid")
      show_grid_targets window
      return 0
      ;;
    "click "[0-9]*)
      click_number "${phrase#click }" click
      return 0
      ;;
    "double click "[0-9]*)
      click_number "${phrase#double click }" double
      return 0
      ;;
    "right click "[0-9]*)
      click_number "${phrase#right click }" right
      return 0
      ;;
    "drag "*)
      parsed=$(python3 - "$phrase" <<'PY'
import re
import sys
m = re.match(r"drag ([0-9]+) to ([0-9]+)$", sys.argv[1])
if m:
    print(m.group(1), m.group(2))
PY
)
      [ -n "$parsed" ] || return 2
      drag_number_to_number $(printf '%s\n' "$parsed")
      return 0
      ;;
  esac
  case "$phrase" in
    "dictate "*) text_phrase=${phrase#dictate } ;;
    *) text_phrase=$phrase ;;
  esac
  text=$(dictation_text_from_phrase "$text_phrase")
  type_text "$text"
  message "Dictation text."
}

notification_text_now() {
  osascript <<'OSA' 2>/dev/null || true
set outText to ""
tell application "System Events"
  if exists process "Notification Center" then
    tell process "Notification Center"
      repeat with w in windows
        try
          set elementsList to entire contents of w
          repeat with e in elementsList
            try
              set candidate to name of e as text
              if candidate is not "" and outText does not contain candidate then set outText to outText & candidate & linefeed
            end try
            try
              set candidate to value of e as text
              if candidate is not "" and outText does not contain candidate then set outText to outText & candidate & linefeed
            end try
            try
              set candidate to description of e as text
              if candidate is not "" and outText does not contain candidate then set outText to outText & candidate & linefeed
            end try
          end repeat
        end try
      end repeat
    end tell
  end if
end tell
return outText
OSA
}

clean_notification_text() {
  awk '
    BEGIN { count = 0 }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      if ($0 == "") next
      if (tolower($0) ~ /^(notification center|close|clear all|options|actions)$/) next
      if (seen[$0]) next
      seen[$0] = 1
      count++
      printf "%s%s", (count == 1 ? "" : ". "), $0
      if (count >= 8) exit
    }
    END { if (count > 0) printf "\n" }
  '
}

cache_notification() {
  ensure_state_dir
  text=$(notification_text_now | clean_notification_text)
  [ -n "$text" ] || return 0
  printf '%s\n' "$text" > "$last_notification_file"
}

read_notification() {
  ensure_state_dir
  cache_notification || true
  text=""
  if [ -f "$last_notification_file" ]; then
    text=$(sed -n '1p' "$last_notification_file")
  fi
  if [ -z "$text" ]; then
    say_async "I do not see a notification to read."
    message "No visible or cached notification was available."
    return 1
  fi
  say_async "$text"
  message "Read notification: $text"
}

visible_targets_now() {
  osascript <<'OSA' 2>/dev/null || true
set outText to ""
tell application "System Events"
  set frontProcess to first application process whose frontmost is true
  tell frontProcess
    if not (exists window 1) then return ""
    set elementList to entire contents of window 1
    repeat with e in elementList
      try
        set roleName to role of e as text
        if roleName is "AXButton" or roleName is "AXCheckBox" or roleName is "AXRadioButton" or roleName is "AXPopUpButton" or roleName is "AXMenuButton" or roleName is "AXTextField" or roleName is "AXLink" then
          set posValue to position of e
          set sizeValue to size of e
          set xValue to (item 1 of posValue) + ((item 1 of sizeValue) / 2)
          set yValue to (item 2 of posValue) + ((item 2 of sizeValue) / 2)
          set labelValue to ""
          try
            set labelValue to name of e as text
          end try
          if labelValue is "" then
            try
              set labelValue to description of e as text
            end try
          end if
          if labelValue is not "" then set outText to outText & labelValue & tab & (xValue as integer) & tab & (yValue as integer) & linefeed
        end if
      end try
    end repeat
  end tell
end tell
return outText
OSA
}

save_numbered_targets() {
  ensure_state_dir
  visible_targets_now | awk -F '	' '
    NF >= 3 && $1 != "" {
      key = tolower($1) "|" $2 "|" $3
      if (seen[key]) next
      seen[key] = 1
      count++
      printf "%d\t%s\t%s\t%s\n", count, $1, $2, $3
      if (count >= 40) exit
    }
  ' > "$numbers_file"
  [ -s "$numbers_file" ]
}

save_grid_targets() {
  scope=$1
  ensure_state_dir
  if [ "$scope" = window ]; then
    bounds=$(
      osascript 2>/dev/null <<'OSA' || printf ''
tell application "System Events"
  set frontProcess to first application process whose frontmost is true
  tell frontProcess
    set posValue to position of window 1
    set sizeValue to size of window 1
    return ((item 1 of posValue) as text) & "," & ((item 2 of posValue) as text) & "," & (((item 1 of posValue) + (item 1 of sizeValue)) as text) & "," & (((item 2 of posValue) + (item 2 of sizeValue)) as text)
  end tell
end tell
OSA
    )
  else
    bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || printf '')
  fi
  [ -n "$bounds" ] || return 1
  python3 - "$bounds" > "$numbers_file" <<'PY'
import sys

parts = [int(float(part.strip())) for part in sys.argv[1].split(",")[:4]]
left, top, right, bottom = parts
width = max(1, right - left)
height = max(1, bottom - top)
n = 1
for row in range(3):
    for col in range(3):
        x = left + int(width * (col + 0.5) / 3)
        y = top + int(height * (row + 0.5) / 3)
        print(f"{n}\tGrid {n}\t{x}\t{y}")
        n += 1
PY
}

show_numbered_targets() {
  if ! save_numbered_targets; then
    message "No clickable targets found."
    return 1
  fi
  summary=$(awk -F '	' 'NR <= 12 { printf "%s %s. ", $1, $2 }' "$numbers_file")
  notify_user "Artificer Voice Numbers" "$summary"
  say_async "$summary"
  message "Numbered visible controls."
}

show_grid_targets() {
  scope=$1
  save_grid_targets "$scope"
  summary=$(awk -F '	' '{ printf "%s. ", $1 }' "$numbers_file")
  notify_user "Artificer Voice Grid" "Say click 1 through click 9."
  say_async "Grid shown. Say click 1 through click 9."
  message "Numbered $scope grid: $summary"
}

target_coords() {
  number=$1
  awk -F '	' -v wanted="$number" '$1 == wanted { print $3 " " $4; found = 1; exit } END { exit found ? 0 : 1 }' "$numbers_file"
}

click_number() {
  number=$1
  click_kind=${2-click}
  [ -f "$numbers_file" ] || {
    message "No numbered targets are active."
    return 1
  }
  coords=$(target_coords "$number") || {
    message "No target numbered $number."
    return 1
  }
  x=$(printf '%s\n' "$coords" | awk '{print $1}')
  y=$(printf '%s\n' "$coords" | awk '{print $2}')
  command -v cliclick >/dev/null 2>&1 || {
    message "cliclick is required for numbered clicking."
    return 1
  }
  case "$click_kind" in
    double) cliclick "dc:$x,$y" >/dev/null ;;
    right) cliclick "rc:$x,$y" >/dev/null ;;
    *) cliclick "c:$x,$y" >/dev/null ;;
  esac
  message "Clicked $number."
}

drag_number_to_number() {
  from_number=$1
  to_number=$2
  [ -f "$numbers_file" ] || {
    message "No numbered targets are active."
    return 1
  }
  from_coords=$(target_coords "$from_number") || return 1
  to_coords=$(target_coords "$to_number") || return 1
  from_x=$(printf '%s\n' "$from_coords" | awk '{print $1}')
  from_y=$(printf '%s\n' "$from_coords" | awk '{print $2}')
  to_x=$(printf '%s\n' "$to_coords" | awk '{print $1}')
  to_y=$(printf '%s\n' "$to_coords" | awk '{print $2}')
  command -v cliclick >/dev/null 2>&1 || {
    message "cliclick is required for dragging."
    return 1
  }
  cliclick "dd:$from_x,$from_y" "dm:$to_x,$to_y" "du:$to_x,$to_y" >/dev/null
  message "Dragged $from_number to $to_number."
}

click_control_by_name() {
  target=$1
  osascript - "$target" <<'OSA' >/dev/null
on run argv
  set targetName to item 1 of argv
  tell application "System Events"
    set frontProcess to first application process whose frontmost is true
    tell frontProcess
      if not (exists window 1) then error "No front window"
      set elementList to entire contents of window 1
      repeat with e in elementList
        try
          set candidate to ""
          try
            set candidate to name of e as text
          end try
          if candidate is "" then
            try
              set candidate to description of e as text
            end try
          end if
          ignoring case
            if candidate is targetName then
              click e
              return
            end if
          end ignoring
        end try
      end repeat
      error "No visible control named " & targetName
    end tell
  end tell
end run
OSA
  message "Clicked $target."
}

move_pointer() {
  direction=$1
  amount=${2-80}
  case "$amount" in
    ''|*[!0-9]*) amount=80 ;;
  esac
  command -v cliclick >/dev/null 2>&1 || {
    message "cliclick is required for pointer movement."
    return 1
  }
  case "$direction" in
    up) cliclick "m:+0,-$amount" >/dev/null ;;
    down) cliclick "m:+0,+$amount" >/dev/null ;;
    left) cliclick "m:-$amount,+0" >/dev/null ;;
    right) cliclick "m:+$amount,+0" >/dev/null ;;
    *) return 1 ;;
  esac
  message "Moved pointer $direction."
}

handle_phrase() {
  phrase=$(normalize_phrase "$1")
  [ -n "$phrase" ] || return 2

  if dictation_active; then
    handle_dictation_phrase "$phrase"
    return 0
  fi

  case "$phrase" in
    "read it"|"read that"|"read that aloud"|"can you read that"|"read that please"|"read it please"|"what was that"|"what did that say"|"what did that notification say"|"repeat the notification")
      read_notification
      return 0
      ;;
    "start dictation"|"start listening"|"dictation mode"|"begin dictation"|"dictate")
      dictation_allowed || return 2
      start_dictation
      return 0
      ;;
    "start listening "*)
      dictation_allowed || return 2
      start_dictation >/dev/null
      text=$(dictation_text_from_phrase "${phrase#start listening }")
      type_text "$text"
      message "Dictation mode on. Dictated text."
      return 0
      ;;
    "stop dictation"|"stop dictating"|"stop listening"|"end dictation"|"command mode")
      stop_dictation
      return 0
      ;;
    "dictate "*)
      dictation_allowed || return 2
      start_dictation >/dev/null
      text=$(dictation_text_from_phrase "${phrase#dictate }")
      type_text "$text"
      message "Dictation mode on. Dictated text."
      return 0
      ;;
    "show numbers"|"show names")
      show_numbered_targets
      return 0
      ;;
    "hide numbers"|"hide grid")
      rm -f "$numbers_file"
      message "Hid voice targets."
      return 0
      ;;
    "show grid")
      show_grid_targets screen
      return 0
      ;;
    "show window grid")
      show_grid_targets window
      return 0
      ;;
    "click "[0-9]*)
      click_number "${phrase#click }" click
      return 0
      ;;
    "double click "[0-9]*)
      click_number "${phrase#double click }" double
      return 0
      ;;
    "right click "[0-9]*)
      click_number "${phrase#right click }" right
      return 0
      ;;
    "drag "*)
      parsed=$(python3 - "$phrase" <<'PY'
import re
import sys
m = re.match(r"drag ([0-9]+) to ([0-9]+)$", sys.argv[1])
if m:
    print(m.group(1), m.group(2))
PY
)
      [ -n "$parsed" ] || return 2
      drag_number_to_number $(printf '%s\n' "$parsed")
      return 0
      ;;
    "click "*)
      click_control_by_name "${phrase#click }"
      return 0
      ;;
    "press "*)
      press_key_spec "${phrase#press }"
      return 0
      ;;
    "undo")
      perform_key z command
      message "Undo."
      return 0
      ;;
    "redo")
      perform_key z "command shift"
      message "Redo."
      return 0
      ;;
    "copy")
      perform_key c command
      message "Copy."
      return 0
      ;;
    "cut")
      perform_key x command
      message "Cut."
      return 0
      ;;
    "paste")
      perform_key v command
      message "Paste."
      return 0
      ;;
    "select all")
      perform_key a command
      message "Select all."
      return 0
      ;;
    "delete word")
      perform_key delete option
      message "Deleted word."
      return 0
      ;;
    "delete sentence"|"delete line")
      perform_key delete command
      message "Deleted line."
      return 0
      ;;
    "scroll down"|"page down")
      perform_key page-down
      message "Scrolled down."
      return 0
      ;;
    "scroll up"|"page up")
      perform_key page-up
      message "Scrolled up."
      return 0
      ;;
    "scroll left")
      perform_key left shift
      message "Scrolled left."
      return 0
      ;;
    "scroll right")
      perform_key right shift
      message "Scrolled right."
      return 0
      ;;
    "top"|"go to top")
      perform_key up command
      message "Went to top."
      return 0
      ;;
    "bottom"|"go to bottom")
      perform_key down command
      message "Went to bottom."
      return 0
      ;;
    "close window")
      perform_key w command
      message "Closed window."
      return 0
      ;;
    "minimize window")
      perform_key m command
      message "Minimized window."
      return 0
      ;;
    "zoom window")
      front_window_menu_item Zoom
      message "Zoomed window."
      return 0
      ;;
    "full screen"|"enter full screen"|"exit full screen")
      perform_key f "control command"
      message "Toggled full screen."
      return 0
      ;;
    "next window")
      perform_key grave command
      message "Next window."
      return 0
      ;;
    "previous window")
      perform_key grave "command shift"
      message "Previous window."
      return 0
      ;;
    "show desktop")
      perform_key f11
      message "Show desktop."
      return 0
      ;;
    "mission control")
      perform_key up control
      message "Mission Control."
      return 0
      ;;
    "app expose"|"application expose")
      perform_key down control
      message "App Expose."
      return 0
      ;;
    "lock screen")
      perform_key q "control command"
      message "Locked screen."
      return 0
      ;;
    "sleep screen"|"turn off screen")
      pmset displaysleepnow >/dev/null
      message "Slept displays."
      return 0
      ;;
    "move pointer up"|"move mouse up")
      move_pointer up
      return 0
      ;;
    "move pointer down"|"move mouse down")
      move_pointer down
      return 0
      ;;
    "move pointer left"|"move mouse left")
      move_pointer left
      return 0
      ;;
    "move pointer right"|"move mouse right")
      move_pointer right
      return 0
      ;;
    "move pointer up "*|"move mouse up "*)
      move_pointer up "${phrase##* }"
      return 0
      ;;
    "move pointer down "*|"move mouse down "*)
      move_pointer down "${phrase##* }"
      return 0
      ;;
    "move pointer left "*|"move mouse left "*)
      move_pointer left "${phrase##* }"
      return 0
      ;;
    "move pointer right "*|"move mouse right "*)
      move_pointer right "${phrase##* }"
      return 0
      ;;
    "switch to "*)
      activate_app "${phrase#switch to }"
      return 0
      ;;
    "open "*)
      activate_app "${phrase#open }"
      return 0
      ;;
    "launch "*)
      activate_app "${phrase#launch }"
      return 0
      ;;
    "quit "*)
      quit_app "${phrase#quit }"
      return 0
      ;;
    "hide "*)
      hide_app "${phrase#hide }"
      return 0
      ;;
    "show "*)
      activate_app "${phrase#show }"
      return 0
      ;;
  esac

  return 2
}

case "${1-}" in
  --help|--usage|-h)
    usage
    ;;
  cache-notification)
    cache_notification || true
    ;;
  dictation-active)
    dictation_active
    ;;
  handle)
    shift
    handle_phrase "${1-}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
