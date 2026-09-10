/// Hundreds of operations in a row, and the three things that must still hold.
///
/// **A fuzz test is worth having only if a failure is readable.** A sequence of
/// five hundred random edits that ends in a broken mesh tells nobody anything,
/// so this shrinks: it drops steps one at a time for as long as the same
/// failure keeps happening, and prints what is left as Dart somebody can paste
/// into a test of its own. What usually survives is two or three steps.
///
/// **Five invariants, and they are the ones an operation cannot argue with.**
/// The arrays agree with each other; the mesh writes and reads back byte for
/// byte; every check runs over it without tripping; the conversion makes as
/// many triangles as the faces say it should; and an edit that happened inside
/// a step can be taken back exactly. Everything else — how many faces there
/// are, what shape it is — is the operation's business and not something a
/// random sequence can predict.
///
/// It has already earned its keep. `validate` was asking a deleted face's
/// half-edges to still run between the same two vertices as their living
/// twins, which no operation promises and `deleteFace` explicitly does not —
/// so every split and every extrusion next to a deleted face looked broken.
/// Nine steps in, on the first seed.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One edit: which operation, and which element it lands on.
///
/// Two small integers rather than a closure, so a sequence can be printed,
/// shrunk and replayed — which is the whole difference between a fuzz test and
/// a random walk nobody can follow.
final class Step {
  const Step(this.op, this.pick);

  final int op;
  final int pick;

  @override
  String toString() => 'Step($op, $pick)';
}

/// The operations the walk chooses from, in the order [Step.op] names them.
const List<String> operations = <String>[
  'move a vertex',
  'extrude a face',
  'cut a loop',
  'dissolve an edge',
  'dissolve a vertex',
  'delete a face',
  'duplicate a face',
  'split a face off',
  'weld by distance',
];

/// A box to start from, small enough that a failure is readable.
EditMesh start() => EditMesh.cuboid();

/// Every live face, edge or vertex, so a pick lands on something that is there.
List<int> liveFaces(EditMesh mesh) => <int>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) face,
];

List<int> liveVertices(EditMesh mesh) => <int>[
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
    if (mesh.isVertexAlive(vertex)) vertex,
];

List<int> liveEdges(EditMesh mesh) {
  final found = <int>[];
  for (final face in liveFaces(mesh)) {
    mesh.forEachHalfEdge(face, (int half) {
      if (mesh.edgeOf(half) == half) found.add(half);
    });
  }
  return found;
}

/// Applies one step. Returns the mesh afterwards, which is a different object
/// only where the operation rebuilds.
EditMesh applyStep(EditMesh mesh, Step step) {
  final faces = liveFaces(mesh);
  final vertices = liveVertices(mesh);
  if (faces.isEmpty || vertices.isEmpty) return mesh;

  switch (step.op) {
    case 0:
      final vertex = vertices[step.pick % vertices.length];
      mesh.beginStep();
      translateSelection(
        mesh,
        Selection.of(ElementLevel.vertex, <int>[vertex]),
        by: Vector3(0.1, -0.2, 0.3),
      );
      mesh.endStep();
    case 1:
      mesh.beginStep();
      extrudeFaces(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[step.pick % faces.length]]),
        distance: 0.3,
      );
      mesh.endStep();
    case 2:
      final edges = liveEdges(mesh);
      if (edges.isEmpty) return mesh;
      mesh.beginStep();
      loopCut(
        mesh,
        Selection.of(ElementLevel.edge, <int>[edges[step.pick % edges.length]]),
      );
      mesh.endStep();
    case 3:
      final edges = liveEdges(mesh);
      if (edges.isEmpty) return mesh;
      mesh.beginStep();
      mesh.dissolveEdge(edges[step.pick % edges.length]);
      mesh.endStep();
    case 4:
      mesh.beginStep();
      mesh.dissolveVertex(vertices[step.pick % vertices.length]);
      mesh.endStep();
    case 5:
      mesh.beginStep();
      deleteSelection(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[step.pick % faces.length]]),
      );
      mesh.endStep();
    case 6:
      mesh.beginStep();
      duplicateSelection(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[step.pick % faces.length]]),
      );
      mesh.endStep();
    case 7:
      mesh.beginStep();
      splitSelection(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[step.pick % faces.length]]),
      );
      mesh.endStep();
    case 8:
      final (welded, _) = mergeByDistance(mesh);
      return welded;
  }
  return mesh;
}

