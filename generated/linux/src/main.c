/* Generated from templates/linux/main.c.template. Regenerate with scripts/render-native-desktop.sh. */
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

static const char *fallback_project_dir = "/Users/andersaamodt/git/artificer";

typedef struct {
  GtkWidget *window;
  GtkWidget *output;
  GtkWidget *status;
} AppState;

static char *backend_path(void) {
  const char *override = g_getenv("ARTIFICER_NATIVE_BACKEND");
  if (override != NULL && g_file_test(override, G_FILE_TEST_IS_EXECUTABLE)) {
    return g_strdup(override);
  }
  return g_build_filename(fallback_project_dir, "scripts", "artificer-native-backend.sh", NULL);
}

static void set_output(AppState *state, const char *text) {
  GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(state->output));
  gtk_text_buffer_set_text(buffer, text != NULL ? text : "", -1);
}

static void run_backend(AppState *state, const char *action) {
  char *backend = backend_path();
  char *stdout_text = NULL;
  char *stderr_text = NULL;
  GError *error = NULL;
  int status = 0;
  char *argv[] = { "/bin/sh", backend, (char *)action, NULL };

  gtk_label_set_text(GTK_LABEL(state->status), "Running...");
  if (!g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, &stdout_text, &stderr_text, &status, &error)) {
    set_output(state, error != NULL ? error->message : "Backend launch failed.");
    gtk_label_set_text(GTK_LABEL(state->status), "Backend failed.");
    if (error != NULL) {
      g_error_free(error);
    }
  } else if (status != 0) {
    set_output(state, stderr_text != NULL && strlen(stderr_text) > 0 ? stderr_text : stdout_text);
    gtk_label_set_text(GTK_LABEL(state->status), "Backend returned an error.");
  } else {
    set_output(state, stdout_text);
    gtk_label_set_text(GTK_LABEL(state->status), "Ready");
  }

  g_free(stdout_text);
  g_free(stderr_text);
  g_free(backend);
}

static void on_doctor(GtkButton *button, gpointer user_data) {
  (void)button;
  run_backend((AppState *)user_data, "doctor");
}

static void on_projects(GtkButton *button, gpointer user_data) {
  (void)button;
  run_backend((AppState *)user_data, "projects");
}

static void on_automations(GtkButton *button, gpointer user_data) {
  (void)button;
  run_backend((AppState *)user_data, "automation-daemon-status");
}

static void on_open_web(GtkButton *button, gpointer user_data) {
  (void)button;
  run_backend((AppState *)user_data, "open-web");
}

static void activate(GtkApplication *app, gpointer user_data) {
  (void)user_data;
  AppState *state = g_new0(AppState, 1);
  GtkWidget *window = gtk_application_window_new(app);
  GtkWidget *main = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  GtkWidget *doctor = gtk_button_new_with_label("Health");
  GtkWidget *projects = gtk_button_new_with_label("Workspaces");
  GtkWidget *automations = gtk_button_new_with_label("Daemon");
  GtkWidget *open_web = gtk_button_new_with_label("Hosted Artificer");
  GtkWidget *scrolled = gtk_scrolled_window_new();
  GtkWidget *output = gtk_text_view_new();
  GtkWidget *status = gtk_label_new("Ready");

  state->window = window;
  state->output = output;
  state->status = status;

  gtk_window_set_title(GTK_WINDOW(window), "Artificer");
  gtk_window_set_default_size(GTK_WINDOW(window), 1120, 720);
  gtk_window_set_child(GTK_WINDOW(window), main);

  gtk_widget_set_margin_top(toolbar, 10);
  gtk_widget_set_margin_bottom(toolbar, 10);
  gtk_widget_set_margin_start(toolbar, 10);
  gtk_widget_set_margin_end(toolbar, 10);
  gtk_box_append(GTK_BOX(toolbar), doctor);
  gtk_box_append(GTK_BOX(toolbar), projects);
  gtk_box_append(GTK_BOX(toolbar), automations);
  gtk_box_append(GTK_BOX(toolbar), open_web);
  gtk_box_append(GTK_BOX(main), toolbar);

  gtk_text_view_set_editable(GTK_TEXT_VIEW(output), FALSE);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(output), TRUE);
  gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled), output);
  gtk_widget_set_vexpand(scrolled, TRUE);
  gtk_box_append(GTK_BOX(main), scrolled);

  gtk_widget_set_margin_top(status, 6);
  gtk_widget_set_margin_bottom(status, 6);
  gtk_widget_set_margin_start(status, 10);
  gtk_widget_set_margin_end(status, 10);
  gtk_label_set_xalign(GTK_LABEL(status), 0.0f);
  gtk_box_append(GTK_BOX(main), status);

  g_signal_connect(doctor, "clicked", G_CALLBACK(on_doctor), state);
  g_signal_connect(projects, "clicked", G_CALLBACK(on_projects), state);
  g_signal_connect(automations, "clicked", G_CALLBACK(on_automations), state);
  g_signal_connect(open_web, "clicked", G_CALLBACK(on_open_web), state);

  run_backend(state, "doctor");
  gtk_window_present(GTK_WINDOW(window));
}

int main(int argc, char **argv) {
  GtkApplication *app = gtk_application_new("app.artificer-native", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);
  return status;
}
