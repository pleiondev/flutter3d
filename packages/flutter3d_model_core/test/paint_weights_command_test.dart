/// `PaintWeights`, the [ModelCommand] itself — `anim-10`'s own closing line,
/// "a stroke is one Cmd-Z." `paint_weights_test.dart` already covers the
/// low-level brush (`paintWeights`, called directly, mesh in hand); this
/// file covers what only exists once that brush is wrapped in a command: the
/// refusals, JSON round trip for `PaintWeights`/`BrushSample`/`PaintMirror`,
/// undo through `ModelHistory` (one stroke, and a hundred strokes inside one
/// transaction), the profile's own `maxInfluences` prune beyond
/// `paintWeight`'s own fixed per-sample cap, and a worked "a stroke changes
/// ≤1% of vertices" example.
///
///     dart test test/paint_weights_command_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own — the same fixture shape
/// `paint_weights_test.dart`'s own `_joint` builds.
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

void _edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

double _weightOf(EditMesh mesh, int vertex, int localJoint) {
  final match = weightsOf(mesh, vertex).where((p) => p.joint == localJoint);
  return match.isEmpty ? 0.0 : match.single.weight;
}

/// Root joint (1) at the origin; mid joint (2), bent 90° about Z, a child of
/// it; joint (3), unposed, is what a stroke paints — the same bent-arm shape
/// `paint_weights_test.dart`'s own `_bentArm` builds, here wrapped in a
/// [ModelHistory] since this file exercises the command, not the bare
/// function.
({ModelHistory history, EditMesh mesh, int objectId}) _bentArmHistory() {
  final mesh = EditMesh.fromFaces(
    <Vector3>[..._quadAt(Vector3.zero()), ..._quadAt(Vector3(2, 0, 0))],
    <List<int>>[
      <int>[0, 1, 2, 3],
      <int>[4, 5, 6, 7],
    ],
  );
  _edit(mesh, () {
    for (var v = 0; v < 4; v++) {
      mesh.setSkin(
        v,
        VertexAttributes(
          joints: Vector4(0, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        ),
      );
    }
    for (var v = 4; v < 8; v++) {
      mesh.setSkin(
        v,
        VertexAttributes(
          joints: Vector4(1, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        ),
      );
    }
  });

  final bend = Matrix4.translation(Vector3(1, 0, 0))
    ..multiply(Matrix4.rotationZ(1.5707963267948966));
  final project = ModelProject(
    objects: <ModelObject>[
      _joint(1, transform: Matrix4.identity()),
      _joint(2, parent: 1, transform: bend),
      _joint(3, transform: Matrix4.identity()),
      ModelObject(
        id: 10,
        name: 'arm',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
        skeletonIndex: 0,
      ),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(
        joints: <int>[1, 2, 3],
        inverseBindMatrices: <Matrix4>[
          Matrix4.identity(),
          Matrix4.translation(Vector3(-1, 0, 0)),
          Matrix4.identity(),
        ],
      ),
    ],
  );
  return (history: ModelHistory(project), mesh: mesh, objectId: 10);
}

void main() {
  group('JSON round trip', () {
    test('BrushSample round-trips through JSON', () {
      final sample = BrushSample(center: Vector3(1, -2, 0.5), radius: 0.25);
      final back = BrushSample.fromJson(sample.toJson());
      expect(back, isNotNull);
      expect(back!.toJson(), sample.toJson());
    });

    test('PaintMirror round-trips through JSON', () {
      const mirror = PaintMirror(
        axis: 1,
        jointMirror: <int, int>{1: 2, 3: 4},
        plane: 0.5,
        tolerance: 1e-3,
      );
      final back = PaintMirror.fromJson(mirror.toJson());
      expect(back, isNotNull);
      expect(back!.toJson(), mirror.toJson());
    });

    test(
      'PaintWeights round-trips through JSON, mirror and maxInfluences included',
      () {
        final command = PaintWeights(
          objectId: 10,
          skeletonIndex: 0,
          joint: 3,
          samples: <BrushSample>[
            BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
            BrushSample(center: Vector3(0, 0, 0), radius: 0.1),
          ],
          strength: 0.6,
          mode: PaintWeightsMode.assign,
          mirror: const PaintMirror(axis: 0, jointMirror: <int, int>{1: 2}),
          normalize: false,
          maxInfluences: 3,
        );
        final back = modelCommandFromJson(command.toJson());
        expect(back, isA<PaintWeights>());
        expect(back!.toJson(), command.toJson());
      },
    );
  });

  group('refusals', () {
    test('refuses an object that does not exist', () {
      final history = ModelHistory(const ModelProject());
      final refused = history.run(
        PaintWeights(
          objectId: 999,
          skeletonIndex: 0,
          joint: 1,
          samples: <BrushSample>[
            BrushSample(center: Vector3.zero(), radius: 1),
          ],
          strength: 0.5,
        ),
      );
      expect(refused, contains('999'));
      expect(history.canUndo, isFalse);
    });

    test('refuses an object with no mesh to paint weights on', () {
      final project = ModelProject(
        objects: <ModelObject>[_joint(1, transform: Matrix4.identity())],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[1],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
      );
      final history = ModelHistory(project);
      final refused = history.run(
        PaintWeights(
          objectId: 1,
          skeletonIndex: 0,
          joint: 1,
          samples: <BrushSample>[
            BrushSample(center: Vector3.zero(), radius: 1),
          ],
          strength: 0.5,
        ),
      );
      expect(refused, contains('mesh'));
      expect(history.canUndo, isFalse);
    });

    test('refuses a skeleton or a joint that is not real', () {
      final fixture = _bentArmHistory();
      final history = fixture.history;

      final badSkeleton = history.run(
        PaintWeights(
          objectId: fixture.objectId,
          skeletonIndex: 9,
          joint: 3,
          samples: <BrushSample>[
            BrushSample(center: Vector3.zero(), radius: 1),
          ],
          strength: 0.5,
        ),
      );
      expect(badSkeleton, contains('skeleton'));

      final badJoint = history.run(
        PaintWeights(
          objectId: fixture.objectId,
          skeletonIndex: 0,
          joint: 999,
          samples: <BrushSample>[
            BrushSample(center: Vector3.zero(), radius: 1),
          ],
          strength: 0.5,
        ),
      );
      expect(badJoint, contains('999'));
      expect(history.canUndo, isFalse);
    });

    test('refuses an empty sample list', () {
      final fixture = _bentArmHistory();
      final refused = fixture.history.run(
        PaintWeights(
          objectId: fixture.objectId,
          skeletonIndex: 0,
          joint: 3,
          samples: const <BrushSample>[],
          strength: 0.5,
        ),
      );
      expect(refused, contains('sample'));
      expect(fixture.history.canUndo, isFalse);
    });
  });

  group('undo, through ModelHistory', () {
    test('a stroke through the command hits a joint on a bent pose, and undo '
        'restores it byte-exact', () {
      final fixture = _bentArmHistory();
      final history = fixture.history;
      final mesh = fixture.mesh;
      final before = mesh.toBytes();

      final refused = history.run(
        PaintWeights(
          objectId: fixture.objectId,
          skeletonIndex: 0,
          joint: 3,
          samples: <BrushSample>[
            BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
          ],
          strength: 0.6,
        ),
      );
      expect(refused, isNull);

      // localJoint 2 is id 3, the joint being painted onto.
      for (var v = 4; v < 8; v++) {
        expect(
          _weightOf(mesh, v, 2),
          greaterThan(0.0),
          reason: 'forearm vertex $v',
        );
      }
      for (var v = 0; v < 4; v++) {
        expect(_weightOf(mesh, v, 2), 0.0, reason: 'shoulder vertex $v');
      }

      expect(history.canUndo, isTrue);
      expect(history.undoSays, 'paint weights');
      expect(history.undo(), isTrue);
      expect(mesh.toBytes(), before);
      expect(history.canUndo, isFalse);
    });

    test('100 commands inside one transaction collapse into one undo step, '
        'byte-exact restore', () {
      final fixture = _bentArmHistory();
      final history = fixture.history;
      final mesh = fixture.mesh;
      final before = mesh.toBytes();

      history.beginTransaction();
      for (var i = 0; i < 100; i++) {
        final refused = history.run(
          PaintWeights(
            objectId: fixture.objectId,
            skeletonIndex: 0,
            joint: 3,
            samples: <BrushSample>[
              BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
            ],
            strength: 0.02,
          ),
        );
        expect(refused, isNull);
      }
      history.endTransaction();

      expect(history.steps, hasLength(1));
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
      expect(mesh.toBytes(), isNot(equals(before)));

      expect(history.undo(), isTrue);
      expect(mesh.toBytes(), before);
      expect(history.canUndo, isFalse);
    });
  });

  group('the profile-driven prune', () {
    test("normalize (default true) prunes beyond paintWeight's own fixed "
        'per-sample cap, and renormalizes what is left', () {
      final mesh = EditMesh.cuboid();
      _edit(mesh, () {
        mesh.setSkin(
          0,
          VertexAttributes(
            joints: Vector4(0, 1, 2, 0),
            weights: Vector4(0.5, 0.3, 0.2, 0),
          ),
        );
      });

      final project = ModelProject(
        objects: <ModelObject>[
          _joint(1, transform: Matrix4.identity()),
          _joint(2, transform: Matrix4.identity()),
          _joint(3, transform: Matrix4.identity()),
          _joint(4, transform: Matrix4.identity()),
          ModelObject(
            id: 10,
            name: 'box',
            geometry: EditedGeometry(mesh),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[1, 2, 3, 4],
            inverseBindMatrices: <Matrix4>[
              Matrix4.identity(),
              Matrix4.identity(),
              Matrix4.identity(),
              Matrix4.identity(),
            ],
          ),
        ],
      );
      final history = ModelHistory(project);

      // A fourth influence, painted at full strength: `paintWeight`'s own
      // fixed cap of 4 keeps all of it (three already stored, plus this
      // one), summing to one on its own — this command's own
      // `maxInfluences: 2` is the only thing that trims it further.
      final refused = history.run(
        PaintWeights(
          objectId: 10,
          skeletonIndex: 0,
          joint: 4,
          samples: <BrushSample>[
            BrushSample(center: mesh.positionOf(0), radius: 0.01),
          ],
          strength: 1.0,
          maxInfluences: 2,
        ),
      );
      expect(refused, isNull);

      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(2));
      // Local joint 3 is id 4, just painted at full strength; local joint
      // 0 is id 1, the largest of what was already there — the two
      // `limitInfluences` keeps.
      expect(pairs.map((p) => p.joint).toSet(), <int>{3, 0});
      final total = pairs.fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(1.0, 1e-6));
    });
  });

  group('a stroke changes a small fraction of a mesh', () {
    test(
      'a stroke on a 441-vertex grid changes at most 1% of its vertices',
      () {
        const n = 20;
        const spacing = 1.0;
        final points = <Vector3>[
          for (var y = 0; y <= n; y++)
            for (var x = 0; x <= n; x++) Vector3(x * spacing, y * spacing, 0),
        ];
        int index(int x, int y) => y * (n + 1) + x;
        final faces = <List<int>>[
          for (var y = 0; y < n; y++)
            for (var x = 0; x < n; x++)
              <int>[
                index(x, y),
                index(x + 1, y),
                index(x + 1, y + 1),
                index(x, y + 1),
              ],
        ];
        final mesh = EditMesh.fromFaces(points, faces);
        _edit(mesh, () {
          for (var v = 0; v < points.length; v++) {
            mesh.setSkin(
              v,
              VertexAttributes(
                joints: Vector4(0, 0, 0, 0),
                weights: Vector4(1, 0, 0, 0),
              ),
            );
          }
        });

        final project = ModelProject(
          objects: <ModelObject>[
            _joint(1, transform: Matrix4.identity()),
            _joint(2, transform: Matrix4.identity()),
            ModelObject(
              id: 10,
              name: 'grid',
              geometry: EditedGeometry(mesh),
              transform: Matrix4.identity(),
              skeletonIndex: 0,
            ),
          ],
          skeletons: <ProjectSkeleton>[
            ProjectSkeleton(
              joints: <int>[1, 2],
              inverseBindMatrices: <Matrix4>[
                Matrix4.identity(),
                Matrix4.identity(),
              ],
            ),
          ],
        );
        final history = ModelHistory(project);

        // A small brush at one corner: only the corner vertex and its two
        // direct grid neighbours (distance 1.0) fall within reach; the
        // diagonal one, at distance √2, does not.
        final refused = history.run(
          PaintWeights(
            objectId: 10,
            skeletonIndex: 0,
            joint: 2,
            samples: <BrushSample>[
              BrushSample(center: Vector3.zero(), radius: 1.05),
            ],
            strength: 0.5,
          ),
        );
        expect(refused, isNull);

        var touched = 0;
        for (var v = 0; v < points.length; v++) {
          if (_weightOf(mesh, v, 1) > 0) touched++;
        }
        expect(touched, greaterThan(0));
        expect(touched / points.length, lessThanOrEqualTo(0.01));
      },
    );
  });
}