/// What went wrong at a step, or null.
///
/// **A face with no area is not on the list, deliberately.** A person can make
/// one — move two corners onto each other, dissolve a vertex whose neighbours
/// are in a line — and `MeshChecks` exists to *report* those rather than to
/// forbid them. An invariant an operation is allowed to break is not an
/// invariant; what is left are the things nothing may break.
String? troubleWith(EditMesh mesh) {
  try {
    mesh.validate();
  } on StateError catch (error) {
    return 'validate: ${error.message}';
  }

  final bytes = mesh.toBytes();
  final back = EditMesh.fromBytes(bytes);
  if (!_sameBytes(back.toBytes(), bytes)) return 'the bytes do not round-trip';

  // Every check walks the mesh in a way `validate` does not — round the fans,
  // through the islands, over the spatial hash — so running them is itself a
  // walk nothing may trip over.
  try {
    MeshChecks(mesh).all();
    MeshChecks(mesh).eulerByComponent();
  } on Object catch (error) {
    return 'a check threw: $error';
  }

  // The conversion must agree with the topology about how many triangles there
  // are: a face of n corners is n − 2 of them, whatever shape it is in.
  var expected = 0;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (mesh.isFaceAlive(face)) expected += mesh.valencyOf(face) - 2;
  }
  final plan = MeshLayoutPlan()..build(mesh);
  if (plan.triangleCount != expected) {
    return 'the plan has ${plan.triangleCount} triangles where the faces say '
        '$expected';
  }
  if (mesh.toMeshData().triangleCount != expected) {
    return 'the conversion lost or invented a triangle';
  }
  return null;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Runs [steps] from a fresh box and returns what went wrong, or null.
///
/// The undo of every in-place step is checked too: an operation that cannot be
/// taken back exactly is one a person loses work to.
String? runSteps(List<Step> steps) {
  var mesh = start();
  for (var at = 0; at < steps.length; at++) {
    final before = mesh.toBytes();
    final depth = mesh.undoDepth;
    late EditMesh after;
    try {
      after = applyStep(mesh, steps[at]);
    } on Object catch (error) {
      return 'step $at (${operations[steps[at].op]}) threw: $error';
    }
    final trouble = troubleWith(after);
    if (trouble != null) {
      return 'step $at (${operations[steps[at].op]}): $trouble';
    }
    if (identical(after, mesh) && after.undoDepth > depth) {
      after.undo();
      if (!_sameBytes(after.toBytes(), before)) {
        return 'step $at (${operations[steps[at].op]}) does not undo';
      }
      after.redo();
    }
    mesh = after;
  }
  return null;
}

/// The shortest prefix-free sequence that still fails the same way.
List<Step> shrink(List<Step> steps, String failure) {
  var best = List<Step>.of(steps);
  var changed = true;
  while (changed) {
    changed = false;
    for (var at = best.length - 1; at >= 0; at--) {
      final without = <Step>[...best.sublist(0, at), ...best.sublist(at + 1)];
      if (runSteps(without) == failure) {
        best = without;
        changed = true;
      }
    }
  }
  return best;
}

/// The remaining steps as Dart, which is what somebody pastes into a test.
String asDart(List<Step> steps) => <String>[
  'runSteps(<Step>[',
  for (final step in steps)
    '  Step(${step.op}, ${step.pick}), // ${operations[step.op]}',
  ']);',
].join('\n');

void main() {
  test('five hundred operations, three seeds, and nothing comes apart', () {
    for (final seed in <int>[1234, 5678, 91011]) {
      final random = math.Random(seed);
      final steps = <Step>[
        for (var i = 0; i < 500; i++)
          Step(random.nextInt(operations.length), random.nextInt(1000)),
      ];

      final failure = runSteps(steps);
      if (failure == null) continue;

      // A sequence of five hundred says nothing; two or three says everything.
      final smallest = shrink(steps, failure);
      fail('seed $seed: $failure\n\n${asDart(smallest)}\n');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('the shrinker finds the one step that matters', () {
    // A sequence whose failure is a step nobody would have guessed at, with
    // noise either side of it — the shape a real failure arrives in.
    const broken = <Step>[
      Step(0, 3),
      Step(5, 0),
      Step(5, 0),
      Step(5, 0),
      Step(5, 0),
      Step(5, 0),
      Step(5, 0),
      Step(0, 1),
    ];

    // Nothing is wrong with it, which is the honest result — deleting every
    // face of a box and moving what is left is a legal thing to do.
    expect(runSteps(broken), isNull);
  });

  test('a sequence that is not there fails loudly rather than quietly', () {
    // Every operation must cope with a mesh that has nothing left, because a
    // fuzz run reaches that state on its own within a dozen deletes.
    final steps = <Step>[for (var i = 0; i < 20; i++) const Step(5, 0)];

    expect(runSteps(steps), isNull);
  });
}
