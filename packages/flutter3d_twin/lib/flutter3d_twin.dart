/// Digital-twin data sources — `ls-i-00`'s own domain content, the same
/// relation [flutter3d_lab] has to `flutter3d_sim`'s stepping and recording
/// primitives ([EduDataSource], [SamplerDataSource], [DataSourceRegistry],
/// `resolveBindings`): a twin's own signal is one more phenomenon to
/// simulate, not something `flutter3d_sim` itself needs to know about.
///
/// Plain Dart, same reason `flutter3d_lab` and `flutter3d_sim` both are: a
/// server checks or replays a twin's own signal in a container with no
/// Flutter SDK in it.
library;

export 'src/spindle_temp.dart';
