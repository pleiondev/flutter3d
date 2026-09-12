/// `anim-10`'s own row: `PaintWeights(joint, samples, strength, mode,
/// mirror, normalize)`, hit-tested against a vertex's own current posed
/// position rather than its bind pose.
///
///     dart test test/paint_weights_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own, the same shape `ik_constraint_test.dart`
/// and `shape_driver_test.dart` already build fixtures out of.
ModelObject _joint(int id, {int? parent, required Matrix4 transform}) => ModelObject(
  id: id,
  name: 'joint$id',
  geometry: const SocketGeometry(),
  transform: transform,
  parent: parent,
);

/// A small quad of four vertices centred on [at], in the XY plane.
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

/// Root joint (1) at the origin; mid joint (2), a child of it one unit out
/// along +X, bent 90° about Z so a vertex rigidly following it swings from
/// its own bind position out to the side rather than staying in line with
/// the root — an elbow, mid-bend. A third joint (3), unposed and currently
/// influencing nothing, is the one a stroke paints new weight onto.
///
/// The mesh itself: a "shoulder" quad (vertices 0–3) bound entirely to the
/// root, sitting near the origin in both bind pose and posed shape since the
/// root never turns; a "forearm" quad (vertices 4–7) bound entirely to the
/// mid joint, whose bind position — (2, 0, 0) — [`inverseBindMatrices[1]`
/// undoes the mid joint's own *unbent* world transform, `Matrix4.translation
/// (1, 0, 0)`] is nowhere near where the bend actually puts it: composing
/// the mid joint's posed world transform with that inverse bind matrix
/// carries a forearm vertex out to (1, 1, 0) instead.
({ModelProject project, EditMesh mesh}) _bentArm() {
  final mesh = EditMesh.fromFaces(
    <Vector3>[..._quadAt(Vector3.zero()), ..._quadAt(Vector3(2, 0, 0))],
    <List<int>>[
      <int>[0, 1, 2, 3],
      <int>[4, 5, 6, 7],
    ],
  );
  _edit(mesh, () {
    for (var v = 0; v < 4; v++) {
      mesh.setSkin(v, VertexAttributes(joints: Vector4(0, 0, 0, 0), weights: Vector4(1, 0, 0, 0)));
    }
    for (var v = 4; v < 8; v++) {
      mesh.setSkin(v, VertexAttributes(joints: Vector4(1, 0, 0, 0), weights: Vector4(1, 0, 0, 0)));
    }
  });

  final bend = Matrix4.translation(Vector3(1, 0, 0))..multiply(Matrix4.rotationZ(1.5707963267948966));
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
  return (project: project, mesh: mesh);
}

double _weightOf(EditMesh mesh, int vertex, int localJoint) {
  final match = weightsOf(mesh, vertex).where((p) => p.joint == localJoint);
  return match.isEmpty ? 0.0 : match.single.weight;
}

/// Vertex 4's own weight on joint index 2 after exactly one of the drag's
/// own samples, painted on a fresh copy of the same fixture — the baseline
/// three stacked samples must beat for the test above to mean anything.
double _bentArmSingleSampleWeight() {
  final fixture = _bentArm();
  paintWeights(
    project: fixture.project,
    mesh: fixture.mesh,
    skeleton: fixture.project.skeletons.single,
    joint: 3,
    samples: <BrushSample>[BrushSample(center: Vector3(1, 1, 0), radius: 0.3)],
    strength: 0.6,
  );
  return _weightOf(fixture.mesh, 4, 2);
}

