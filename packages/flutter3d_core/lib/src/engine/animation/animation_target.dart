import 'package:vector_math/vector_math.dart';

/// What a player can drive.
///
/// An interface rather than `SceneNode` directly, and the direction matters:
/// the animation layer is reached from the asset decoders, so depending on the
/// scene graph would drag `RenderMaterial` — and through it the graphics backend and
/// `dart:ui` — into everything that merely decodes a glTF file. That is exactly
/// what stopped `tool/bench/bench.dart` from compiling ahead of time.
///
/// `SceneNode` satisfies it as written; nothing else has to.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class AnimationTarget {
  void setPosition(double x, double y, double z);
  void setRotation(Quaternion value);
  void setScale(double x, double y, double z);
}

/// How a clip behaves when it runs off its end.
enum AnimationWrap {
  /// Hold the final pose.
  once,

  /// Start over.
  loop,

  /// Play backwards, then forwards, and so on.
  pingPong,
}
