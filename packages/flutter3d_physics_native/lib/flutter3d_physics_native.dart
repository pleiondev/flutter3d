/// The physics core of flutter3d in C11 — P9.
///
/// Rigid bodies owned and stepped natively, reached through `dart:ffi` and
/// built by this package's hook with the C compiler the target already uses.
/// `flutter3d_physics` is the pure-Dart reference it is held to, and the
/// fallback where it cannot run.
library;

export 'src/native_debris.dart';
export 'src/native_particles.dart' hide nativeGpuPointer;
export 'src/native_world.dart';
