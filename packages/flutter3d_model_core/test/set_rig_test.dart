/// `SetRig`, `doc-36d`'s own row: one history step for a whole auto-rig
/// result. JSON round trip for `SetRig`/`SkinWeightsBlob`, the three
/// refusals (a taken joint object id, an object with no mesh to skin, a
/// stale `baseVersion` — the exact rule `ApplyJobResult` already refuses
/// stale mesh bytes with), and undo through `ModelHistory` removing every
/// joint object, the skeleton, and restoring the skin bytes byte-exact.
///
///     dart test test/set_rig_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own — the same fixture shape
/// `paint_weights_command_test.dart`'s own `_joint` builds.
ModelObject _joint(int id, {int? parent, required Matrix4 transform}) =>
    ModelObject(
      id: id,
      name: 'joint$id',
      geometry: const SocketGeometry(),
      transform: transform,
      parent: parent,
    );

List<Vector3> _quadAt(Vector3 at) => <Vector3>[
  at + Vector3(-0.05, -0.05, 0),
  at + Vector3(0.05, -0.05, 0),
  at + Vector3(0.05, 0.05, 0),
  at + Vector3(-0.05, 0.05, 0),
];

double _weightOf(EditMesh mesh, int vertex, int localJoint) {
  final match = weightsOf(mesh, vertex).where((p) => p.joint == localJoint);
  return match.isEmpty ? 0.0 : match.single.weight;
}

/// One skinned object (id 1, a single-quad mesh, four vertices, already
/// bound to *something* — see below) and nothing else — `nextId` at 2, the
/// same place `buildSkeleton`'s own `firstObjectId` would start a rig's own
/// joints from.
///
/// **Pre-seeded with a throwaway binding before the fixture is ever handed
/// to a test.** `EditMesh.setSkin`'s own doc comment: the *first* call on
/// any vertex allocates the whole mesh's own joint/weight layers, zero-filled
/// for every vertex slot — a one-time, unjournalled structural change that a
/// later `EditMesh.undo` does not reverse, only the values written after it.
/// A test that captured `toBytes()` before that first-ever call and expected
/// it back after undoing a command that made that call would be checking an
/// `EditMesh` quirk this row did not introduce, not `SetRig` itself — so
/// this fixture is never in that "never once skinned" state to begin with,
/// the same way `paint_weights_command_test.dart`'s own bent-arm fixture
/// already is not.
({ModelProject project, EditMesh mesh}) _fixture() {
  final mesh = EditMesh.fromFaces(_quadAt(Vector3.zero()), <List<int>>[
    <int>[0, 1, 2, 3],
  ]);
  mesh.beginStep();
  for (var v = 0; v < 4; v++) {
    mesh.setSkin(
      v,
      VertexAttributes(
        joints: Vector4(0, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      ),
    );
  }
  mesh.endStep();
  final project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'arm',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
      ),
    ],
    nextId: 2,
  );
  return (project: project, mesh: mesh);
}

/// Every vertex bound fully to local joint 0 — 8 `Float32`s per vertex slot
/// (`data`'s own shape), four vertex slots, the fixture mesh's own count.
SkinWeightsBlob _fullyBoundBlob({int baseVersion = 1}) => SkinWeightsBlob(
  baseVersion: baseVersion,
  data: Float32List.fromList(<double>[
    for (var v = 0; v < 4; v++) ...<double>[0, 0, 0, 0, 1, 0, 0, 0],
  ]),
);

