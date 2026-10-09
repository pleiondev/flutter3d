/// The half of this backend that needs a browser: the device, the pass encoder
/// and the bindings under both.
///
/// **Separate from `flutter3d_webgpu.dart` because `dart:js_interop` is not a
/// library the Dart VM has**, and a barrel that re-exports one importing it
/// cannot be imported on the VM at all. The translation tables and the pipeline
/// signature are worth asserting whether or not there is a GPU in the room —
/// they are what catch a typo in `"less-equal"` in a second — so they stay in
/// the barrel that loads everywhere, and this one carries what only a browser
/// can run.
///
/// An application opens a device through [WebGpuDevice.open] — or lets an
/// engine's `DeviceRegistry` do it — and never touches anything else here.
library;

/// The device, and `WebGpuDevice.open`, the one call an application makes.
export 'src/webgpu_device.dart' show WebGpuDevice;

/// The widget `presentFrame` in `flutter3d_app` returns for this device.
export 'src/webgpu_frame_presenter.dart';

// The encoder, the JavaScript bindings (`GPU*`), the allocators and the
// handle types are not exported since 1.0: they are this backend's own
// business, and a browser API in a signature here would make every change
// to it a major release. The package's tests import them from `src/`.
