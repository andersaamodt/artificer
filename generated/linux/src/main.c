/* Generated from ir/app.ir.yaml. Regenerate with scripts/render-native-desktop.sh. */
#include <gtk/gtk.h>

static const char *wizardry_app_ir =
  "{\n  \"version\": \"native-desktop-ir/v1\",\n  \"format\": \"yaml-1.2-json-compatible\",\n  \"app\": {\n    \"id\": \"artificer-native\",\n    \"name\": \"Artificer (native)\",\n    \"targets\": [\n      \"macos\",\n      \"linux\"\n    ],\n    \"window\": {\n      \"id\": \"window.main\",\n      \"name\": \"mainWindow\",\n      \"type\": \"Window\",\n      \"title\": \"Artificer (native)\",\n      \"width\": 112,\n      \"minWidth\": 96,\n      \"height\": 72,\n      \"minHeight\": 56,\n      \"menuBar\": {\n        \"id\": \"menubar.main\",\n        \"type\": \"MenuBar\",\n        \"children\": [\n          {\n            \"id\": \"menu.app\",\n            \"type\": \"Menu\",\n            \"title\": \"Artificer (native)\",\n            \"children\": [\n              {\n                \"id\": \"menuitem.openSettings\",\n                \"type\": \"MenuItem\",\n                \"title\": \"Settings\",\n                \"action\": \"open_settings\"\n              },\n              {\n                \"id\": \"menuitem.quit\",\n                \"type\": \"MenuItem\",\n                \"title\": \"Quit\",\n                \"action\": \"quit_app\"\n              }\n            ]\n          },\n          {\n            \"id\": \"menu.file\",\n            \"type\": \"Menu\",\n            \"title\": \"File\",\n            \"children\": [\n              {\n                \"id\": \"menuitem.save\",\n                \"type\": \"MenuItem\",\n                \"title\": \"Save\",\n                \"action\": \"save_document\",\n                \"shortcut\": \"cmd+s\"\n              }\n            ]\n          }\n        ]\n      },\n      \"toolbar\": {\n        \"id\": \"toolbar.main\",\n        \"type\": \"Toolbar\",\n        \"children\": [\n          {\n            \"id\": \"toolbar.button.save\",\n            \"type\": \"Button\",\n            \"title\": \"Save\",\n            \"action\": \"save_document\"\n          },\n          {\n            \"id\": \"toolbar.spacer.1\",\n            \"type\": \"Spacer\"\n          },\n          {\n            \"id\": \"toolbar.button.settings\",\n            \"type\": \"Button\",\n            \"title\": \"Settings\",\n            \"action\": \"open_settings\"\n          }\n        ]\n      },\n      \"content\": {\n        \"id\": \"content.main\",\n        \"type\": \"Content\",\n        \"child\": {\n          \"id\": \"stack.root\",\n          \"type\": \"Stack\",\n          \"axis\": \"vertical\",\n          \"spacing\": 16,\n          \"children\": [\n            {\n              \"id\": \"section.hero\",\n              \"type\": \"Section\",\n              \"title\": \"Overview\",\n              \"child\": {\n                \"id\": \"stack.hero\",\n                \"type\": \"Stack\",\n                \"axis\": \"vertical\",\n                \"spacing\": 12,\n                \"children\": [\n                  {\n                    \"id\": \"text.headline\",\n                    \"type\": \"Text\",\n                    \"style\": \"title\",\n                    \"value\": \"Artificer (native)\"\n                  },\n                  {\n                    \"id\": \"text.summary\",\n                    \"type\": \"Text\",\n                    \"style\": \"body\",\n                    \"value\": \"Native desktop app scaffolded by App Forge.\"\n                  },\n                  {\n                    \"id\": \"group.form\",\n                    \"type\": \"Group\",\n                    \"title\": \"Quick action\",\n                    \"child\": {\n                      \"id\": \"form.settings\",\n                      \"type\": \"Form\",\n                      \"children\": [\n                        {\n                          \"id\": \"input.projectName\",\n                          \"type\": \"Input\",\n                          \"label\": \"Project name\",\n                          \"stateKey\": \"project_name\",\n                          \"placeholder\": \"Artificer (native)\"\n                        },\n                        {\n                          \"id\": \"button.primary\",\n                          \"type\": \"Button\",\n                          \"title\": \"Save draft\",\n                          \"action\": \"save_document\"\n                        }\n                      ]\n                    }\n                  }\n                ]\n              }\n            }\n          ]\n        }\n      },\n      \"statusBar\": {\n        \"id\": \"statusbar.main\",\n        \"type\": \"StatusBar\",\n        \"children\": [\n          {\n            \"id\": \"statusbar.text\",\n            \"type\": \"Text\",\n            \"style\": \"caption\",\n            \"value\": \"Ready\"\n          }\n        ]\n      }\n    }\n  },\n  \"extensions\": []\n}\n";

static void activate(GtkApplication *app, gpointer user_data) {
  GtkWidget *window = gtk_application_window_new(app);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  GtkWidget *title = gtk_label_new("Artificer (native)");
  GtkWidget *summary = gtk_label_new("Generated from the canonical native desktop IR.");
  GtkWidget *targets = gtk_label_new("Targets: macos,linux");

  (void)user_data;
  (void)wizardry_app_ir;

  gtk_window_set_title(GTK_WINDOW(window), "Artificer (native)");
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
  GtkApplication *app = gtk_application_new("app.artificer-native", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
