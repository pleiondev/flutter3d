// Reads `/dev/input/js0` to `js3` and forwards what they say.
//
// The kernel's joystick interface delivers events — a button's new state,
// an axis' new value — so the descriptors are opened without blocking and
// drained on a GLib timer while Dart listens. Each event goes out as the
// kernel wrote it: its type, its number and its value, three doubles, in
// one list per pad per tick behind the pad's slot. Which number is which
// control is the `xpad` driver's layout, and that and everything else the
// numbers mean is `lib/src/desktop_mapping.dart`'s, as on the other
// platforms. A device that cannot be opened is no pad; one whose read
// fails with anything but "nothing yet" is gone.
#include "include/pad_input/pad_input_plugin.h"

#include <errno.h>
#include <fcntl.h>
#include <gtk/gtk.h>
#include <linux/joystick.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <vector>

#define PAD_INPUT_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pad_input_plugin_get_type(), \
                              PadInputPlugin))

namespace {

constexpr int kSlots = 4;
// About a hundred and twenty times a second, as on Windows.
constexpr guint kTickMilliseconds = 8;
// Looking for a pad that is not there is an `open` that fails; once a
// second is enough to notice one plugged in.
constexpr guint kScanEvery = 120;

}  // namespace

struct _PadInputPlugin {
  GObject parent_instance;
  FlEventChannel* channel;
  gboolean listening;
  guint timer;
  guint ticks;
  int fds[kSlots];
};

G_DEFINE_TYPE(PadInputPlugin, pad_input_plugin, g_object_get_type())

static void send_event(PadInputPlugin* self, const char* name, int slot) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "event", fl_value_new_string(name));
  if (slot >= 0) fl_value_set_string_take(map, "slot", fl_value_new_int(slot));
  fl_event_channel_send(self->channel, map, nullptr, nullptr);
}

static void close_slot(PadInputPlugin* self, int slot, gboolean tell) {
  if (self->fds[slot] < 0) return;
  close(self->fds[slot]);
  self->fds[slot] = -1;
  if (tell) send_event(self, "disconnected", slot);
}

static void scan(PadInputPlugin* self) {
  for (int slot = 0; slot < kSlots; slot++) {
    if (self->fds[slot] >= 0) continue;
    char path[32];
    snprintf(path, sizeof(path), "/dev/input/js%d", slot);
    const int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd < 0) continue;
    self->fds[slot] = fd;
    send_event(self, "connected", slot);
  }
}

static void drain(PadInputPlugin* self, int slot) {
  std::vector<double> sample = {static_cast<double>(slot)};
  struct js_event event;
  while (true) {
    const ssize_t got = read(self->fds[slot], &event, sizeof(event));
    if (got == static_cast<ssize_t>(sizeof(event))) {
      sample.push_back(event.type);
      sample.push_back(event.number);
      sample.push_back(event.value);
      continue;
    }
    if (got < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
      // Unplugged: what it sent first still counts, then it is gone.
      if (sample.size() > 1) {
        g_autoptr(FlValue) list =
            fl_value_new_float_list(sample.data(), sample.size());
        fl_event_channel_send(self->channel, list, nullptr, nullptr);
      }
      close_slot(self, slot, TRUE);
      return;
    }
    break;
  }
  if (sample.size() == 1) return;
  g_autoptr(FlValue) list =
      fl_value_new_float_list(sample.data(), sample.size());
  fl_event_channel_send(self->channel, list, nullptr, nullptr);
}

static gboolean tick(gpointer user_data) {
  PadInputPlugin* self = PAD_INPUT_PLUGIN(user_data);
  if (!self->listening) return G_SOURCE_REMOVE;
  if (self->ticks++ % kScanEvery == 0) scan(self);
  for (int slot = 0; slot < kSlots; slot++) {
    if (self->fds[slot] >= 0) drain(self, slot);
  }
  return G_SOURCE_CONTINUE;
}

static FlMethodErrorResponse* listen_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  PadInputPlugin* self = PAD_INPUT_PLUGIN(user_data);
  self->listening = TRUE;
  self->ticks = 0;
  if (self->timer == 0) {
    self->timer = g_timeout_add(kTickMilliseconds, tick, self);
  }
  // Whatever is already plugged in, now rather than a tick from now.
  scan(self);
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  PadInputPlugin* self = PAD_INPUT_PLUGIN(user_data);
  self->listening = FALSE;
  if (self->timer != 0) {
    g_source_remove(self->timer);
    self->timer = 0;
  }
  for (int slot = 0; slot < kSlots; slot++) close_slot(self, slot, FALSE);
  return nullptr;
}

// The window losing the keyboard: let go of every pad, as the other
// platforms do.
static gboolean focus_out_cb(GtkWidget*, GdkEvent*, gpointer user_data) {
  PadInputPlugin* self = PAD_INPUT_PLUGIN(user_data);
  if (self->listening) send_event(self, "relaxed", -1);
  return FALSE;
}

static void pad_input_plugin_dispose(GObject* object) {
  PadInputPlugin* self = PAD_INPUT_PLUGIN(object);
  cancel_cb(nullptr, nullptr, self);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(pad_input_plugin_parent_class)->dispose(object);
}

static void pad_input_plugin_class_init(PadInputPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pad_input_plugin_dispose;
}

static void pad_input_plugin_init(PadInputPlugin* self) {
  for (int slot = 0; slot < kSlots; slot++) self->fds[slot] = -1;
}

void pad_input_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PadInputPlugin* plugin =
      PAD_INPUT_PLUGIN(g_object_new(pad_input_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.flutter3d/gamepad/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->channel, listen_cb, cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    GtkWidget* window = gtk_widget_get_toplevel(GTK_WIDGET(view));
    g_signal_connect(window, "focus-out-event", G_CALLBACK(focus_out_cb),
                     plugin);
  }

  g_object_unref(plugin);
}
