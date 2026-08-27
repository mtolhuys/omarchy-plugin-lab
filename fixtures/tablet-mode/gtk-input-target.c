#include <gtk/gtk.h>

static const char *result_path;
static const char *activated_path;

static void write_text(GtkEditable *editable, gpointer unused) {
  (void)unused;
  const char *text = gtk_editable_get_text(editable);
  g_file_set_contents(result_path, text, -1, NULL);
}

static void activated(GtkEntry *entry, gpointer unused) {
  (void)entry;
  (void)unused;
  g_file_set_contents(activated_path, "activated\n", -1, NULL);
}

static void app_activate(GtkApplication *app, gpointer unused) {
  (void)unused;
  GtkWidget *window = gtk_application_window_new(app);
  GtkWidget *entry = gtk_entry_new();
  gtk_window_set_title(GTK_WINDOW(window), "Tablet GTK Input");
  gtk_window_set_default_size(GTK_WINDOW(window), 760, 220);
  gtk_widget_set_margin_top(entry, 60);
  gtk_widget_set_margin_bottom(entry, 60);
  gtk_widget_set_margin_start(entry, 60);
  gtk_widget_set_margin_end(entry, 60);
  gtk_window_set_child(GTK_WINDOW(window), entry);
  g_signal_connect(entry, "changed", G_CALLBACK(write_text), NULL);
  g_signal_connect(entry, "activate", G_CALLBACK(activated), NULL);
  gtk_window_present(GTK_WINDOW(window));
  gtk_widget_grab_focus(entry);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  result_path = argv[1];
  activated_path = argv[2];
  GtkApplication *app = gtk_application_new("dev.omarchy.TabletGtkInput", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(app_activate), NULL);
  int status = g_application_run(G_APPLICATION(app), 1, argv);
  g_object_unref(app);
  return status;
}
