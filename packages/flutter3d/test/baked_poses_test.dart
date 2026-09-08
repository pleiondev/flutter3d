/// Sampling a clip once so a crowd can wear it.
///
/// **What is being checked is that the table agrees with the player**, because
/// the table is going to be read by a shader instead of the player and there is
/// no third opinion available. Everything else here — the width, the stacking,
/// the playhead being put back — is bookkeeping that a crowd finds out about
/// only by looking wrong.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation_clip.dart';
import 'package:flutter3d/src/engine/animation/animation_player.dart';
import 'package:flutter3d/src/engine/animation/animation_target.dart';
import 'package:flutter3d/src/engine/animation/animation_track.dart';
import 'package:flutter3d/src/engine/animation/baked_poses.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Two joints in a chain, bound at rest, with the root on a turntable.
///
/// Clip *i* turns the root `i + 1` quarter-turns over one second, so a second
/// clip is a faster one — which is what says the rows of one clip are not the
/// rows of another.
({Scene scene, Skeleton skeleton, AnimationPlayer player}) rig({
  int clips = 1,
}) {
  final scene = Scene();
  final root = scene.add(SceneNode(name: 'root'));
  final tip = SceneNode(name: 'tip')..setPosition(0.0, 1.0, 0.0);
  root.add(tip);

  final skeleton = Skeleton(
    name: 'chain',
    joints: <SceneNode>[root, tip],
    inverseBindMatrices: <Matrix4>[
      Matrix4.copy(root.worldMatrix)..invert(),
      Matrix4.copy(tip.worldMatrix)..invert(),
    ],
  );

  return (
    scene: scene,
    skeleton: skeleton,
    player: AnimationPlayer(
      clips: <AnimationClip>[
        for (var i = 0; i < clips; i++) _turn(quarters: i + 1, name: 'turn $i'),
      ],
      targets: <AnimationTarget?>[root, tip],
    ),
  );
}

/// A one-second clip turning node nought [quarters] quarter-turns about Z.
AnimationClip _turn({required int quarters, required String name}) {
  final end = Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 1.5707963 * quarters)
    ..normalize();
  return AnimationClip(
    name: name,
    tracks: <AnimationTrack>[
      AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          0.0, 0.0, 0.0, 1.0, //
          end.x, end.y, end.z, end.w,
        ]),
        componentCount: 4,
      ),
    ],
  );
}

/// The pose the player actually shows at [seconds], as joint [joint]'s matrix.
Matrix4 poseAt(
  AnimationPlayer player,
  Skeleton skeleton,
  double seconds,
  int joint,
) {
  player.seek(seconds);
  skeleton.update(Matrix4.identity());
  final storage = Float32List(16);
  for (var e = 0; e < 16; e++) {
    storage[e] = skeleton.matrices[joint * 16 + e];
  }
  return Matrix4.fromFloat32List(storage);
}

void expectSame(Matrix4 got, Matrix4 wanted, {required String reason}) {
  for (var e = 0; e < 16; e++) {
    expect(got.storage[e], closeTo(wanted.storage[e], 1e-6), reason: reason);
  }
}

/// How far two poses are apart, as the largest element between them.
///
/// **Not the translation**, which was the first thing this compared and is
/// always nought here: a joint matrix is `jointWorld * inverseBind`, so a rig
/// whose root only turns produces pure rotations and every one of them has the
/// same fourth column. The difference between two moments of a turntable is in
/// the rotation or it is nowhere.
double apart(Matrix4 a, Matrix4 b) {
  var worst = 0.0;
  for (var e = 0; e < 16; e++) {
    final double gap = (a.storage[e] - b.storage[e]).abs();
    if (gap > worst) worst = gap;
  }
  return worst;
}

