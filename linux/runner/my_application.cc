#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gunixsocketaddress.h>
#include <glib/gstdio.h>
#include <unistd.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Started by `--capture` with no window to hand it to: stay hidden until
  // the screenshot is in (or quit if it was cancelled).
  gboolean start_hidden;
  GSocketService* link;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---- screenshots ---------------------------------------------------------
// "takeScreenshot" steps the window aside and asks the desktop's screenshot
// service (xdg-desktop-portal) for a picture, with the desktop's own area
// picker. It answers with the picture's file path, or null if the person
// cancelled, and brings the window back either way.
//
// The window is hidden rather than minimised: tried on GNOME under Wayland,
// a window coming back from minimised stays unfocused (Wayland does not let
// a window take focus by itself), while one shown again gets the focus.

typedef struct {
  GtkWindow* window;
  FlMethodCall* call;
  GDBusConnection* bus;
  guint signal_id;
  gchar* token;
  gint x, y;  // where the window was, for X11; Wayland places it itself
  gboolean was_shown;  // false for a window started by --capture
} ShotRequest;

static void shot_done(ShotRequest* r, FlValue* result, const gchar* error) {
  if (r->signal_id != 0) {
    g_dbus_connection_signal_unsubscribe(r->bus, r->signal_id);
  }
  // GTK keeps a maximised or full-screen window so when it is shown again.
  // A window that was never shown is left to the Dart side, which shows it
  // with the picture or quits.
  if (r->was_shown) {
    gtk_window_move(r->window, r->x, r->y);
    gtk_widget_show(GTK_WIDGET(r->window));
    gtk_window_present(r->window);
  }
  if (error != nullptr) {
    fl_method_call_respond_error(r->call, "unavailable", error, nullptr,
                                 nullptr);
  } else {
    fl_method_call_respond_success(r->call, result, nullptr);
  }
  g_object_unref(r->call);
  g_object_unref(r->bus);
  g_free(r->token);
  g_free(r);
}

static void shot_response_cb(GDBusConnection* bus, const gchar* sender,
                             const gchar* path, const gchar* iface,
                             const gchar* signal, GVariant* params,
                             gpointer user_data) {
  ShotRequest* r = static_cast<ShotRequest*>(user_data);
  guint32 code = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(params, "(u@a{sv})", &code, &results);
  const gchar* uri = nullptr;
  g_autoptr(FlValue) value = fl_value_new_null();
  if (code == 0 && g_variant_lookup(results, "uri", "&s", &uri)) {
    g_autofree gchar* file = g_filename_from_uri(uri, nullptr, nullptr);
    if (file != nullptr) {
      g_clear_pointer(&value, fl_value_unref);
      value = fl_value_new_string(file);
    }
  }
  shot_done(r, value, nullptr);
}

static void shot_called_cb(GObject* source, GAsyncResult* res,
                           gpointer user_data) {
  ShotRequest* r = static_cast<ShotRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), res, &error);
  // On success the answer comes later, as the Response signal.
  if (reply == nullptr) shot_done(r, nullptr, error->message);
}

static gboolean shot_ask(gpointer user_data) {
  ShotRequest* r = static_cast<ShotRequest*>(user_data);
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(r->token));
  g_variant_builder_add(&options, "{sv}", "interactive",
                        g_variant_new_boolean(TRUE));
  g_dbus_connection_call(
      r->bus, "org.freedesktop.portal.Desktop",
      "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Screenshot",
      "Screenshot", g_variant_new("(sa{sv})", "", &options), nullptr,
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, shot_called_cb, r);
  return G_SOURCE_REMOVE;
}

static void take_screenshot(GtkWindow* window, FlMethodCall* call) {
  g_autoptr(GError) error = nullptr;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) {
    fl_method_call_respond_error(call, "unavailable", error->message, nullptr,
                                 nullptr);
    return;
  }
  ShotRequest* r = g_new0(ShotRequest, 1);
  r->window = window;
  r->call = FL_METHOD_CALL(g_object_ref(call));
  r->bus = bus;
  r->token = g_strdup_printf("thinkspace%u", g_random_int());
  // The answer arrives on a request object whose path the portal derives
  // from our bus name and the token, so listen there before asking.
  g_autofree gchar* sender =
      g_strdup(g_dbus_connection_get_unique_name(bus) + 1);
  g_strdelimit(sender, ".", '_');
  g_autofree gchar* path = g_strdup_printf(
      "/org/freedesktop/portal/desktop/request/%s/%s", sender, r->token);
  r->signal_id = g_dbus_connection_signal_subscribe(
      bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
      "Response", path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, shot_response_cb, r,
      nullptr);
  // Out of the way first, so the picture shows what is behind the window.
  r->was_shown = gtk_widget_get_visible(GTK_WIDGET(window));
  if (r->was_shown) {
    gtk_window_get_position(window, &r->x, &r->y);
    gtk_widget_hide(GTK_WIDGET(window));
  }
  g_timeout_add(400, shot_ask, r);
}

