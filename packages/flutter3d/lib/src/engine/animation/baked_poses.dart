/// A clip's joint matrices, sampled once and laid out for a texture.
///
/// ## Why a crowd cannot simply be skinned
///
/// A skinned draw hands the vertex stage one array of joint matrices in a
/// uniform block, and a uniform is the same for every instance of a draw by
/// definition — the same wall `lib/morph_instanced.glsl` describes for shapes,
/// one storey up. A thousand instanced villagers would all stand in one pose.
/// The three ways out are a uniform array indexed by instance, which the
/// guaranteed sixteen kilobytes of uniform block turns into about eight
/// villagers; a storage buffer, which `flutter_gpu` does not expose at all; and
/// a texture read from the vertex stage, which this engine already does for
/// per-instance morph weights and which every backend answers.
///
/// ## Why the *clip* is baked and not the pose
///
/// A texture here is created with its contents and never written again —
/// `GraphicsDevice` has `createTextureFromPixels` and no update, which is a
/// decision the HAL makes on purpose. Live per-instance poses change every
/// frame, so putting them in a texture means building a texture every frame,
/// for a crowd, for ever. That is the one case the morph-weight design
/// explicitly says it is not for: *a crowd where each face is different rather
/// than a crowd where each face is moving.*
///
/// So what goes in the texture is the animation rather than the animated. A
/// clip sampled at a fixed rate is a table that never changes; each instance
/// then needs only **which clip** and **when**, which is two numbers and rides
/// in the instance stream where per-instance data already rides. The texture is
/// built once and the per-frame cost is nought.
///
/// ## What this therefore cannot do, said plainly
///
/// A crowd baked this way plays **clips**, not poses. No inverse kinematics, no
/// per-instance procedural aiming, no ragdoll — anything that computes a pose
/// from the world at run time needs the pose to reach the GPU that frame, and
/// this deliberately arranges for it not to. A hero keeps the skinned stage it
/// has; this is for the thousand behind them.
///
/// The pose is also sampled rather than continuous. Reading a single row shows
/// the judder of the sample rate, so the stage that reads this is expected to
/// take two rows and blend — which is why [framesPerClip] frames cover the clip
/// *without* repeating its first pose at the end, and why row `frames - 1`
/// blends back into row `0`.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/skeleton.dart';
import 'animation_player.dart';

/// A clip's worth of joint matrices, ready to become a texture.
final class BakedPoses {
  BakedPoses._({
    required this.joints,
    required this.frames,
    required this.durations,
    required this.pixels,
  });

  /// How many joints each row holds. The skeleton's own count, not
  /// [Skeleton.maxJoints]: a rig of twenty joints should not pay for sixty-four.
  final int joints;

  /// How many rows each clip was sampled into.
  final int frames;

  /// Each baked clip's length in seconds, in the order they were baked.
  ///
  /// Kept because the reader needs it and nothing else has it in this form: to
  /// turn an instance's time into a row you have to know how long the clip is,
  /// and by then the clip itself is somewhere else entirely.
  final List<double> durations;

  /// The matrices, four floats a column and four columns a joint.
  final Float32List pixels;

  /// How many clips are in here.
  int get clips => durations.length;

  /// Texels across: four to a matrix.
  int get width => joints * 4;

  /// Texels down: every clip's frames, one clip after another.
  int get height => clips * frames;

  /// The row a clip's frame is on.
  ///
  /// Clips are stacked rather than given a texture each, so a crowd wearing
  /// three clips is one sampler and not three. It is also why the reader has to
  /// be told where a clip starts: the row is not the frame.
  int rowOf(int clip, int frame) => clip * frames + frame;

  /// Reads one joint's matrix back, for a test or a tool.
  Matrix4 matrixAt(int clip, int frame, int joint) {
    final storage = Float32List(16);
    final int at = (rowOf(clip, frame) * width + joint * 4) * 4;
    for (var e = 0; e < 16; e++) {
      storage[e] = pixels[at + e];
    }
    return Matrix4.fromFloat32List(storage);
  }

  /// Samples every clip [player] holds into one table.
  ///
  /// [meshWorld] is the world transform of the node the skinned mesh hangs
  /// from, exactly as [Skeleton.update] means it: the matrices come out in the
  /// mesh's own space, which is what makes them independent of where any
  /// instance of the crowd stands.
  ///
  /// **The playhead is put back where it was found.** Baking is a side effect
  /// on the whole rig — it moves the playhead and every joint node with it — and
  /// a caller who bakes a crowd out of the model it is also drawing would
  /// otherwise watch it snap to the last frame sampled.
  ///
  /// A clip with no length at all is sampled anyway, every row alike: an
  /// animation that does not move is a pose, and a pose is a perfectly good
  /// thing for a statue in a crowd to wear.
  static BakedPoses of(
    AnimationPlayer player, {
    required Skeleton skeleton,
    required Matrix4 meshWorld,
    int framesPerClip = 32,
  }) {
    if (framesPerClip < 1) {
      throw ArgumentError.value(
        framesPerClip,
        'framesPerClip',
        'a clip sampled no times is not a clip',
      );
    }
    if (player.clips.isEmpty) {
      throw ArgumentError('a player with no clips has nothing to bake');
    }

    final int joints = skeleton.joints.length;
    final pixels = Float32List(
      player.clips.length * framesPerClip * joints * 16,
    );
    final durations = <double>[];

    final int wasPlaying = player.clipIndex;
    final double wasAt = player.time;

    var at = 0;
    for (var clip = 0; clip < player.clips.length; clip++) {
      player.play(clip);
      final double duration = player.duration;
      durations.add(duration);
      for (var frame = 0; frame < framesPerClip; frame++) {
        // `frame / frames`, not `frame / (frames - 1)`: a loop's last sample is
        // one step short of the end, so that blending from it lands on the
        // first. Sampling to the very end instead repeats the opening pose and
        // makes a walk cycle hitch once a lap.
        player.seek(duration * frame / framesPerClip);
        skeleton.update(meshWorld);
        for (var joint = 0; joint < joints; joint++) {
          final int from = joint * 16;
          for (var e = 0; e < 16; e++) {
            pixels[at++] = skeleton.matrices[from + e];
          }
        }
      }
    }

    if (wasPlaying >= 0) {
      player
        ..play(wasPlaying)
        ..seek(wasAt);
    }

    return BakedPoses._(
      joints: joints,
      frames: framesPerClip,
      durations: List<double>.unmodifiable(durations),
      pixels: pixels,
    );
  }
}