void main() {
  group('a baked clip', () {
    test('holds the pose the player would have shown at that moment', () {
      // **The one that matters.** The shader will read this table instead of
      // asking the player, so the table has to be what the player says. Every
      // frame, not the first — a bake that samples at the wrong times still
      // starts in the right place.
      final (:scene, :skeleton, :player) = rig();
      final poses = BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 8,
      );

      for (var frame = 0; frame < poses.frames; frame++) {
        for (var joint = 0; joint < poses.joints; joint++) {
          expectSame(
            poses.matrixAt(0, frame, joint),
            poseAt(player, skeleton, frame / 8.0, joint),
            reason: 'frame $frame, joint $joint',
          );
        }
      }
    });

    test('stops a step short of the end, so the loop closes', () {
      // Mutation: sample at `frame / (frames - 1)`. The parity test above still
      // passes on frame nought and fails everywhere else, but *this* is the
      // reason the divisor is what it is: the last row has to be one step
      // before the end, so that blending it back into the first row is a step
      // like any other. Sampling to the end repeats the opening pose and a walk
      // cycle hitches once a lap.
      final (:scene, :skeleton, :player) = rig();
      final poses = BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 4,
      );

      expectSame(
        poses.matrixAt(0, 3, 1),
        poseAt(player, skeleton, 0.75, 1),
        reason: 'the last row is not three quarters of the way round',
      );
      expect(
        apart(poses.matrixAt(0, 3, 1), poses.matrixAt(0, 0, 1)),
        greaterThan(0.1),
        reason: 'the last row repeats the first, so a lap hitches',
      );
    });

    test('is as wide as the rig rather than as wide as the shader', () {
      // Mutation: lay out `Skeleton.maxJoints` columns. A two-joint rig then
      // carries sixty-four matrices a frame, and thirty-one thirty-seconds of
      // the texture is identity nobody reads.
      final (:scene, :skeleton, :player) = rig();
      final poses = BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 4,
      );

      expect(poses.joints, 2);
      expect(poses.width, 8, reason: 'four texels a matrix, two matrices');
      expect(poses.height, 4);
      expect(poses.pixels.length, 8 * 4 * 4);
    });

    test('puts the playhead back where it found it', () {
      // Mutation: drop the restore. A caller who bakes a crowd out of the model
      // it is also drawing watches that model snap to the last frame sampled —
      // and it is the *last clip's* last frame, so it may not even be the
      // animation that was playing.
      final (:scene, :skeleton, :player) = rig(clips: 2);
      player
        ..play(0)
        ..seek(0.3);

      BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 4,
      );

      expect(player.clipIndex, 0);
      expect(player.time, closeTo(0.3, 1e-9));
    });
  });

  group('several clips', () {
    test('stack into one table, and a row knows which it is on', () {
      // One sampler for a crowd wearing three animations, not three. Mutation:
      // have `rowOf` ignore the clip — every instance then plays the first clip
      // whatever it was told.
      final (:scene, :skeleton, :player) = rig(clips: 2);
      final poses = BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 4,
      );

      expect(poses.clips, 2);
      expect(poses.height, 8);
      expect(poses.rowOf(1, 0), 4);

      // Half a second into a quarter-turn and into a half-turn are different
      // places to be, which is the whole of what stacking has to preserve.
      expect(
        apart(poses.matrixAt(0, 2, 1), poses.matrixAt(1, 2, 1)),
        greaterThan(0.1),
        reason: 'the second clip baked as though it were the first',
      );
    });

    test('records how long each one is', () {
      // The reader turns an instance's time into a row, and cannot without
      // this: by then the clip is somewhere else entirely.
      final (:scene, :skeleton, :player) = rig(clips: 2);
      final poses = BakedPoses.of(
        player,
        skeleton: skeleton,
        meshWorld: Matrix4.identity(),
        framesPerClip: 4,
      );

      expect(poses.durations, <double>[1.0, 1.0]);
    });
  });

  group('a bake that cannot be made', () {
    test('refuses no frames rather than making an empty table', () {
      final (:scene, :skeleton, :player) = rig();
      expect(
        () => BakedPoses.of(
          player,
          skeleton: skeleton,
          meshWorld: Matrix4.identity(),
          framesPerClip: 0,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a player with nothing to play', () {
      final (:scene, :skeleton, :player) = rig();
      expect(
        () => BakedPoses.of(
          AnimationPlayer(
            clips: const <AnimationClip>[],
            targets: const <AnimationTarget?>[],
          ),
          skeleton: skeleton,
          meshWorld: Matrix4.identity(),
        ),
        throwsArgumentError,
      );
    });
  });
}
