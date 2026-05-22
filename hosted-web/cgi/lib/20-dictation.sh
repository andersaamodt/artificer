normalize_dictation_shortcut() {
  shortcut_kind=$1
  shortcut_value=$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$shortcut_value" in
    none)
      printf '%s' "none"
      return 0
      ;;
  esac

  case "$shortcut_kind" in
    hold)
      case "$shortcut_value" in
        alt|meta|shift|control|ctrl-m|space|mouse-button-4|mouse-button-5|mouse-wheel-click|backslash|semicolon|quote|f6|f7|f8|f9|f10|f13|f14|f15|f16|f17|f18|f19)
          printf '%s' "$shortcut_value"
          return 0
          ;;
      esac
      ;;
    toggle)
      case "$shortcut_value" in
        capslock|backslash|semicolon|quote|f6|f7|f8|f9|f10|f13|f14|f15|f16|f17|f18|f19|mouse-button-4|mouse-button-5|mouse-wheel-click)
          printf '%s' "$shortcut_value"
          return 0
          ;;
      esac
      ;;
  esac

  printf '%s' "none"
}

dictation_shortcuts_get_json() {
  hold_value=$(normalize_dictation_shortcut "hold" "$(read_file_line "$dictation_shortcut_hold_file" "none")")
  toggle_value=$(normalize_dictation_shortcut "toggle" "$(read_file_line "$dictation_shortcut_toggle_file" "none")")
  printf '{"success":true,"hold":"%s","toggle":"%s"}\n' \
    "$(json_escape "$hold_value")" \
    "$(json_escape "$toggle_value")"
}

dictation_shortcuts_set_values() {
  next_hold=$(normalize_dictation_shortcut "hold" "${1:-none}")
  next_toggle=$(normalize_dictation_shortcut "toggle" "${2:-none}")
  mkdir -p "$dictation_settings_dir"
  printf '%s\n' "$next_hold" > "$dictation_shortcut_hold_file"
  printf '%s\n' "$next_toggle" > "$dictation_shortcut_toggle_file"
}

dictation_prewarm_enabled() {
  raw_value=$(trim "$(read_file_line "$dictation_prewarm_enabled_file" "1")")
  case "$raw_value" in
    0|false|FALSE|False|no|NO|No|off|OFF|Off)
      printf '%s' "0"
      ;;
    *)
      printf '%s' "1"
      ;;
  esac
}

set_dictation_prewarm_enabled() {
  next_value=$1
  mkdir -p "$dictation_settings_dir"
  case "$next_value" in
    1)
      printf '%s\n' "1" > "$dictation_prewarm_enabled_file"
      ;;
    *)
      printf '%s\n' "0" > "$dictation_prewarm_enabled_file"
      ;;
  esac
}

dictation_prewarm_get_json() {
  prewarm_enabled=$(dictation_prewarm_enabled)
  if [ "$prewarm_enabled" = "1" ]; then
    prewarm_json=true
  else
    prewarm_json=false
  fi
  printf '{"success":true,"enabled":%s}\n' "$prewarm_json"
}

