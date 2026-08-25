/// A `flutter3d_hardware` backend that rasterises in Dart.
///
/// Two hardware backends agreeing proves less than it looks like: both are
/// driven by a C API and both rasterise on a GPU, so an assumption shared by
/// graphics hardware would be invisible to the pair of them. This one shares
/// nothing with either — no driver, no shading language, no command buffer.
///
/// Whether that was really allowed is what running it answers.
library;

export 'src/cpu_device.dart';
export 'src/cpu_png.dart';
export 'src/cpu_shader.dart';
export 'src/cpu_shaders_builtin.dart';
export 'src/frame_difference.dart';
