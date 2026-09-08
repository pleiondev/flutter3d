/// WebGPU as an implementation of `flutter3d_hardware`.
///
/// The fourth backend, and the first one whose API disagrees with the contract
/// about *when* a pipeline exists. Impeller, WebGL2 and the software rasteriser
/// all take cull mode, winding, depth compare and the blend equation as pass
/// state a draw can change; WebGPU takes every one of them as a field of the
/// pipeline object, alongside the attachment formats a pass only settles when
/// it is opened. So a backend here cannot build anything where the contract
/// says `createPipeline` — it records the stage pair, accumulates the setters,
/// and looks a real pipeline up at the draw. [WebGpuPipelineKey] is that
/// lookup key, and it is why this barrel begins with a table rather than a
/// device.
///
/// **No status line here, deliberately.** `flutter3d_webgl`'s barrel carries a
/// paragraph saying what that backend can and cannot draw yet, and warns in its
/// own last sentence that the paragraph said the opposite for as long as the
/// shaders took to write. It is the first thing a reader meets on pub.dev and
/// nothing fails when it goes stale. What this package can draw is recorded
/// where it can be wrong out loud — in `CHANGELOG.md`, and in the tests.
library;

/// The translation between the contract's vocabulary and WebGPU's own
/// enumeration strings. Pure Dart: nothing in it reaches for `dart:js_interop`
/// or `package:web`, so every answer is asserted on the VM rather than only in
/// a browser with a GPU.
///
/// **`webgpu_interop.dart` is deliberately not exported beside it, and the
/// reason is this file's own platform.** A barrel that re-exports a library
/// importing `dart:js_interop` cannot be imported on the VM at all, and the
/// table's tests are the ones that run in a second and catch a typo in
/// `"less-equal"` without a GPU. So the bindings are reached at
/// `package:flutter3d_webgpu/src/webgpu_interop.dart`, by the device and the
/// encoder that will sit next to them, and this barrel stays importable
/// everywhere.
export 'src/webgpu_formats.dart';
