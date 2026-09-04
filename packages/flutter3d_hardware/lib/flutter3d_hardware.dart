/// The graphics vocabulary `flutter3d` is written against.
///
/// **Nothing here names a graphics API.** That is the entire content of this
/// package: it is what a backend implements and what the engine talks to, so
/// that neither has to know about the other. `flutter3d_impeller` implements it over
/// `flutter_gpu`; a WebGL2 backend would implement it beside that, and the
/// engine would not change.
///
/// Two rules hold it in shape, and both are checked rather than intended:
///
///  * no `flutter_gpu` import anywhere in this package, ever, and none in its
///    pubspec either — `tool/structure.dart`'s "the hardware layer names no
///    graphics API" rule. It was a `no_backend_test.dart` in this package
///    until the arrangement rules moved into that scanner, and the citation
///    outlived the file;
///  * no `dart:ui` and no `package:flutter/` either, apart from the files
///    named in that same rule's `hardwareMayUseFlutter` — one member on
///    [GraphicsDevice] has to name it, and the reason is written where the
///    exception is.
///
/// When a second backend arrives, this package does not change. A translation
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
