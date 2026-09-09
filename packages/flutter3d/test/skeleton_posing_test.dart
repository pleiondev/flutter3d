/// What posing a character costs, and that a pose reaches the palette at all.
///
///     flutter test test/skeleton_posing_test.dart
///
/// **A test rather than a line in `tool/bench`, and the reason is the finding.**
/// `anim-31` of `doc/model-editor-plan.md` asks for one animation number in
/// phase 0: `Skeleton.update` over 64 joints, a thousand times. It cannot be an
/// AOT benchmark like the ones behind `ARCHITECTURE.md` §14 — `Skeleton` reaches
/// `SceneNode`, which reaches `Scene`, which names `flutter3d_hardware`, which
/// declares the Flutter SDK, so `dart compile exe` stops at `dart:ui`. So the
/// figure is taken where the code can run, which is a Flutter test, and it is
/// JIT: comparable with itself over time and not with the AOT table.
///
/// The assertions are here because a benchmark nobody checks is a benchmark
/// that can measure the wrong thing forever: if the pose did not reach the
/// palette, the timing would be of a no-op.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/scene/scene_node.dart';
import 'package:flutter3d/src/engine/scene/skeleton.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A chain of [count] joints, each a child of the one before it — a spine
/// rather than a star, so `worldMatrix` is a real walk up a hierarchy.
({Skeleton skeleton, SceneNode root}) chain(int count) {
  final joints = <SceneNode>[];
  final inverseBind = <Matrix4>[];
  SceneNode? parent;
  for (var i = 0; i < count; i++) {
    final joint = SceneNode(name: 'joint$i')
      ..setPosition(0, 0.1, 0)
      ..setRotation(Quaternion.axisAngle(Vector3(0, 0, 1), 0.02 * i));
    parent?.add(joint);
    parent = joint;
    joints.add(joint);
    inverseBind.add(Matrix4.translation(Vector3(0, -0.1 * i, 0)));
  }
  return (
    skeleton: Skeleton(joints: joints, inverseBindMatrices: inverseBind),
    root: joints.first,
  );
}

void main() {
  test('a new pose reaches the palette', () {
    final it = chain(Skeleton.maxJoints);
    final meshWorld = Matrix4.identity();

    it.skeleton.update(meshWorld);
    final before = Float32List.fromList(it.skeleton.matrices);

    it.root.setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), 0.4));
    it.skeleton.update(meshWorld);

    expect(
      it.skeleton.matrices,
      isNot(equals(before)),
      reason: 'the root turned and the palette did not follow it',
    );
  });

  test('posing 64 joints a thousand times', () {
    final it = chain(Skeleton.maxJoints);
    final meshWorld = Matrix4.identity();

    // Warm, because the first call through a JIT measures the compiler.
    for (var i = 0; i < 100; i++) {
      it.skeleton.update(meshWorld);
    }

    final stopwatch = Stopwatch()..start();
    var angle = 0.0;
    for (var i = 0; i < 1000; i++) {
      angle += 0.001;
      it.root.setRotation(Quaternion.axisAngle(Vector3(0, 1, 0), angle));
      it.skeleton.update(meshWorld);
    }
    stopwatch.stop();

    final perPose = stopwatch.elapsedMicroseconds / 1000;
    // ignore: avoid_print — the number is the point of this file.
    print(
      'Skeleton.update, 64 joints, a new pose each time: '
      '${perPose.toStringAsFixed(1)} us per pose '
      '(${(perPose / Skeleton.maxJoints * 1000).toStringAsFixed(0)} ns per joint)',
    );

    // A budget rather than a benchmark assertion: a hundred characters posed in
    // one frame at 60 Hz leaves 166 us apiece, and this must fit inside that
    // with room for everything else. It is two orders of magnitude under today,
    // and the check is here so that a change which loses those two orders is
    // reported by a test rather than by somebody's frame rate.
    expect(perPose, lessThan(166));
  });
}