dictation_whisper_language_entries() {
  cat <<'EOF'
af|Afrikaans
am|Amharic
ar|Arabic
as|Assamese
az|Azerbaijani
ba|Bashkir
be|Belarusian
bg|Bulgarian
bn|Bengali
bo|Tibetan
br|Breton
bs|Bosnian
ca|Catalan
cs|Czech
cy|Welsh
da|Danish
de|German
el|Greek
en|English
es|Spanish
et|Estonian
eu|Basque
fa|Persian
fi|Finnish
fo|Faroese
fr|French
gl|Galician
gu|Gujarati
ha|Hausa
haw|Hawaiian
he|Hebrew
hi|Hindi
hr|Croatian
ht|Haitian Creole
hu|Hungarian
hy|Armenian
id|Indonesian
is|Icelandic
it|Italian
ja|Japanese
jw|Javanese
ka|Georgian
kk|Kazakh
km|Khmer
kn|Kannada
ko|Korean
la|Latin
lb|Luxembourgish
ln|Lingala
lo|Lao
lt|Lithuanian
lv|Latvian
mg|Malagasy
mi|Maori
mk|Macedonian
ml|Malayalam
mn|Mongolian
mr|Marathi
ms|Malay
mt|Maltese
my|Burmese
ne|Nepali
nl|Dutch
nn|Nynorsk
no|Norwegian
oc|Occitan
pa|Punjabi
pl|Polish
ps|Pashto
pt|Portuguese
ro|Romanian
ru|Russian
sa|Sanskrit
sd|Sindhi
si|Sinhala
sk|Slovak
sl|Slovenian
sn|Shona
so|Somali
sq|Albanian
sr|Serbian
su|Sundanese
sv|Swedish
sw|Swahili
ta|Tamil
te|Telugu
tg|Tajik
th|Thai
tk|Turkmen
tl|Tagalog
tr|Turkish
tt|Tatar
uk|Ukrainian
ur|Urdu
uz|Uzbek
vi|Vietnamese
yi|Yiddish
yo|Yoruba
zh|Chinese
EOF
}

normalize_dictation_language_value() {
  language_value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$language_value" in
    ""|auto|default|detect)
      printf '%s' "auto"
      return 0
      ;;
    *[!a-z0-9_-]*)
      printf '%s' ""
      return 0
      ;;
  esac
  while IFS='|' read -r code _label; do
    [ -n "$code" ] || continue
    if [ "$language_value" = "$code" ]; then
      printf '%s' "$code"
      return 0
    fi
  done <<EOF
$(dictation_whisper_language_entries)
EOF
  printf '%s' ""
}

dictation_language_allowed_for_backend() {
  backend_name=$1
  language_value=$2
  case "$language_value" in
    auto)
      return 0
      ;;
    "")
      return 1
      ;;
  esac
  case "$backend_name" in
    ""|ctranslate2-whisper|mlx-whisper)
      normalized=$(normalize_dictation_language_value "$language_value")
      [ "$normalized" = "$language_value" ]
      return $?
      ;;
    parakeet)
      [ "$language_value" = "en" ]
      return $?
      ;;
  esac
  return 1
}

dictation_language_backend_for_settings() {
  backend_name=$(installed_voice_backend_for_host || true)
  if [ -n "$backend_name" ]; then
    printf '%s' "$backend_name"
    return 0
  fi
  preferred=$(preferred_voice_component_for_host || true)
  printf '%s' "$preferred"
}

dictation_language_value_for_backend() {
  backend_name=$1
  stored_value=$(normalize_dictation_language_value "$(read_file_line "$dictation_language_file" "auto")")
  if [ -z "$stored_value" ]; then
    stored_value="auto"
  fi
  if ! dictation_language_allowed_for_backend "$backend_name" "$stored_value"; then
    stored_value="auto"
  fi
  printf '%s' "$stored_value"
}

set_dictation_language_value() {
  next_value=$1
  mkdir -p "$dictation_settings_dir"
  printf '%s\n' "$next_value" > "$dictation_language_file"
}

dictation_languages_json_for_backend() {
  backend_name=$1
  printf '['
  printf '{"value":"auto","label":"Auto-detect"}'
  case "$backend_name" in
    ""|ctranslate2-whisper|mlx-whisper)
      while IFS='|' read -r code label; do
        [ -n "$code" ] || continue
        printf ',{"value":"%s","label":"%s"}' \
          "$(json_escape "$code")" \
          "$(json_escape "$label")"
      done <<EOF
$(dictation_whisper_language_entries)
EOF
      ;;
    parakeet)
      printf ',{"value":"en","label":"English"}'
      ;;
  esac
  printf ']'
}

dictation_language_get_json() {
  backend_name=${1:-}
  if [ -z "$backend_name" ]; then
    backend_name=$(dictation_language_backend_for_settings)
  fi
  language_value=$(dictation_language_value_for_backend "$backend_name")
  languages_json=$(dictation_languages_json_for_backend "$backend_name")
  printf '{"success":true,"language":"%s","languages":%s}\n' \
    "$(json_escape "$language_value")" \
    "$languages_json"
}

