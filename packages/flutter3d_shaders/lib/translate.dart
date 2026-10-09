/// The engine's GLSL in the dialects the web backends read: GLSL ES 3.00 for
/// WebGL2, and the prepared GLSL and reflection WebGPU's section is made of.
///
/// **Pure text in, text out**, with no `dart:io` anywhere under it, so a
/// browser test and a backend's own library can import it as readily as a
/// build script. What runs a compiler is `compile.dart`.
///
/// **Here rather than in the two backends that wrote it** — P8. A project's
/// build hook compiles its own materials for every backend, and the hook is a
/// process that cannot resolve a package declaring the Flutter SDK, which
/// both `flutter3d_webgl` and `flutter3d_webgpu` do. None of these files ever
/// needed the SDK; only the packages they lived in did.
library;

export 'src/bundle_section_exception.dart';
export 'src/glsl_to_wgsl.dart';
export 'src/glsl_translate.dart';
export 'src/webgl_bundle_section.dart';
export 'src/wgsl_section.dart';