void main() {
  group('JSON round trip', () {
    test('SkinWeightsBlob round-trips through JSON', () {
      final blob = SkinWeightsBlob(
        baseVersion: 3,
        data: Float32List.fromList(<double>[
          0,
          1,
          2,
          3,
          0.25,
          0.25,
          0.25,
          0.25,
        ]),
      );
      final back = SkinWeightsBlob.fromJson(blob.toJson());
      expect(back, isNotNull);
      expect(back!.toJson(), blob.toJson());
    });

    test('SetRig round-trips with a skinObjectId and weights', () {
      final command = SetRig(
        jointObjects: <ModelObject>[
          _joint(2, transform: Matrix4.identity()),
          _joint(
            3,
            parent: 2,
            transform: Matrix4.translation(Vector3(1, 0, 0)),
          ),
        ],
        skeleton: ProjectSkeleton(
          joints: <int>[2, 3],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
          name: 'rig',
        ),
        skinObjectId: 1,
        weights: _fullyBoundBlob(),
        label: 'auto-rig humanoid (2 joints)',
      );
      final back = modelCommandFromJson(command.toJson());
      expect(back, isA<SetRig>());
      expect(back!.toJson(), command.toJson());
    });

    test('SetRig round-trips with neither a skinObjectId nor weights', () {
      final command = SetRig(
        jointObjects: <ModelObject>[_joint(2, transform: Matrix4.identity())],
        skeleton: ProjectSkeleton(
          joints: <int>[2],
          inverseBindMatrices: <Matrix4>[Matrix4.identity()],
        ),
        label: 'add an empty rig',
      );
      final back = modelCommandFromJson(command.toJson());
      expect(back, isA<SetRig>());
      expect(back!.toJson(), command.toJson());
    });
  });

  group('refusals', () {
    test('refuses a joint object id that is already taken', () {
      final fixture = _fixture();
      final history = ModelHistory(fixture.project);
      final refused = history.run(
        SetRig(
          jointObjects: <ModelObject>[_joint(1, transform: Matrix4.identity())],
          skeleton: ProjectSkeleton(
            joints: <int>[1],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
          label: 'x',
        ),
      );
      expect(refused, contains('object 1 already exists'));
      expect(history.canUndo, isFalse);
    });

    test('refuses a skinObjectId that does not exist', () {
      final fixture = _fixture();
      final history = ModelHistory(fixture.project);
      final refused = history.run(
        SetRig(
          jointObjects: <ModelObject>[_joint(2, transform: Matrix4.identity())],
          skeleton: ProjectSkeleton(
            joints: <int>[2],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
          skinObjectId: 999,
          label: 'x',
        ),
      );
      expect(refused, contains('there is no object 999'));
      expect(history.canUndo, isFalse);
    });

    test('refuses skinning (with weights) an object with no mesh', () {
      final project = ModelProject(
        objects: <ModelObject>[_joint(1, transform: Matrix4.identity())],
        nextId: 2,
      );
      final history = ModelHistory(project);
      final refused = history.run(
        SetRig(
          jointObjects: <ModelObject>[_joint(2, transform: Matrix4.identity())],
          skeleton: ProjectSkeleton(
            joints: <int>[2],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
          skinObjectId: 1,
          weights: SkinWeightsBlob(baseVersion: 1, data: Float32List(8)),
          label: 'x',
        ),
      );
      expect(refused, contains('no mesh to skin'));
      expect(history.canUndo, isFalse);
    });

    test(
      'refuses a stale baseVersion — the exact rule ApplyJobResult uses',
      () {
        final fixture = _fixture();
        final history = ModelHistory(fixture.project);
        // Bumps object 1's own version from 1 to 2.
        history.run(const Rename(id: 1, to: 'renamed'));

        final refused = history.run(
          SetRig(
            jointObjects: <ModelObject>[
              _joint(2, transform: Matrix4.identity()),
            ],
            skeleton: ProjectSkeleton(
              joints: <int>[2],
              inverseBindMatrices: <Matrix4>[Matrix4.identity()],
            ),
            skinObjectId: 1,
            weights: _fullyBoundBlob(), // still says baseVersion 1
            label: 'x',
          ),
        );
        expect(refused, contains('has changed since this job started'));
        expect(refused, contains('now version 2'));
        expect(refused, contains('started at 1'));
        // The Rename above is the only step; the refusal added none.
        expect(history.steps, hasLength(1));
      },
    );

    test(
      'refuses a skin weights blob whose length disagrees with the mesh',
      () {
        final fixture = _fixture();
        final history = ModelHistory(fixture.project);
        final refused = history.run(
          SetRig(
            jointObjects: <ModelObject>[
              _joint(2, transform: Matrix4.identity()),
            ],
            skeleton: ProjectSkeleton(
              joints: <int>[2],
              inverseBindMatrices: <Matrix4>[Matrix4.identity()],
            ),
            skinObjectId: 1,
            // The fixture mesh has 4 vertices; this needs 32 numbers.
            weights: SkinWeightsBlob(baseVersion: 1, data: Float32List(8)),
            label: 'x',
          ),
        );
        expect(refused, contains('needs 32'));
        expect(history.canUndo, isFalse);
      },
    );
  });

  group('binding with no weights', () {
    test('binds skinObjectId to the new skeleton even when it has no mesh, '
        'as long as weights is not given', () {
      final project = ModelProject(
        objects: <ModelObject>[_joint(1, transform: Matrix4.identity())],
        nextId: 2,
      );
      final history = ModelHistory(project);
      final refused = history.run(
        SetRig(
          jointObjects: <ModelObject>[_joint(2, transform: Matrix4.identity())],
          skeleton: ProjectSkeleton(
            joints: <int>[2],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
          skinObjectId: 1,
          label: 'x',
        ),
      );
      expect(refused, isNull);
      expect(history.project[1]!.skeletonIndex, 0);
    });
  });

  group('undo, through ModelHistory', () {
    test('run(SetRig(...)) adds every joint object, the skeleton, binds '
        'skinObjectId and writes its skin — undo removes all of it and '
        'restores the mesh byte-exact', () {
      final fixture = _fixture();
      final history = ModelHistory(fixture.project);
      final mesh = fixture.mesh;
      final before = mesh.toBytes();

      final refused = history.run(
        SetRig(
          jointObjects: <ModelObject>[
            _joint(2, transform: Matrix4.identity()),
            _joint(
              3,
              parent: 2,
              transform: Matrix4.translation(Vector3(1, 0, 0)),
            ),
          ],
          skeleton: ProjectSkeleton(
            joints: <int>[2, 3],
            inverseBindMatrices: <Matrix4>[
              Matrix4.identity(),
              Matrix4.identity(),
            ],
            name: 'rig',
          ),
          skinObjectId: 1,
          weights: _fullyBoundBlob(),
          label: 'auto-rig humanoid (2 joints)',
        ),
      );
      expect(refused, isNull);

      expect(history.project.skeletons, hasLength(1));
      expect(history.project.skeletons.single.joints, <int>[2, 3]);
      expect(history.project.objects, hasLength(3));
      expect(history.project[1]!.skeletonIndex, 0);
      expect(history.project.nextId, 4);
      for (var v = 0; v < 4; v++) {
        expect(_weightOf(mesh, v, 0), 1.0, reason: 'vertex $v');
      }

      expect(history.canUndo, isTrue);
      expect(history.undoSays, 'auto-rig humanoid (2 joints)');
      expect(history.undo(), isTrue);

      expect(history.project.skeletons, isEmpty);
      expect(history.project.objects, hasLength(1));
      expect(history.project[2], isNull);
      expect(history.project[3], isNull);
      expect(history.project[1]!.skeletonIndex, isNull);
      expect(mesh.toBytes(), before);
      expect(history.canUndo, isFalse);
    });
  });
}
