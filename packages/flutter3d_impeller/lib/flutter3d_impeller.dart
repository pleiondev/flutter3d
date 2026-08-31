/// `flutter_gpu` as an implementation of `flutter3d_hardware`.
///
/// An application constructs [GpuRenderBackend] and hands it to
/// `Renderer.create`. Nothing else in the stack names `flutter_gpu`, which is
/// the property this package exists to hold: the engine is written against the
/// HAL, and swapping this out for another backend is a change to one line of
/// application wiring.
library;

export 'src/gpu_device.dart';
export 'src/gpu_formats.dart';
export 'src/gpu_texture.dart';