void main() {
  group("anim-10's own acceptance: a stroke in a bent pose hits the elbow", () {
    test('the forearm quad is painted, found at its posed position, not its bind position', () {
      final fixture = _bentArm();
      final project = fixture.project;
      final mesh = fixture.mesh;
      final skeleton = project.skeletons.single;

      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: skeleton,
        joint: 3,
        // The forearm quad's own posed centre — (1, 1, 0) — never its bind
        // centre, (2, 0, 0): a brush aimed here only finds anything because
        // hit-testing reads the posed shape. Both quads' own bind and posed
        // shoulder/root positions sit well outside this radius, so a hit
        // here can only be the forearm quad, and only by way of its bend.
        samples: <BrushSample>[BrushSample(center: Vector3(1, 1, 0), radius: 0.3)],
        strength: 0.6,
      );

      // localJoint 2 is id 3, the joint being painted onto.
      for (var v = 4; v < 8; v++) {
        expect(_weightOf(mesh, v, 2), greaterThan(0.0), reason: 'forearm vertex $v');
      }
      // The shoulder quad, near the unmoving root, is untouched.
      for (var v = 0; v < 4; v++) {
        expect(_weightOf(mesh, v, 2), 0.0, reason: 'shoulder vertex $v');
      }
    });

    test('a target the bend moves away from is missed, proving this is not a lucky bind-pose hit', () {
      final fixture = _bentArm();
      final project = fixture.project;
      final mesh = fixture.mesh;
      final skeleton = project.skeletons.single;

      // The forearm quad's own BIND centre — where a bind-pose-only
      // implementation would look, and where the quad no longer is once
      // bent.
      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: skeleton,
        joint: 3,
        samples: <BrushSample>[BrushSample(center: Vector3(2, 0, 0), radius: 0.3)],
        strength: 0.6,
      );

      for (var v = 0; v < 8; v++) {
        expect(_weightOf(mesh, v, 2), 0.0, reason: 'vertex $v');
      }
    });
  });

  group("anim-10's own acceptance: one drag is one step", () {
    test('undoing once reverts every sample in the drag, not just the last one', () {
      final fixture = _bentArm();
      final project = fixture.project;
      final mesh = fixture.mesh;
      final skeleton = project.skeletons.single;

      final before = weightsOf(mesh, 4).map((p) => (p.joint, p.weight)).toList();

      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: skeleton,
        joint: 3,
        samples: <BrushSample>[
          BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
          BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
          BrushSample(center: Vector3(1, 1, 0), radius: 0.3),
        ],
        strength: 0.6,
      );
      // Three overlapping samples actually stacked onto one vertex — not
      // three independent, non-accumulating hits — so a partial undo
      // (reverting only the last one) would leave a visibly different,
      // intermediate weight rather than the exact pre-stroke one.
      final oneSampleWeight = _bentArmSingleSampleWeight();
      expect(_weightOf(mesh, 4, 2), greaterThan(oneSampleWeight));

      final undid = mesh.undo();
      expect(undid, isTrue);
      final after = weightsOf(mesh, 4).map((p) => (p.joint, p.weight)).toList();
      expect(after, before);
    });
  });

  group('mirror and normalize', () {
    test('mirror carries a stroke on one side onto its geometric partner on the other', () {
      final mesh = EditMesh.cuboid();
      final project = ModelProject(
        objects: <ModelObject>[
          _joint(1, transform: Matrix4.identity()),
          ModelObject(
            id: 10,
            name: 'box',
            geometry: EditedGeometry(mesh),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(joints: <int>[1], inverseBindMatrices: <Matrix4>[Matrix4.identity()]),
        ],
      );
      _edit(mesh, () {
        for (var v = 0; v < 8; v++) {
          mesh.setSkin(v, VertexAttributes(joints: Vector4(0, 0, 0, 0), weights: Vector4(1, 0, 0, 0)));
        }
      });

      // `EditMesh.cuboid()`'s own vertex 1, (0.5, -0.5, -0.5), is vertex 0's
      // mirror image across the x = 0 plane.
      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: project.skeletons.single,
        joint: 1,
        samples: <BrushSample>[BrushSample(center: Vector3(-0.5, -0.5, -0.5), radius: 0.05)],
        strength: 0.4,
        mirror: const PaintMirror(axis: 0, jointMirror: <int, int>{}),
      );

      List<(int, double)> asTuples(int vertex) =>
          weightsOf(mesh, vertex).map((p) => (p.joint, p.weight)).toList();
      expect(asTuples(0), asTuples(1));
    });

    test('normalize renormalizes an assign that left a vertex short of one', () {
      final mesh = EditMesh.cuboid();
      final project = ModelProject(
        objects: <ModelObject>[
          _joint(1, transform: Matrix4.identity()),
          ModelObject(
            id: 10,
            name: 'box',
            geometry: EditedGeometry(mesh),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(joints: <int>[1], inverseBindMatrices: <Matrix4>[Matrix4.identity()]),
        ],
      );

      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: project.skeletons.single,
        joint: 1,
        samples: <BrushSample>[BrushSample(center: mesh.positionOf(0), radius: 0.01)],
        strength: 0.4,
        mode: PaintWeightsMode.assign,
        normalize: true,
      );

      final total = weightsOf(mesh, 0).fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(1.0, 1e-6));
    });

    test('without normalize, an assign below full strength is left exactly as assigned', () {
      final mesh = EditMesh.cuboid();
      final project = ModelProject(
        objects: <ModelObject>[
          _joint(1, transform: Matrix4.identity()),
          ModelObject(
            id: 10,
            name: 'box',
            geometry: EditedGeometry(mesh),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(joints: <int>[1], inverseBindMatrices: <Matrix4>[Matrix4.identity()]),
        ],
      );

      paintWeights(
        project: project,
        mesh: mesh,
        skeleton: project.skeletons.single,
        joint: 1,
        samples: <BrushSample>[BrushSample(center: mesh.positionOf(0), radius: 0.01)],
        strength: 0.4,
        mode: PaintWeightsMode.assign,
      );

      final total = weightsOf(mesh, 0).fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(0.4, 1e-6));
    });
  });
}
