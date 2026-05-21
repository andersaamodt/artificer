#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
ir_path="$project_dir/ir/app.ir.yaml"
schema_path="$project_dir/schemas/native-desktop-ir-v1.json"
generated_root="$project_dir/generated"
macos_dir="$generated_root/macos"
linux_dir="$generated_root/linux"

"$script_dir/validate-native-desktop-ir.sh" "$ir_path" "$schema_path" >/dev/null

app_name=$(jq -r '.app.name' "$ir_path")
app_id=$(jq -r '.app.id' "$ir_path")
window_title=$(jq -r '.app.window.title // .app.name' "$ir_path")
menu_json=$(jq -c '.app.window.menuBar // {}' "$ir_path")
toolbar_json=$(jq -c '.app.window.toolbar // {}' "$ir_path")
content_json=$(jq -c '.app.window.content // {}' "$ir_path")
status_json=$(jq -c '.app.window.statusBar // {}' "$ir_path")
targets_csv=$(jq -r '.app.targets | join(",")' "$ir_path")
pretty_ir=$(jq '.' "$ir_path")

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

cat > "$macos_dir/Sources/App/App.swift" <<EOF
// Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh.
import SwiftUI

private let canonicalIR = """
$pretty_ir
"""

private let menuBarIR = #"$menu_json"#
private let toolbarIR = #"$toolbar_json"#
private let contentIR = #"$content_json"#
private let statusBarIR = #"$status_json"#

@main
struct GeneratedNativeDesktopApp: App {
  var body: some Scene {
    WindowGroup("$window_title") {
      RootView()
    }
    .commands {
      CommandMenu("$app_name") {
        Button("Settings") {}
        Divider()
        Button("Quit") {}
      }
    }
  }
}

private struct RootView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("$app_name")
        .font(.title2)
      Text("Generated from the canonical native desktop IR.")
        .foregroundStyle(.secondary)
      Divider()
      Text("Toolbar IR: \\(toolbarIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Content IR: \\(contentIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Status IR: \\(statusBarIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text("Targets: $targets_csv")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(minWidth: 720, minHeight: 460, alignment: .topLeading)
  }
}
EOF

linux_ir_literal=$(printf '%s' "$pretty_ir" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')

cat > "$linux_dir/meson.build" <<EOF
# Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh.
project('$app_id', 'c', version: '0.1.0')

gtk_dep = dependency('gtk4')

executable(
  '$app_id',
  ['src/main.c'],
  dependencies: [gtk_dep],
  install: false,
)
EOF

cat > "$linux_dir/src/main.c" <<EOF
/* Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh. */
#include <gtk/gtk.h>

static const char *wizardry_app_ir =
  "$linux_ir_literal";

static void activate(GtkApplication *app, gpointer user_data) {
  GtkWidget *window = gtk_application_window_new(app);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  GtkWidget *title = gtk_label_new("$app_name");
  GtkWidget *summary = gtk_label_new("Generated from the canonical native desktop IR.");
  GtkWidget *targets = gtk_label_new("Targets: $targets_csv");

  (void)user_data;
  (void)wizardry_app_ir;

  gtk_window_set_title(GTK_WINDOW(window), "$window_title");
  gtk_window_set_default_size(GTK_WINDOW(window), 960, 640);
  gtk_widget_set_margin_top(box, 20);
  gtk_widget_set_margin_bottom(box, 20);
  gtk_widget_set_margin_start(box, 20);
  gtk_widget_set_margin_end(box, 20);
  gtk_label_set_xalign(GTK_LABEL(title), 0.0f);
  gtk_label_set_xalign(GTK_LABEL(summary), 0.0f);
  gtk_label_set_xalign(GTK_LABEL(targets), 0.0f);
  gtk_box_append(GTK_BOX(box), title);
  gtk_box_append(GTK_BOX(box), summary);
  gtk_box_append(GTK_BOX(box), targets);
  gtk_window_set_child(GTK_WINDOW(window), box);
  gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
  GtkApplication *app = gtk_application_new("app.$app_id", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
EOF

printf 'status=ok\n'
printf 'ir=%s\n' "$ir_path"
printf 'macos=%s\n' "$macos_dir"
printf 'linux=%s\n' "$linux_dir"
