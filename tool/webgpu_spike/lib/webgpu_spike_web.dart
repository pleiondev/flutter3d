/// The half of the spike that needs a browser: the device, the pass encoder and
/// the triangle they draw.
///
/// Separate from `webgpu_spike.dart` because `dart:js_interop` is not a library
/// the VM has, and the translation tables this package exists to state are worth
/// asserting whether or not there is a GPU in the room. See that file for what a
/// spike is and is not.
library;

export 'src/webgpu_interop.dart';
export 'src/webgpu_spike_device.dart';
export 'src/webgpu_spike_encoder.dart';
export 'src/webgpu_triangle.dart';