// ---- one shortcut, many windows -------------------------------------------
// Every window is its own process. Each listens on a socket of its own in
// $XDG_RUNTIME_DIR/thinkspace (private to the user) and notes in a file
// beside it when it last had the focus. `thinkspace --capture`, which a
// keyboard shortcut runs, hands the screenshot to the window used last and
// exits before Flutter starts; if no window answers, it carries on as a new
// window that takes the screenshot itself.

static gchar* link_dir() {
  return g_build_filename(g_get_user_runtime_dir(), "thinkspace", nullptr);
}

static gchar* link_file(gint pid, const gchar* ext) {
  g_autofree gchar* dir = link_dir();
  g_autofree gchar* name = g_strdup_printf("%d.%s", pid, ext);
  return g_build_filename(dir, name, nullptr);
}

static void note_used() {
  g_autofree gchar* path = link_file(getpid(), "used");
  g_autofree gchar* now = g_strdup_printf("%" G_GINT64_FORMAT, g_get_real_time());
  g_file_set_contents(path, now, -1, nullptr);
}

static gboolean focus_in_cb(GtkWidget* widget, GdkEvent* event,
                            gpointer user_data) {
  note_used();
  return FALSE;
}

static gboolean link_incoming_cb(GSocketService* service,
                                 GSocketConnection* connection, GObject* source,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  // A request is one short line, sent at once; never wait long for it.
  g_socket_set_timeout(g_socket_connection_get_socket(connection), 2);
  gchar buf[32] = {0};
  GInputStream* in = g_io_stream_get_input_stream(G_IO_STREAM(connection));
  gssize n = g_input_stream_read(in, buf, sizeof(buf) - 1, nullptr, nullptr);
  if (n > 0 && g_str_has_prefix(buf, "capture") && self->channel != nullptr) {
    fl_method_channel_invoke_method(self->channel, "capture", nullptr, nullptr,
                                    nullptr, nullptr);
    GOutputStream* out = g_io_stream_get_output_stream(G_IO_STREAM(connection));
    g_output_stream_write_all(out, "ok\n", 3, nullptr, nullptr, nullptr);
  }
  return TRUE;
}

static void link_start(MyApplication* self) {
  g_autofree gchar* dir = link_dir();
  if (g_mkdir_with_parents(dir, 0700) != 0) {
    g_warning("Screenshot shortcut link not started: no %s", dir);
    return;
  }
  g_autofree gchar* path = link_file(getpid(), "sock");
  g_unlink(path);
  g_autoptr(GSocketAddress) address = g_unix_socket_address_new(path);
  self->link = g_socket_service_new();
  g_autoptr(GError) error = nullptr;
  if (!g_socket_listener_add_address(G_SOCKET_LISTENER(self->link), address,
                                     G_SOCKET_TYPE_STREAM,
                                     G_SOCKET_PROTOCOL_DEFAULT, nullptr,
                                     nullptr, &error)) {
    g_warning("Screenshot shortcut link not started: %s", error->message);
    g_clear_object(&self->link);
    return;
  }
  g_signal_connect(self->link, "incoming", G_CALLBACK(link_incoming_cb), self);
  g_socket_service_start(self->link);
  note_used();
}

static void link_stop(MyApplication* self) {
  if (self->link == nullptr) return;
  g_socket_service_stop(self->link);
  g_clear_object(&self->link);
  g_autofree gchar* sock = link_file(getpid(), "sock");
  g_autofree gchar* used = link_file(getpid(), "used");
  g_unlink(sock);
  g_unlink(used);
}

typedef struct {
  gint64 used;
  gint pid;
} LinkEntry;

static gint newest_first(gconstpointer a, gconstpointer b) {
  const LinkEntry* x = static_cast<const LinkEntry*>(a);
  const LinkEntry* y = static_cast<const LinkEntry*>(b);
  return x->used < y->used ? 1 : x->used > y->used ? -1 : 0;
}

