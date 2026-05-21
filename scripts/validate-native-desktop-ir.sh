#!/bin/sh

set -eu

ir_path=${1:-ir/app.ir.yaml}
schema_path=${2:-schemas/native-desktop-ir-v1.json}

has_line_break() {
  value=${1-}
  nl_char=$(printf '\nX')
  nl_char=${nl_char%X}
  cr_char=$(printf '\r')
  case "$value" in *"$nl_char"*|*"$cr_char"*) return 0 ;; esac
  return 1
}

if has_line_break "$ir_path"; then
  printf '%s\n' "native-desktop-ir: IR path must not contain line breaks." >&2
  exit 2
fi

if has_line_break "$schema_path"; then
  printf '%s\n' "native-desktop-ir: schema path must not contain line breaks." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: jq is required to validate the canonical IR." >&2
  exit 1
fi

[ -f "$ir_path" ] || {
  printf '%s\n' "native-desktop-ir: IR file not found: $ir_path" >&2
  exit 1
}

[ -f "$schema_path" ] || {
  printf '%s\n' "native-desktop-ir: schema file not found: $schema_path" >&2
  exit 1
}

if ! jq -e . "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: canonical IR must stay valid YAML 1.2 JSON-compatible syntax." >&2
  printf '%s\n' "repair: rewrite ir/app.ir.yaml as normalized JSON-compatible YAML with double-quoted keys and values." >&2
  exit 1
fi

if ! jq -e '
  .version == "native-desktop-ir/v1"
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: version must be native-desktop-ir/v1." >&2
  printf '%s\n' "repair: set version to native-desktop-ir/v1." >&2
  exit 1
fi

if ! jq -e '
  (.app.id | type) == "string" and (.app.id | length) > 0 and
  (.app.name | type) == "string" and (.app.name | length) > 0
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: app.id and app.name are required strings." >&2
  printf '%s\n' "repair: add a stable app.id and a human-readable app.name." >&2
  exit 1
fi

if ! jq -e '
  (.app.id | test("^[A-Za-z][A-Za-z0-9-]*$")) and
  (.app.name | test("^[A-Za-z0-9 .,_()\\-]+$")) and
  ((.app.window.title // .app.name) | test("^[A-Za-z0-9 .,_()\\-]+$"))
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: app.id, app.name, and app.window.title must be render-safe." >&2
  printf '%s\n' "repair: use a slug-like app.id and display names with letters, numbers, spaces, '.', ',', '_', '-', or parentheses." >&2
  exit 1
fi

if ! jq -e '
  (.app.targets | type) == "array" and
  (.app.targets | length) > 0 and
  (.app.targets | all(. == "macos" or . == "linux"))
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: app.targets must contain one or both of macos and linux." >&2
  printf '%s\n' "repair: use targets like [\"macos\", \"linux\"]." >&2
  exit 1
fi

if ! jq -e '
  (.app.window.type == "Window") and
  ((.app.window.id | type) == "string") and
  ((.app.window.id | length) > 0)
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: app.window must be a Window node with a stable id." >&2
  printf '%s\n' "repair: set app.window.type to Window and add app.window.id." >&2
  exit 1
fi

if ! jq -e '
  def nodes:
    if type == "array" then
      (map(nodes) | add) // []
    elif type == "object" then
      ((if (.type? and .id?) then [.] else [] end) + (([ .[]? ] | map(nodes) | add) // []))
    else
      []
    end;
  def allowed_type:
    . == "Window" or . == "MenuBar" or . == "Menu" or . == "MenuItem" or . == "Toolbar" or
    . == "Sidebar" or . == "Content" or . == "Section" or . == "Stack" or . == "Split" or
    . == "Tabs" or . == "List" or . == "Detail" or . == "Form" or . == "Group" or
    . == "Text" or . == "Label" or . == "Button" or . == "Input" or . == "Toggle" or
    . == "Select" or . == "Image" or . == "Spacer" or . == "Modal" or . == "StatusBar";
  (nodes | all((.type | allowed_type) and ((.id | type) == "string") and (.id | length > 0))) and
  ((nodes | map(.id) | length) == (nodes | map(.id) | unique | length))
' "$ir_path" >/dev/null 2>&1; then
  printf '%s\n' "native-desktop-ir: every node needs a unique id and a v1 primitive type." >&2
  printf '%s\n' "repair: dedupe node ids and use only the documented v1 primitive set." >&2
  exit 1
fi

printf 'status=ok\n'
printf 'ir=%s\n' "$ir_path"
printf 'schema=%s\n' "$schema_path"
