#include "pointer_lock_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <vector>

namespace pointer_lock {

namespace {

// State codes shared with the Dart side, as on macOS.
constexpr int kStateReleased = 0;
constexpr int kStateCaptured = 1;

}  // namespace

void PointerLockPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<PointerLockPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

PointerLockPlugin::PointerLockPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  methods_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "dev.flutter3d/pointer_lock",
      &flutter::StandardMethodCodec::GetInstance());
  methods_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  events_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "dev.flutter3d/pointer_lock/events",
      &flutter::StandardMethodCodec::GetInstance());
  events_->SetStreamHandler(
      std::make_unique<
          flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            // Losing the stream means Dart is gone or reloading; holding
            // the pointer past that strands the cursor.
            Release(false);
            sink_.reset();
            return nullptr;
          }));

  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

PointerLockPlugin::~PointerLockPlugin() {
  Release(false);
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

HWND PointerLockPlugin::Window() const {
  auto* view = registrar_->GetView();
  return view == nullptr ? nullptr
                         : GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void PointerLockPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "capture") {
    Capture();
    result->Success();
  } else if (method == "release" || method == "reset") {
    // `reset` is Dart's first call, and does something only after a hot
    // restart left the pointer captured.
    Release(false);
    result->Success();
  } else if (method == "isCaptured") {
    result->Success(flutter::EncodableValue(captured_));
  } else {
    result->NotImplemented();
  }
}

void PointerLockPlugin::Capture() {
  if (captured_) return;
  HWND window = Window();
  if (window == nullptr) return;

  RAWINPUTDEVICE mouse{};
  mouse.usUsagePage = 0x01;  // generic desktop
  mouse.usUsage = 0x02;      // mouse
  mouse.dwFlags = 0;
  mouse.hwndTarget = window;
  if (!RegisterRawInputDevices(&mouse, 1, sizeof(mouse))) return;

  if (!cursor_hidden_) {
    ShowCursor(FALSE);
    cursor_hidden_ = true;
  }
  Clip();
  captured_ = true;
  if (sink_) sink_->Success(flutter::EncodableValue(kStateCaptured));
}

void PointerLockPlugin::Clip() {
  HWND window = Window();
  if (window == nullptr) return;
  RECT client;
  GetClientRect(window, &client);
  POINT corners[2] = {{client.left, client.top},
                      {client.right, client.bottom}};
  MapWindowPoints(window, nullptr, corners, 2);
  // The middle of the window, and only that: the hidden cursor never
  // drifts onto the frame, where a click would resize instead of shoot.
  const LONG x = (corners[0].x + corners[1].x) / 2;
  const LONG y = (corners[0].y + corners[1].y) / 2;
  const RECT centre = {x, y, x + 1, y + 1};
  SetCursorPos(x, y);
  ClipCursor(&centre);
}

void PointerLockPlugin::Release(bool notify) {
  if (captured_) {
    RAWINPUTDEVICE mouse{};
    mouse.usUsagePage = 0x01;
    mouse.usUsage = 0x02;
    mouse.dwFlags = RIDEV_REMOVE;
    mouse.hwndTarget = nullptr;
    RegisterRawInputDevices(&mouse, 1, sizeof(mouse));
    ClipCursor(nullptr);
  }
  if (cursor_hidden_) {
    ShowCursor(TRUE);
    cursor_hidden_ = false;
  }
  const bool was = captured_;
  captured_ = false;
  if (notify && was && sink_) {
    sink_->Success(flutter::EncodableValue(kStateReleased));
  }
}

std::optional<LRESULT> PointerLockPlugin::HandleWindowProc(HWND, UINT message,
                                                           WPARAM wparam,
                                                           LPARAM lparam) {
  switch (message) {
    case WM_INPUT: {
      if (!captured_ || !sink_) return std::nullopt;
      RAWINPUT raw{};
      UINT size = sizeof(raw);
      if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT, &raw,
                          &size, sizeof(RAWINPUTHEADER)) == static_cast<UINT>(-1)) {
        return std::nullopt;
      }
      if (raw.header.dwType != RIM_TYPEMOUSE) return std::nullopt;
      // Absolute motion is a tablet or a remote desktop, whose numbers are
      // positions, not counts; reading them as deltas would spin the view.
      if (raw.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE) return std::nullopt;
      const LONG dx = raw.data.mouse.lLastX;
      const LONG dy = raw.data.mouse.lLastY;
      if (dx == 0 && dy == 0) return std::nullopt;
      // Binary, as on macOS: the hot path at a thousand reports a second.
      sink_->Success(flutter::EncodableValue(std::vector<double>{
          static_cast<double>(dx), static_cast<double>(dy)}));
      return std::nullopt;
    }
    case WM_ACTIVATE:
      // Release rather than pause: a hidden, clipped cursor over another
      // application is one the player cannot get back.
      if (LOWORD(wparam) == WA_INACTIVE) Release(true);
      return std::nullopt;
    case WM_SIZE:
    case WM_MOVE:
      if (captured_) Clip();
      return std::nullopt;
  }
  return std::nullopt;
}

}  // namespace pointer_lock
