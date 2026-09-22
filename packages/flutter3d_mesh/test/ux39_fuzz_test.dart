/// `ux-39`'s own acceptance: five hundred insets, slides and bridges over
/// three seeds, and the mesh still validates after every one of them.
///
/// **Its own walk rather than three more cases in `fuzz_test.dart`.** That
/// file's operation list is what decides its random sequence, so adding to
/// it replaces the five hundred steps it has been green on with five hundred
/// different ones — and the different ones turn out to reach a
/// `dissolveVertex` fault that predates this row (a live face left holding a
/// dissolved vertex; the shrunk sequence needs no operation from this row at
/// all, and reproduces with all three of them stubbed out). Widening that
/// file is the right thing to do once that is fixed, and doing it now would
/// leave a red test standing in for somebody else's bug.
///
/// So this walk leaves `dissolve` out and keeps everything these three
/// operations actually have to survive beside: moves, extrusions, loop cuts,
/// and each other.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two squares facing each other: the smallest shape with two borders a
/// bridge can join, and the one the walk below starts from.
///
/// **Not a tube.** A tube's two rims are already joined to each other, one
/// side edge per corner, so bridging them would put a second edge between a
/// pair of vertices that already share one — which `bridgeLoops` refuses,
/// and rightly. Two separate squares are the case a person actually reaches
/// for.
EditMesh twoSquares({double apart = 3.0}) => EditMesh.fromFaces(
  <Vector3>[
    Vector3(-1, 0, -1),
    Vector3(1, 0, -1),
    Vector3(1, 0, 1),
    Vector3(-1, 0, 1),
    Vector3(-1, apart, -1),
    Vector3(1, apart, -1),
    Vector3(1, apart, 1),
    Vector3(-1, apart, 1),
  ],
  <List<int>>[
    <int>[0, 1, 2, 3],
    <int>[7, 6, 5, 4],
  ],
);

List<int> _liveFaces(EditMesh mesh) => <int>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) face,
];

List<int> _liveEdges(EditMesh mesh) {
  final found = <int>[];
  for (final int face in _liveFaces(mesh)) {
    mesh.forEachHalfEdge(face, (int half) {
      if (mesh.edgeOf(half) == half) found.add(half);
    });
  }
  return found;
}

List<int> _borders(EditMesh mesh) => <int>[
  for (final int edge in _liveEdges(mesh))
    if (!mesh.hasLiveTwin(edge)) edge,
];

/// One step of the walk. Returns what went wrong, or null.
String? _step(EditMesh mesh, int op, int pick) {
  final faces = _liveFaces(mesh);
  final edges = _liveEdges(mesh);
  if (faces.isEmpty || edges.isEmpty) return null;
  mesh.beginStep();
  switch (op) {
    case 0:
      insetFaces(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[pick % faces.length]]),
        thickness: 0.05 + (pick % 7) * 0.02,
        depth: pick.isEven ? 0.0 : 0.1,
      );
    case 1:
      slideEdges(
        mesh,
        Selection.of(ElementLevel.edge, <int>[edges[pick % edges.length]]),
        amount: pick.isEven ? 0.3 : -0.6,
      );
    case 2:
      final borders = _borders(mesh);
      if (borders.isNotEmpty) {
        bridgeLoops(mesh, Selection.of(ElementLevel.edge, borders));
      }
    case 3:
      extrudeFaces(
        mesh,
        Selection.of(ElementLevel.face, <int>[faces[pick % faces.length]]),
        distance: 0.2,
      );
    case 4:
      loopCut(
        mesh,
        Selection.of(ElementLevel.edge, <int>[edges[pick % edges.length]]),
      );
    case 5:
      translateSelection(
        mesh,
        Selection.of(ElementLevel.edge, <int>[edges[pick % edges.length]]),
        by: Vector3(0.05, 0.1, -0.05),
      );
  }
  mesh.endStep();

  try {
    mesh.validate();
  } on StateError catch (error) {
    return 'validate: ${error.message}';
  }
  try {
    MeshChecks(mesh).all();
  } on Object catch (error) {
    return 'a check threw: $error';
  }
  return null;
}

void main() {
  test('five hundred of ux-39\'s own operations, three seeds', () {
    for (final int seed in <int>[1234, 5678, 91011]) {
      final random = math.Random(seed);
      final mesh = twoSquares();
      for (var i = 0; i < 500; i++) {
        final int op = random.nextInt(6);
        final int pick = random.nextInt(1000);
        final String? failure = _step(mesh, op, pick);
        if (failure != null) {
          fail('seed $seed, step $i (op $op, pick $pick): $failure');
        }
      }
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('the starting shape is two borders, and bridging closes them', () {
    final mesh = twoSquares();
    mesh.beginStep();
    final OpResult result = bridgeLoops(
      mesh,
      Selection.of(ElementLevel.edge, _borders(mesh)),
    );
    mesh.endStep();

    expect(result.reason, isNull);
    expect(_borders(mesh), isEmpty);
    mesh.validate();
  });
}
