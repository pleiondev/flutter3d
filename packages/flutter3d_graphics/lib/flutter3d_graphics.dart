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
///  * no `flutter_gpu` import anywhere in this package, ever —
///    `flutter3d_graphics/test/no_backend_test.dart`;
///  * no `dart:ui` either, apart from one member on [GraphicsDevice] that has
///    to name it. The reason is written where the exception is.
///
/// When a second backend arrives, this package does not change. A translation
/// file appears in the new backend, and that is all.
library;

/// The device: textures, buffers, pipelines, passes.
export 'src/graphics_device.dart';

/// Recording a pass — state, bindings, draws.
export 'src/command_encoder.dart';

// Pass state as one value. No backend implements anything for it — see the
// file's header for why it is here rather than in the engine.
export 'src/pass_state.dart';

/// Enums, one per thing a caller has to name.
export 'src/formats.dart';

/// Opaque handles for the things a backend owns.
export 'src/geometry_buffer.dart';
export 'src/shader.dart';
export 'src/texture.dart';

/// How a texture is sampled.
export 'src/sampler.dart';

/// Reuse of render targets, and the description that makes two of them
/// interchangeable.
export 'src/render_target_pool.dart';
