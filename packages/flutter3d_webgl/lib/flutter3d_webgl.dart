/// WebGL2 as an implementation of `flutter3d_hardware`.
///
/// The second backend. Its value is not only that it runs on the web: it is the
/// first thing that can tell us whether the HAL is a seam or a description of
/// Impeller, because a fake backend can only confirm that an interface is
/// callable, never that it is implementable.
///
/// **Status: the device and the encoder are written; the shaders are not.** The
/// engine names its stages — `LightingModel.shaderName` and the renderer's
/// `require` calls — and every backend must ship a set answering to those
/// names. The other backend's are impellerc GLSL, and translating them to
/// GLSL ES 3.00 is the bulk of the remaining work. Until then this package can
/// drive the HAL but cannot draw this engine's scenes, and says so rather than
/// pretending.
library;

export 'src/open.dart';
export 'src/webgl_device.dart';
export 'src/webgl_shaders.dart';
