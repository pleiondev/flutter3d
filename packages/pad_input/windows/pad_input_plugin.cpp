#include "pad_input_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <vector>

namespace pad_input {

namespace {

constexpr char kEventChannelName[] = "dev.flutter3d/gamepad/events";
constexpr UINT_PTR kTimerId = 0x70ad;
// About a hundred and twenty times a second: faster than any frame a game
// draws, so a press is never a frame late for being polled.
constexpr UINT kTimerMilliseconds = 8;
// One tick in a hundred and twenty: once a second, for an empty index.
constexpr unsigned kScanEvery = 120;

flutter::EncodableValue Event(const char* name, int slot) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("event")] = flutter::EncodableValue(name);
  if (slot >= 0) {
    map[flutter::EncodableValue("slot")] = flutter::EncodableValue(slot);
  }
  return flutter::EncodableValue(map);
}

}  // namespace

void PadInputPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<PadInputPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

PadInputPlugin::PadInputPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), kEventChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetStreamHandler(
      std::make_unique<
          flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            Listen(std::move(events));
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            Cancel();
            return nullptr;
          }));
  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

PadInputPlugin::~PadInputPlugin() {
  Cancel();
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

HWND PadInputPlugin::Window() const {
  auto* view = registrar_->GetView();
  return view == nullptr ? nullptr
                         : GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void PadInputPlugin::Listen(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  sink_ = std::move(sink);
  connected_.fill(false);
  packet_.fill(0);
  ticks_ = 0;
  HWND window = Window();
  if (window != nullptr && !polling_) {
    polling_ = SetTimer(window, kTimerId, kTimerMilliseconds, nullptr) != 0;
  }
  // Whatever is already plugged in, now rather than a second from now.
  Poll();
}

void PadInputPlugin::Cancel() {
  HWND window = Window();
  if (polling_ && window != nullptr) KillTimer(window, kTimerId);
  polling_ = false;
  sink_.reset();
}

std::optional<LRESULT> PadInputPlugin::HandleWindowProc(HWND, UINT message,
                                                        WPARAM wparam,
                                                        LPARAM) {
  switch (message) {
    case WM_TIMER:
      if (wparam != kTimerId) return std::nullopt;
      Poll();
      return 0;
    case WM_ACTIVATE:
      // The player went to another window: let go of every pad, as the
      // other platforms do, so a stick left half over does not keep
      // walking behind it.
      if (LOWORD(wparam) == WA_INACTIVE && sink_) {
        sink_->Success(Event("relaxed", -1));
      }
      return std::nullopt;
  }
  return std::nullopt;
}

void PadInputPlugin::Poll() {
  if (!sink_) return;
  const bool scan = ticks_++ % kScanEvery == 0;
  for (DWORD slot = 0; slot < XUSER_MAX_COUNT; slot++) {
    if (!connected_[slot] && !scan) continue;
    XINPUT_STATE state{};
    if (XInputGetState(slot, &state) != ERROR_SUCCESS) {
      if (connected_[slot]) {
        connected_[slot] = false;
        sink_->Success(Event("disconnected", static_cast<int>(slot)));
      }
      continue;
    }
    if (!connected_[slot]) {
      connected_[slot] = true;
      sink_->Success(Event("connected", static_cast<int>(slot)));
    } else if (state.dwPacketNumber == packet_[slot]) {
      continue;
    }
    packet_[slot] = state.dwPacketNumber;
    const XINPUT_GAMEPAD& pad = state.Gamepad;
    std::vector<double> sample = {
        static_cast<double>(slot),          static_cast<double>(pad.sThumbLX),
        static_cast<double>(pad.sThumbLY),  static_cast<double>(pad.sThumbRX),
        static_cast<double>(pad.sThumbRY),  static_cast<double>(pad.bLeftTrigger),
        static_cast<double>(pad.bRightTrigger),
        static_cast<double>(pad.wButtons),
    };
    sink_->Success(flutter::EncodableValue(sample));
  }
}

}  // namespace pad_input
