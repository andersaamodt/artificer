#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
ir_path="$project_dir/ir/app.ir.yaml"
schema_path="$project_dir/schemas/native-desktop-ir-v1.json"
generated_root="$project_dir/generated"
macos_dir="$generated_root/macos"
linux_dir="$generated_root/linux"

sh "$script_dir/validate-native-desktop-ir.sh" "$ir_path" "$schema_path" >/dev/null

app_name=$(jq -r '.app.name' "$ir_path")
app_id=$(jq -r '.app.id' "$ir_path")
window_title=$(jq -r '.app.window.title // .app.name' "$ir_path")
pretty_ir=$(jq '.' "$ir_path")
linux_ir_literal=$(printf '%s\n' "$pretty_ir" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/  "/; s/$/\\n"/')

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_template() {
  src=$1
  dst=$2
  mkdir -p "$(dirname "$dst")"
  escaped_name=$(escape_sed_replacement "$app_name")
  escaped_id=$(escape_sed_replacement "$app_id")
  escaped_title=$(escape_sed_replacement "$window_title")
  escaped_project_dir=$(escape_sed_replacement "$project_dir")
  sed \
    -e "s/__APP_NAME__/$escaped_name/g" \
    -e "s/__APP_ID__/$escaped_id/g" \
    -e "s/__WINDOW_TITLE__/$escaped_title/g" \
    -e "s/__PROJECT_DIR__/$escaped_project_dir/g" \
    "$src" > "$dst"
}

mkdir -p "$macos_dir/Sources/App" "$linux_dir/src"

cat > "$macos_dir/Package.swift" <<EOF
// Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "$app_id",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "$app_id", targets: ["App"])
  ],
  targets: [
    .executableTarget(
      name: "App",
      path: "Sources/App"
    )
  ]
)
EOF

render_template "$project_dir/templates/macos/App.swift.template" "$macos_dir/Sources/App/App.swift"
render_template "$project_dir/templates/linux/main.c.template" "$linux_dir/src/main.c"

cat > "$linux_dir/meson.build" <<EOF
project('$app_id', 'c', version: '0.1.0')
gtk = dependency('gtk4')
executable('$app_id', 'src/main.c', dependencies: gtk, install: true)
EOF

printf 'status=ok\n'
printf 'ir=%s\n' "$ir_path"
printf 'macos=%s\n' "$macos_dir"
printf 'linux=%s\n' "$linux_dir"
