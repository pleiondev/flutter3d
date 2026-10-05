/// One joint's world matrix down its own chain — what the goals and the
/// two-bone solver ask for in a game's step, instead of every node.
///
///     dart test test/pose_world_of_test.dart
///
/// On the hero's rig, every joint turned off its rest: each node's matrix
/// from [Pose.worldMatrixOf] is [Pose.worldMatrices]' to float precision, and
/// a hierarchy that loops — a malformed rig — is walked to an end.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('every node of the hero, turned, as the whole walk has it', () async {
    final doc = await GltfLoader().load(
      File('../flutter3d/test/fixtures/hero.glb').readAsBytesSync(),
    );
    final pose = Pose.fromNodes(doc.nodes);
    // Each joint turned a little its own way, so no chain is the identity.
    for (var i = 0; i < pose.nodeCount; i++) {
      final q = Quaternion.axisAngle(
        Vector3(1.0, 0.5 * (i % 3), 0.3).normalized(),
        0.05 * (i % 7 + 1),
      );
      pose.rotations
        ..[i * 4] = q.x
        ..[i * 4 + 1] = q.y
        ..[i * 4 + 2] = q.z
        ..[i * 4 + 3] = q.w;
    }
    final all = pose.worldMatrices();
    final scratch = Matrix4.identity();
    expect(pose.nodeCount, greaterThan(40));
    for (var i = 0; i < pose.nodeCount; i++) {
      final one = pose.worldMatrixOf(i, scratch);
      for (var k = 0; k < 16; k++) {
        expect(one.storage[k], closeTo(all[i].storage[k], 1e-4), reason: '$i');
      }
    }
  });

  test('a hierarchy that loops is walked to an end, not for ever', () {
    final pose = Pose(
      parents: const <int>[1, 0, 1],
      restTranslations: Float32List.fromList(<double>[
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        3,
      ]),
      restRotations: Float32List.fromList(<double>[
        for (var i = 0; i < 3; i++) ...<double>[0, 0, 0, 1],
      ]),
      restScales: Float32List.fromList(<double>[for (var i = 0; i < 9; i++) 1]),
    );
    for (var i = 0; i < 3; i++) {
      final m = pose.worldMatrixOf(i);
      expect(m.storage.every((v) => v.isFinite), isTrue, reason: '$i');
    }
  });
}
