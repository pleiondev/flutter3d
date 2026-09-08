/// WebGPU as an implementation of `flutter3d_hardware`.
///
/// The fourth backend, and the first one whose API disagrees with the contract
/// about *when* a pipeline exists. Impeller, WebGL2 and the software rasteriser
/// all take cull mode, winding, depth compare and the blend equation as pass
/// state a draw can change; WebGPU takes every one of them as a field of the
/// pipeline object, alongside the attachment formats a pass only settles when
/// it is opened. So a backend here cannot build anything where the contract
/// says `createPipeline` — it records the stage pair, accumulates the setters,
/// and looks a real pipeline up at the draw. [WebGpuPipelineSignature] is that
/// lookup key, and it is why this barrel begins with a table rather than a
/// device.
///
/// **The device is in `flutter3d_webgpu_web.dart`, and the split is about the
/// VM.** Everything here is pure Dart, so a harness on the VM can hold the
/// translation and the signature to their answers without a browser; the device,
/// the encoder and the bindings import `dart:js_interop`, which the VM does not
/// have, and a barrel re-exporting one of those cannot be imported at all off
/// the web. An application imports the other file and calls `openWebGpu`.
///
/// **No status line here, deliberately.** `flutter3d_webgl`'s barrel carries a
/// paragraph saying what that backend can and cannot draw yet, and warns in its
/// own last sentence that the paragraph said the opposite for as long as the
/// shaders took to write. It is the first thing a reader meets on pub.dev and
/// nothing fails when it goes stale. What this package can draw is recorded
/// where it can be wrong out loud — in `CHANGELOG.md`, and in the tests.
library;

/// The WGSL sources and the reflection a bundle carries for this backend, as
/// one document a packer writes and a device reads. Exported because a device
/// is opened over it — `WebGpuDevice.create` takes the stages — and because a
/// tool that packs a bundle for this backend needs the encoder.
export 'src/webgpu_bundle_section.dart';

/// The translation between the contract's vocabulary and WebGPU's own
/// enumeration strings. Pure Dart: nothing in it reaches for `dart:js_interop`
/// or `package:web`, so every answer is asserted on the VM rather than only in
/// a browser with a GPU.
///
/// **`webgpu_interop.dart` is deliberately not exported beside it, and the
/// reason is this file's own platform.** A barrel that re-exports a library
/// importing `dart:js_interop` cannot be imported on the VM at all, and the
/// table's tests are the ones that run in a second and catch a typo in
/// `"less-equal"` without a GPU. So the bindings are reached through
/// `flutter3d_webgpu_web.dart`, by whoever is opening a device, and this barrel
/// stays importable everywhere.
export 'src/webgpu_formats.dart';

/// What a draw looks a pipeline up by, and the map it looks it up in. Pure Dart
/// for the same reason the table is, and asserted the same way: which two
/// states are one pipeline and which are two is a question about this file
/// rather than about a browser.
export 'src/webgpu_pipeline_cache.dart';

/// A compiled stage, a pipeline over a pair of them, and the library that
/// resolves a name into the first. Everything but turning text into a module,
/// which is the device's through `WgslModuleCompiler` — so the vertex layout
/// arithmetic and the refusals load and are asserted on the VM.
export 'src/webgpu_shaders.dart';
