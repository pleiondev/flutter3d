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
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class AnimationWrap {
  const AnimationWrap._(this.name);

  /// Hold the final pose.
  static const AnimationWrap once = AnimationWrap._('once');

  /// Start over.
  static const AnimationWrap loop = AnimationWrap._('loop');

  /// Play backwards, then forwards, and so on.
  static const AnimationWrap pingPong = AnimationWrap._('pingPong');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<AnimationWrap> values = <AnimationWrap>[
    once,
    loop,
    pingPong,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static AnimationWrap? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'AnimationWrap.$name';
}
