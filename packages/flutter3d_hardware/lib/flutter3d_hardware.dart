/// The graphics vocabulary `flutter3d` is written against.
///
/// **Nothing here names a graphics API.** That is the entire content of this
/// package: it is what a backend implements and what the engine talks to, so
/// that neither has to know about the other. Three implement it —
/// `flutter3d_impeller` over `flutter_gpu`, `flutter3d_webgl` over WebGL2, and
/// `flutter3d_cpu`, a software rasteriser with no driver under it at all — and
/// the engine did not change for any of them.
///
/// Two rules hold it in shape, and both are checked rather than intended by
/// `tool/structure.dart`'s **"the hardware layer names no graphics API"** rule,
/// which reads every file in this package's `lib/`:
///
///  * no `flutter_gpu` import anywhere in this package, ever, and no dependency
///    on a backend in its pubspec either — the second because importing nothing
///    and depending on everything would pass a scan of the imports alone. Held
///    by `tool/structure.dart`'s "the hardware layer names no graphics API"
///    rule. It was a `no_backend_test.dart` in this package until the
///    arrangement rules moved into that scanner, and the citation outlived the
///    file by long enough to be quoted in three places;
///  * no `dart:ui` and no `package:flutter/` either, apart from the files
///    `hardwareMayUseFlutter` names. The reason is written where each exception
///    is.
///
/// That citation used to be `flutter3d_hardware/test/no_backend_test.dart`,
/// which has not existed since the boundary tests became one scanner — so the
/// evidence offered for the load-bearing half of the claim led nowhere, in the
/// file a fourth-backend author reads first.
///
/// When a fourth backend arrives, this package does not change. A translation
/// file appears in the new backend, and that is all.
library;

/// Recording a pass — state, bindings, draws.
export 'src/command_encoder.dart';

/// Enums, one per thing a caller has to name.
export 'src/formats.dart';

/// Opaque handles for the things a backend owns.
export 'src/geometry_buffer.dart';

/// The device: textures, buffers, pipelines, passes.
export 'src/graphics_device.dart';

/// How a texture is sampled.
export 'src/mip_chain.dart';
// Pass state as one value. No backend implements anything for it — see the
// file's header for why it is here rather than in the engine.
export 'src/pass_state.dart';

/// What a readback may ask for, checked once for every backend.
export 'src/readback.dart';

/// Reuse of render targets, and the description that makes two of them
/// interchangeable.
export 'src/render_target_pool.dart';
export 'src/sampler.dart';
export 'src/shader.dart';

/// A bundle that arrives as bytes: the container every backend reads its own
/// section of, and the refusal a device answers with when it cannot.
export 'src/shader_bundle.dart';
export 'src/texture.dart';
export 'src/vertex_layout_spec.dart';
