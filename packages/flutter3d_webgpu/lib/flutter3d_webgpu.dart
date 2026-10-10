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
/// the web. An application imports the other file and calls `WebGpuDevice.open`.
///
/// **No status line here, deliberately.** `flutter3d_webgl`'s barrel carries a
/// paragraph saying what that backend can and cannot draw yet, and warns in its
/// own last sentence that the paragraph said the opposite for as long as the
/// shaders took to write. It is the first thing a reader meets on pub.dev and
/// nothing fails when it goes stale. What this package can draw is recorded
/// where it can be wrong out loud — in `CHANGELOG.md`, and in the tests.
library;

/// The engine's compiled stage a material loaded at run time is spliced
/// into, for `RuntimeShaders`' `webGpuHost`. Pure Dart, as the table it reads
/// is.
export 'src/runtime_material_host.dart';

/// The stages a bundle carries for this backend, as a device reads them.
/// Exported because a device is opened over them — `WebGpuDevice.open` takes
/// the stages — and a page with a bundle of its own decodes them.
///
/// **The reflection classes are not** (`WebGpuStage`, `WebGpuBlock`,
/// `WebGpuBlockMember`, `WebGpuSampler`, `WebGpuAttribute`, and the encoder,
/// `encodeWebGpuSection`), since 1.0: they mirror what WGSL reflection
/// cannot say and change with it. The packing tools are this package's own and
/// import them from `src/`.
export 'src/webgpu_bundle_section.dart'
    show WebGpuSectionStages, decodeWebGpuSection;

// Everything else under `lib/src` — the translation tables (`gpu*`), the
// pipeline signature and cache, the shader library — is this backend's own
// business since 1.0, imported by its tests from `src/` and by nobody else:
// a WebGPU detail in this package's API would be a major release every time
// the browser's API moved.