// Asks the window used last to take a screenshot. True if one agreed.
// Sockets nobody answers on are left over from a crash and are removed.
static gboolean forward_capture() {
  g_autofree gchar* dir = link_dir();
  GDir* d = g_dir_open(dir, 0, nullptr);
  if (d == nullptr) return FALSE;
  g_autoptr(GArray) entries = g_array_new(FALSE, FALSE, sizeof(LinkEntry));
  const gchar* name;
  while ((name = g_dir_read_name(d)) != nullptr) {
    if (!g_str_has_suffix(name, ".sock")) continue;
    LinkEntry e = {0, static_cast<gint>(g_ascii_strtoll(name, nullptr, 10))};
    if (e.pid <= 0) continue;
    g_autofree gchar* used = link_file(e.pid, "used");
    g_autofree gchar* text = nullptr;
    if (g_file_get_contents(used, &text, nullptr, nullptr)) {
      e.used = g_ascii_strtoll(text, nullptr, 10);
    }
    g_array_append_val(entries, e);
  }
  g_dir_close(d);
  g_array_sort(entries, newest_first);
  for (guint i = 0; i < entries->len; i++) {
    LinkEntry e = g_array_index(entries, LinkEntry, i);
    g_autofree gchar* path = link_file(e.pid, "sock");
    g_autoptr(GSocketAddress) address = g_unix_socket_address_new(path);
    g_autoptr(GSocketClient) client = g_socket_client_new();
    g_socket_client_set_timeout(client, 3);
    g_autoptr(GSocketConnection) connection = g_socket_client_connect(
        client, G_SOCKET_CONNECTABLE(address), nullptr, nullptr);
    if (connection == nullptr) {
      g_autofree gchar* used = link_file(e.pid, "used");
      g_unlink(path);
      g_unlink(used);
      continue;
    }
    GOutputStream* out = g_io_stream_get_output_stream(G_IO_STREAM(connection));
    GInputStream* in = g_io_stream_get_input_stream(G_IO_STREAM(connection));
    gchar reply[8] = {0};
    if (g_output_stream_write_all(out, "capture\n", 8, nullptr, nullptr,
                                  nullptr) &&
        g_input_stream_read(in, reply, sizeof(reply) - 1, nullptr, nullptr) >
            0 &&
        g_str_has_prefix(reply, "ok")) {
      return TRUE;
    }
  }
  return FALSE;
}

// Lets the Dart side put the project name in the window title, switch full
// screen on and off (it answers with whether it is now full screen), and
// take a screenshot (see above).
static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  if (g_strcmp0(fl_method_call_get_name(call), "setTitle") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      const gchar* title = fl_value_get_string(args);
      GtkWidget* titlebar = gtk_window_get_titlebar(window);
      if (titlebar != nullptr && GTK_IS_HEADER_BAR(titlebar)) {
        gtk_header_bar_set_title(GTK_HEADER_BAR(titlebar), title);
      }
      gtk_window_set_title(window, title);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(fl_method_call_get_name(call), "setFullscreen") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    gboolean on = fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                  fl_value_get_bool(args);
    if (on) {
      gtk_window_fullscreen(window);
    } else {
      gtk_window_unfullscreen(window);
    }
    g_autoptr(FlValue) state = fl_value_new_bool(on);
    fl_method_call_respond_success(call, state, nullptr);
  } else if (g_strcmp0(fl_method_call_get_name(call), "takeScreenshot") == 0) {
    take_screenshot(window, call);
  } else if (g_strcmp0(fl_method_call_get_name(call), "showWindow") == 0) {
    gtk_widget_show(GTK_WIDGET(window));
    gtk_window_present(window);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(fl_method_call_get_name(call), "quit") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    g_application_quit(g_application_get_default());
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (self->start_hidden) return;  // shown once the screenshot is in
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Thinkspace");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Thinkspace");
  }

  // Finds the installed icon (hicolor theme); harmless if it is not installed.
  gtk_window_set_default_icon_name("thinkspace");
  gtk_window_set_icon_name(window, "thinkspace");

  // The layout is tested down to this size; smaller would squeeze the panels.
  gtk_widget_set_size_request(GTK_WIDGET(window), 900, 560);
  gtk_window_set_default_size(window, 1440, 900);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  // Draw with Skia, not Impeller. On desktop OpenGL, Impeller smooths only
  // circles, rectangles and straight lines; any other filled or stroked path
  // (arrowheads, curves, pen strokes, rotated pictures) comes out with jagged
  // edges unless the driver offers multisampling, which most do not. Skia
  // smooths every edge itself.
  fl_dart_project_set_enable_impeller(project, FALSE);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "thinkspace/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, window_method_cb, window,
                                            nullptr);
  self->channel = channel;

  g_signal_connect(window, "focus-in-event", G_CALLBACK(focus_in_cb), nullptr);
  link_start(self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // A screenshot shortcut: give it to an open window if there is one.
  if (g_strv_contains(self->dart_entrypoint_arguments, "--capture")) {
    if (forward_capture()) {
      *exit_status = 0;
      return TRUE;
    }
    self->start_hidden = TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  link_stop(MY_APPLICATION(application));

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
