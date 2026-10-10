// Locks the pointer to the window and reports its motion as relative deltas.
//
// GTK 3 has no relative-pointer call of its own, so this does what games on
// X11 have long done: the seat is grabbed with a blank cursor, the pointer
// is warped to the window's centre, and each motion is reported as how far
// it got from there before being warped back. The warp's own motion lands
// exactly on the centre and is skipped. Under Wayland a client may not warp
// the pointer, and the grab alone keeps it in the window: the deltas are
// then the cursor's own motion until it meets the window's edge — a
// known limit, and the reason `zwp_relative_pointer` is the next step here.
//
// As on macOS, this object outlives a Dart hot restart, which is why
// `reset` can let go of a pointer the restarted Dart no longer knows it
// holds.
#include "include/pointer_lock/pointer_lock_plugin.h"

#include <gtk/gtk.h>

#define POINTER_LOCK_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pointer_lock_plugin_get_type(), \
                              PointerLockPlugin))

namespace {

// State codes shared with the Dart side, as on macOS.
constexpr int kStateReleased = 0;
constexpr int kStateCaptured = 1;

}  // namespace

struct _PointerLockPlugin {
  GObject parent_instance;
  FlMethodChannel* methods;
  FlEventChannel* events;
  GtkWidget* view;
  gboolean listening;
  gboolean captured;
  GdkSeat* seat;
  gint centre_x;
  gint centre_y;
};

G_DEFINE_TYPE(PointerLockPlugin, pointer_lock_plugin, g_object_get_type())

static void send_state(PointerLockPlugin* self, int state) {
  if (!self->listening) return;
  g_autoptr(FlValue) value = fl_value_new_int(state);
  fl_event_channel_send(self->events, value, nullptr, nullptr);
}

// The view's centre on the screen, and the pointer put there.
static void centre(PointerLockPlugin* self) {
  GdkWindow* window = gtk_widget_get_window(self->view);
  if (window == nullptr || self->seat == nullptr) return;
  gint x, y;
  gdk_window_get_origin(window, &x, &y);
  self->centre_x = x + gtk_widget_get_allocated_width(self->view) / 2;
  self->centre_y = y + gtk_widget_get_allocated_height(self->view) / 2;
  GdkDevice* pointer = gdk_seat_get_pointer(self->seat);
  gdk_device_warp(pointer, gtk_widget_get_screen(self->view), self->centre_x,
                  self->centre_y);
}

static void capture(PointerLockPlugin* self) {
  if (self->captured || self->view == nullptr) return;
  GdkWindow* window = gtk_widget_get_window(self->view);
  if (window == nullptr) return;
  GdkDisplay* display = gdk_window_get_display(window);
  GdkSeat* seat = gdk_display_get_default_seat(display);
  g_autoptr(GdkCursor) blank =
      gdk_cursor_new_for_display(display, GDK_BLANK_CURSOR);
  const GdkGrabStatus status =
      gdk_seat_grab(seat, window, GDK_SEAT_CAPABILITY_ALL_POINTING, TRUE,
                    blank, nullptr, nullptr, nullptr);
  if (status != GDK_GRAB_SUCCESS) return;
  self->seat = seat;
  self->captured = TRUE;
  centre(self);
  send_state(self, kStateCaptured);
}

// `notify`: whether Dart is told — false when Dart asked and knows.
static void release(PointerLockPlugin* self, gboolean notify) {
  if (self->seat != nullptr) gdk_seat_ungrab(self->seat);
  self->seat = nullptr;
  const gboolean was = self->captured;
  self->captured = FALSE;
  if (notify && was) send_state(self, kStateReleased);
}

static gboolean motion_cb(GtkWidget*, GdkEventMotion* event,
                          gpointer user_data) {
  PointerLockPlugin* self = POINTER_LOCK_PLUGIN(user_data);
  if (!self->captured) return FALSE;
  const gint x = static_cast<gint>(event->x_root);
  const gint y = static_cast<gint>(event->y_root);
  // The warp arriving, not the player moving.
  if (x == self->centre_x && y == self->centre_y) return TRUE;
  if (self->listening) {
    const double values[2] = {event->x_root - self->centre_x,
                              event->y_root - self->centre_y};
    g_autoptr(FlValue) list = fl_value_new_float_list(values, 2);
    fl_event_channel_send(self->events, list, nullptr, nullptr);
  }
  centre(self);
  // Flutter is not told the cursor moved: it is hidden, and a hover that
  // jumps to the centre every event is nothing a widget should act on.
  return TRUE;
}

static gboolean focus_out_cb(GtkWidget*, GdkEvent*, gpointer user_data) {
  // Release rather than pause: a hidden, grabbed pointer over another
  // application is one the player cannot get back.
  release(POINTER_LOCK_PLUGIN(user_data), TRUE);
  return FALSE;
}

static void method_cb(FlMethodChannel*, FlMethodCall* call,
                      gpointer user_data) {
  PointerLockPlugin* self = POINTER_LOCK_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "capture") == 0) {
    capture(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "release") == 0 ||
             g_strcmp0(method, "reset") == 0) {
    // `reset` is Dart's first call, and does something only after a hot
    // restart left the pointer captured.
    release(self, FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "isCaptured") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(self->captured);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static FlMethodErrorResponse* listen_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  POINTER_LOCK_PLUGIN(user_data)->listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  PointerLockPlugin* self = POINTER_LOCK_PLUGIN(user_data);
  // Losing the stream means Dart is gone or reloading; holding the pointer
  // past that strands the cursor.
  release(self, FALSE);
  self->listening = FALSE;
  return nullptr;
}

static void pointer_lock_plugin_dispose(GObject* object) {
  PointerLockPlugin* self = POINTER_LOCK_PLUGIN(object);
  release(self, FALSE);
  g_clear_object(&self->methods);
  g_clear_object(&self->events);
  G_OBJECT_CLASS(pointer_lock_plugin_parent_class)->dispose(object);
}

static void pointer_lock_plugin_class_init(PointerLockPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pointer_lock_plugin_dispose;
}

static void pointer_lock_plugin_init(PointerLockPlugin*) {}

void pointer_lock_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PointerLockPlugin* plugin = POINTER_LOCK_PLUGIN(
      g_object_new(pointer_lock_plugin_get_type(), nullptr));

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->methods = fl_method_channel_new(
      messenger, "dev.flutter3d/pointer_lock", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->methods, method_cb, g_object_ref(plugin), g_object_unref);
  plugin->events = fl_event_channel_new(
      messenger, "dev.flutter3d/pointer_lock/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->events, listen_cb, cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    plugin->view = GTK_WIDGET(view);
    gtk_widget_add_events(plugin->view, GDK_POINTER_MOTION_MASK);
    g_signal_connect(plugin->view, "motion-notify-event",
                     G_CALLBACK(motion_cb), plugin);
    GtkWidget* window = gtk_widget_get_toplevel(plugin->view);
    g_signal_connect(window, "focus-out-event", G_CALLBACK(focus_out_cb),
                     plugin);
  }

  g_object_unref(plugin);
}
