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
/// An application opens a device through [openWebGpu] and never touches
/// anything else here. The rest is exported because a backend is a package
/// somebody may have to debug from outside: the encoder's signature, the frame
/// arenas' counts and `WebGpuDevice.debugDrainErrors` are how a wrong picture
/// is turned into a sentence.
library;

/// The one call an application makes.
export 'src/open.dart';

/// The device.
export 'src/webgpu_device.dart';

/// One pass, accumulated and resolved at the draw.
export 'src/webgpu_encoder.dart';

/// The bindings under all of it, hand-written because `package:web` stops at
/// WebGPU's flag constants.
export 'src/webgpu_interop.dart';

/// Allocation, teardown, and the frame arenas that decide this backend's buffer
/// lifetimes. See the file's own header, which is where the argument for the
/// scheme is.
export 'src/webgpu_resources.dart';

/// The value types a handle carries here.
export 'src/webgpu_types.dart';
