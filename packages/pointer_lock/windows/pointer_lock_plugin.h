#ifndef FLUTTER_PLUGIN_POINTER_LOCK_PLUGIN_H_
#define FLUTTER_PLUGIN_POINTER_LOCK_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>

#include <memory>
#include <optional>

namespace pointer_lock {

// Locks the pointer to the window and reports its motion as relative deltas.
//
// The motion comes from Raw Input, the mouse's own counts before Windows
// accelerates them or stops them at the edge of the screen — so a turn
// does not end where the cursor would have hit a wall. `ClipCursor` keeps
// the hidden cursor inside the window, so a click while captured cannot
// land on another application.
//
// As on macOS, this object outlives a Dart hot restart, which is why
// `reset` can let go of a pointer the restarted Dart no longer knows it
// holds.
class PointerLockPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit PointerLockPlugin(flutter::PluginRegistrarWindows* registrar);
  ~PointerLockPlugin() override;

  PointerLockPlugin(const PointerLockPlugin&) = delete;
  PointerLockPlugin& operator=(const PointerLockPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  void Capture();
  // `notify`: whether Dart is told — false when Dart asked and knows.
  void Release(bool notify);
  void Clip();
  HWND Window() const;

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  int window_proc_id_ = -1;
  bool captured_ = false;
  // `ShowCursor` counts, as `NSCursor.hide` does: hiding twice needs
  // showing twice, and showing without having hidden breaks the next hide.
  bool cursor_hidden_ = false;
};

}  // namespace pointer_lock

#endif  // FLUTTER_PLUGIN_POINTER_LOCK_PLUGIN_H_
