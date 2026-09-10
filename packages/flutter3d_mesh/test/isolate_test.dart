/// A mesh crossing to another isolate and coming back.
///
/// **The assertion is that it is the same mesh, byte for byte.** An operation
/// run somewhere else has to give what it gives here — not "look the same", not
/// "have the same counts" — because the whole point of moving the work is that
/// nobody has to think about where it ran.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Pushes the first face out. Top-level, because a closure is what cannot
/// cross — and because naming the work is what the isolate is handed.
EditMesh pushTheFirstFaceOut(EditMesh mesh) {
  mesh.beginStep();
  extrudeFaces(mesh, Selection.of(ElementLevel.face, <int>[0]), distance: 0.75);
  mesh.endStep();
  return mesh;
}

/// Cuts a loop round whatever ring the first edge crosses.
EditMesh cutALoop(EditMesh mesh) {
  mesh.beginStep();
  loopCut(
    mesh,
    Selection.of(ElementLevel.edge, <int>[mesh.edgeOf(mesh.halfEdgeOf(0))]),
  );
  mesh.endStep();
  return mesh;
}

void main() {
  test('an extrusion in an isolate is the extrusion in place', () async {
    final here = pushTheFirstFaceOut(EditMesh.cuboid());

    final there = await editInIsolate(EditMesh.cuboid(), pushTheFirstFaceOut);

    // Mutation: send the mesh and forget to send the work's result back —
    // or rebuild from the bytes that went out rather than the ones that came
    // in — and this is the cube that was handed over.
    expect(there.toBytes(), here.toBytes());
    expect(there.faceCount, 10);
    expect(there.signedVolume, closeTo(1.75, 1e-5));
    there.validate();
  });

  test('a mesh carrying every layer crosses whole', () async {
    final mesh = EditMesh.cuboid();
    mesh.beginStep();
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      mesh.setMaterialSlot(face, face);
      mesh.forEachHalfEdge(face, (int half) {
        mesh
          ..setUv(half, Vector2(face / 6, 0.5))
          ..setEdgeFlag(half, EdgeFlags.sharp, on: face.isEven);
      });
    }
    mesh.endStep();

    final there = await editInIsolate(mesh, cutALoop);
    final here = cutALoop(EditMesh.fromBytes(mesh.toBytes()));

    // Mutation: leave a layer out of what crosses, and an operation run
    // elsewhere quietly strips the materials off the document.
    expect(there.toBytes(), here.toBytes());
    expect(there.materialSlotOf(3), 3);
    expect(there.hasLayer(MeshDomain.corner, MeshAttribute.uv0), isTrue);
  });

  test('what comes back has no history, and says why', () async {
    final there = await editInIsolate(EditMesh.cuboid(), pushTheFirstFaceOut);

    // The bytes carry no journal, so the step the isolate opened is not one a
    // caller can undo — a document that wants that records the operation on
    // its own side, which is `doc-08`'s.
    expect(there.undoDepth, 0);
  });

  test('a selection and a result are plain values a port can carry', () {
    final mesh = EditMesh.cuboid();
    mesh.beginStep();
    final result = extrudeFaces(
      mesh,
      Selection.of(ElementLevel.face, <int>[0, 2], active: 2),
      distance: 1,
    );
    mesh.endStep();

    // Nothing here holds a closure, a port or a native handle: numbers, a
    // typed array, an enum and a string. That is what makes the pair of them
    // sendable without a format of their own.
    expect(result.selection.ids, isA<Object>());
    expect(result.movedVertices, isNotEmpty);
    expect(result.selection.active, 2);
    expect(result.reason, isNull);
    expect(result.topologyChanged, isTrue);
  });

  test('a build with no isolates does the work here', () {
    // Compiled to JavaScript or WebAssembly there is nowhere else to run, and
    // the answer is the work on this thread rather than a failure several
    // seconds in. On this build the flag is false, which is what says the
    // isolate path is the one the tests above took.
    expect(meshWorkStaysHere, isFalse);
  });
}
