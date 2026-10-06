#ifndef FLUTTER_PLUGIN_PAD_INPUT_PLUGIN_H_
#define FLUTTER_PLUGIN_PAD_INPUT_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <Xinput.h>

#include <array>
#include <memory>
#include <optional>

namespace pad_input {

// Reads the four XInput user indices and forwards what they say.
//
// XInput has no events: a pad is asked what it is doing. So the window is
// given a timer while Dart listens, and each tick asks every connected pad
// and sends a sample when its packet number moved. The values go out as
// XInput reports them — sticks −32768…32767, triggers 0…255, the buttons'
// bit mask — and `lib/src/desktop_mapping.dart` decides what they mean,
// including that XInput's stick y is positive upwards. Nothing here
// decides anything, as on the other platforms.
class PadInputPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit PadInputPlugin(flutter::PluginRegistrarWindows* registrar);
  ~PadInputPlugin() override;

  PadInputPlugin(const PadInputPlugin&) = delete;
  PadInputPlugin& operator=(const PadInputPlugin&) = delete;

 private:
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  void Listen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);
  void Cancel();
  void Poll();
  HWND Window() const;

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  int window_proc_id_ = -1;
  bool polling_ = false;
  std::array<bool, XUSER_MAX_COUNT> connected_{};
  std::array<DWORD, XUSER_MAX_COUNT> packet_{};
  // Asking an index nothing is plugged into is slow — XInput looks for
  // the device every time — so an empty one is asked once a second, not
  // every tick.
  unsigned ticks_ = 0;
};

}  // namespace pad_input

#endif  // FLUTTER_PLUGIN_PAD_INPUT_PLUGIN_H_
