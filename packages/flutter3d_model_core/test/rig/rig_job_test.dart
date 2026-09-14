/// `anim-33d`'s own `boneSegmentsOf`: a [RetargetRig] read as
/// [BoneSegment]s, addressed the same local way [WeightPair.joint] already
/// is everywhere else — including the "more nodes than joints" case
/// `RigBuildOptions.controllers` adds (`flutter3d_model_core`'s own
/// `rig_template.dart`), read here without that package at all.
///
///     dart test test/rig_job_test.dart
library;

import 'package:flutter3d_rig/flutter3d_rig.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// [actual] equals [expected] within [tolerance] — `Matrix4`/`Vector3` are
/// both `Float32List`-backed, so a position composed through a few chained
/// translations (as [boneSegmentsOf]'s own world-transform walk does) does
/// not necessarily land on the exact same float32 bit pattern a literal
/// like `Vector3(0, 1.4, 0)` rounds to, even though both are "1.4" to any
/// precision a rig cares about.
void _expectClose(Vector3 actual, Vector3 expected, [double tolerance = 1e-4]) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
  expect(actual.z, closeTo(expected.z, tolerance));
}

void main() {
  group('boneSegmentsOf', () {
    test('one segment per joint, parent world position to own', () {
      // hips(0) -> spine(1) -> chest(2), all pure translations, only
      // spine/chest are joints — hips is a node above them the same way a
      // rig controller sits above a template's own root joint.
      final rig = RetargetRig(
        nodes: <RigNode>[
          RigNode(
            id: 0,
            name: 'hips',
            restLocal: Matrix4.translation(Vector3(0, 1, 0)),
          ),
          RigNode(
            id: 1,
            name: 'spine',
            restLocal: Matrix4.translation(Vector3(0, 0.2, 0)),
            parent: 0,
          ),
          RigNode(
            id: 2,
            name: 'chest',
            restLocal: Matrix4.translation(Vector3(0, 0.2, 0)),
            parent: 1,
          ),
        ],
        joints: <int>[1, 2],
      );

      final segments = boneSegmentsOf(rig);
      expect(segments, hasLength(2));

      _expectClose(segments[0].head, Vector3(0, 1, 0));
      _expectClose(segments[0].tail, Vector3(0, 1.2, 0));
      expect(segments[0].name, 'spine');

      _expectClose(segments[1].head, Vector3(0, 1.2, 0));
      _expectClose(segments[1].tail, Vector3(0, 1.4, 0));
      expect(segments[1].name, 'chest');
    });

    test('a joint whose parent is not itself a joint still resolves — the '
        'RigBuildOptions.controllers case', () {
      // The parent (id 0) is a node in the rig but never listed as a
      // joint — exactly what a rig controller is once `rig_template.dart`
      // adds one.
      final rig = RetargetRig(
        nodes: <RigNode>[
          RigNode(
            id: 0,
            name: 'hipsControl',
            restLocal: Matrix4.translation(Vector3(1, 2, 3)),
          ),
          RigNode(
            id: 1,
            name: 'hips',
            restLocal: Matrix4.identity(),
            parent: 0,
          ),
        ],
        joints: <int>[1],
      );

      final segments = boneSegmentsOf(rig);
      expect(segments, hasLength(1));
      _expectClose(segments[0].head, Vector3(1, 2, 3));
      _expectClose(segments[0].tail, Vector3(1, 2, 3));
      expect(segments[0].name, 'hips');
    });

    test('a joint with no parent at all gets a degenerate, zero-length '
        'segment', () {
      final rig = RetargetRig(
        nodes: <RigNode>[
          RigNode(
            id: 0,
            name: 'root',
            restLocal: Matrix4.translation(Vector3(5, 0, 0)),
          ),
        ],
        joints: <int>[0],
      );

      final segments = boneSegmentsOf(rig);
      expect(segments, hasLength(1));
      expect(segments[0].head, segments[0].tail);
      _expectClose(segments[0].head, Vector3(5, 0, 0));
    });

    test('addresses joints by their own position in rig.joints, not by id', () {
      final rig = RetargetRig(
        nodes: <RigNode>[
          RigNode(
            id: 10,
            name: 'a',
            restLocal: Matrix4.translation(Vector3(1, 0, 0)),
          ),
          RigNode(
            id: 20,
            name: 'b',
            restLocal: Matrix4.translation(Vector3(0, 1, 0)),
            parent: 10,
          ),
        ],
        joints: <int>[20, 10],
      );

      final segments = boneSegmentsOf(rig);
      expect(segments, hasLength(2));
      expect(segments[0].name, 'b');
      expect(segments[1].name, 'a');
    });

    test('empty rig gives empty segments', () {
      final rig = RetargetRig(nodes: const <RigNode>[], joints: const <int>[]);
      expect(boneSegmentsOf(rig), isEmpty);
    });
  });
}
