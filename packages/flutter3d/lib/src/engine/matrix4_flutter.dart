/// The crossing between Flutter's `Matrix4` and the engine's.
///
/// Two classes share the name. `package:flutter/widgets.dart` exports
/// `vector_math_64`'s, which holds doubles; every engine signature takes
/// `vector_math`'s, which holds 32-bit floats, because a matrix the engine
/// takes is a matrix it uploads. The float32 one stays: changing it would
/// break every signature that names it.
///
/// A file that imports both writes `hide Matrix4` on the Flutter import
/// (`flutter3d_lints`'s `hide_flutter_matrix4` offers it as a fix), names
/// the engine's `Matrix4` bare, and crosses with [FlutterMatrix4ToEngine]
/// and [EngineMatrix4ToFlutter] where a widget's `Transform` meets a node.
library;

import 'package:vector_math/vector_math.dart' as engine show Matrix4;
import 'package:vector_math/vector_math_64.dart' as flutter show Matrix4;

/// A Flutter (`vector_math_64`) `Matrix4` read as the engine's.
extension FlutterMatrix4ToEngine on flutter.Matrix4 {
  /// This matrix as the single-precision `Matrix4` the engine takes, entry
  /// for entry in the same column-major order.
  ///
  /// Each entry is rounded to the nearest 32-bit float; a translation of
  /// more than about 16 million world units loses its fractional part, as
  /// it would anywhere in the engine.
  engine.Matrix4 toEngine() => engine.Matrix4.fromList(storage);
}

/// The engine's `Matrix4` read as Flutter's (`vector_math_64`).
extension EngineMatrix4ToFlutter on engine.Matrix4 {
  /// This matrix as the double-precision `Matrix4` a Flutter widget takes,
  /// such as `Transform.transform`; every 32-bit entry widens exactly.
  flutter.Matrix4 toFlutter() => flutter.Matrix4.fromList(storage);
}
