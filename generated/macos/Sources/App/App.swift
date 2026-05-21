// Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh.
import SwiftUI

private let canonicalIR = """
{
  "version": "native-desktop-ir/v1",
  "format": "yaml-1.2-json-compatible",
  "app": {
    "id": "artificer-native",
    "name": "Artificer (native)",
    "targets": [
      "macos",
      "linux"
    ],
    "window": {
      "id": "window.main",
      "name": "mainWindow",
      "type": "Window",
      "title": "Artificer (native)",
      "width": 112,
      "minWidth": 96,
      "height": 72,
      "minHeight": 56,
      "menuBar": {
        "id": "menubar.main",
        "type": "MenuBar",
        "children": [
          {
            "id": "menu.app",
            "type": "Menu",
            "title": "Artificer (native)",
            "children": [
              {
                "id": "menuitem.openSettings",
                "type": "MenuItem",
                "title": "Settings",
                "action": "open_settings"
              },
              {
                "id": "menuitem.quit",
                "type": "MenuItem",
                "title": "Quit",
                "action": "quit_app"
              }
            ]
          },
          {
            "id": "menu.file",
            "type": "Menu",
            "title": "File",
            "children": [
              {
                "id": "menuitem.save",
                "type": "MenuItem",
                "title": "Save",
                "action": "save_document",
                "shortcut": "cmd+s"
              }
            ]
          }
        ]
      },
      "toolbar": {
        "id": "toolbar.main",
        "type": "Toolbar",
        "children": [
          {
            "id": "toolbar.button.save",
            "type": "Button",
            "title": "Save",
            "action": "save_document"
          },
          {
            "id": "toolbar.spacer.1",
            "type": "Spacer"
          },
          {
            "id": "toolbar.button.settings",
            "type": "Button",
            "title": "Settings",
            "action": "open_settings"
          }
        ]
      },
      "content": {
        "id": "content.main",
        "type": "Content",
        "child": {
          "id": "stack.root",
          "type": "Stack",
          "axis": "vertical",
          "spacing": 16,
          "children": [
            {
              "id": "section.hero",
              "type": "Section",
              "title": "Overview",
              "child": {
                "id": "stack.hero",
                "type": "Stack",
                "axis": "vertical",
                "spacing": 12,
                "children": [
                  {
                    "id": "text.headline",
                    "type": "Text",
                    "style": "title",
                    "value": "Artificer (native)"
                  },
                  {
                    "id": "text.summary",
                    "type": "Text",
                    "style": "body",
                    "value": "Native desktop app scaffolded by App Forge."
                  },
                  {
                    "id": "group.form",
                    "type": "Group",
                    "title": "Quick action",
                    "child": {
                      "id": "form.settings",
                      "type": "Form",
                      "children": [
                        {
                          "id": "input.projectName",
                          "type": "Input",
                          "label": "Project name",
                          "stateKey": "project_name",
                          "placeholder": "Artificer (native)"
                        },
                        {
                          "id": "button.primary",
                          "type": "Button",
                          "title": "Save draft",
                          "action": "save_document"
                        }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      },
      "statusBar": {
        "id": "statusbar.main",
        "type": "StatusBar",
        "children": [
          {
            "id": "statusbar.text",
            "type": "Text",
            "style": "caption",
            "value": "Ready"
          }
        ]
      }
    }
  },
  "extensions": []
}
"""

private let menuBarIR = #"{"id":"menubar.main","type":"MenuBar","children":[{"id":"menu.app","type":"Menu","title":"Artificer (native)","children":[{"id":"menuitem.openSettings","type":"MenuItem","title":"Settings","action":"open_settings"},{"id":"menuitem.quit","type":"MenuItem","title":"Quit","action":"quit_app"}]},{"id":"menu.file","type":"Menu","title":"File","children":[{"id":"menuitem.save","type":"MenuItem","title":"Save","action":"save_document","shortcut":"cmd+s"}]}]}"#
private let toolbarIR = #"{"id":"toolbar.main","type":"Toolbar","children":[{"id":"toolbar.button.save","type":"Button","title":"Save","action":"save_document"},{"id":"toolbar.spacer.1","type":"Spacer"},{"id":"toolbar.button.settings","type":"Button","title":"Settings","action":"open_settings"}]}"#
private let contentIR = #"{"id":"content.main","type":"Content","child":{"id":"stack.root","type":"Stack","axis":"vertical","spacing":16,"children":[{"id":"section.hero","type":"Section","title":"Overview","child":{"id":"stack.hero","type":"Stack","axis":"vertical","spacing":12,"children":[{"id":"text.headline","type":"Text","style":"title","value":"Artificer (native)"},{"id":"text.summary","type":"Text","style":"body","value":"Native desktop app scaffolded by App Forge."},{"id":"group.form","type":"Group","title":"Quick action","child":{"id":"form.settings","type":"Form","children":[{"id":"input.projectName","type":"Input","label":"Project name","stateKey":"project_name","placeholder":"Artificer (native)"},{"id":"button.primary","type":"Button","title":"Save draft","action":"save_document"}]}}]}}]}}"#
private let statusBarIR = #"{"id":"statusbar.main","type":"StatusBar","children":[{"id":"statusbar.text","type":"Text","style":"caption","value":"Ready"}]}"#

@main
struct GeneratedNativeDesktopApp: App {
  var body: some Scene {
    WindowGroup("Artificer (native)") {
      RootView()
    }
    .commands {
      CommandMenu("Artificer (native)") {
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
      Text("Artificer (native)")
        .font(.title2)
      Text("Generated from the canonical native desktop IR.")
        .foregroundStyle(.secondary)
      Divider()
      Text("Toolbar IR: \(toolbarIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Content IR: \(contentIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Status IR: \(statusBarIR)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text("Targets: macos,linux")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(minWidth: 720, minHeight: 460, alignment: .topLeading)
  }
}
