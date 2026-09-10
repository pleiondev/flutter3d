/// The mesh a rail button actually presses.
///
///     flutter test test/mesh_session_test.dart
///
/// Everything here is arithmetic over an `EditMesh` and needs no window, which
/// is the point of the session being its own object: what a button does can be
/// tested by pressing it, without pumping a widget or opening a device.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/mesh_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A session over the cube a project starts as.
MeshSession cube() => MeshSession(EditMesh.cuboid());

/// Everything at [level], which is what "select all" would give.
Selection all(EditMesh mesh, ElementLevel level) => Selection.of(level, <int>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) face,
]).convertedTo(mesh, level);

void main() {
  group('an operation', () {
    test('extrude adds geometry and can be undone', () {
      final session = cube();
      final faces = session.mesh.faceCount;
      session.select(Selection.of(ElementLevel.face, <int>[0]));
      final before = session.meshVersion;

      expect(session.run('mesh.extrude'), isNull);

      // A quad extruded is four walls and the cap put back: five faces where
      // there was one.
      expect(session.mesh.faceCount, faces + 4);
      expect(session.meshVersion, greaterThan(before));

      expect(session.undo(), isTrue);
      // Mutation: drop the `beginStep`/`endStep` pair around the operation and
      // this is false — nothing was recorded, so a person who extrudes the
      // wrong face has no way back and the model is spoilt. That the journal is
      // `EditMesh`'s own is exactly why undo can exist before the document
      // does.
      expect(session.mesh.faceCount, faces);
    });

    test('a refusal is a sentence and leaves nothing behind', () {
      final session = cube();
      final depth = session.mesh.undoDepth;

      final said = session.run('mesh.extrude');

      expect(said, isNotNull);
      expect(said, contains('selected'));
      // `endStep` discards a step that wrote nothing, so the journal is where
      // it was without anybody having to tidy up.
      expect(session.mesh.undoDepth, depth);
      expect(session.meshVersion, 1);
    });

    test('a refusal does not take back the edit before it', () {
      final session = cube()..select(Selection.of(ElementLevel.face, <int>[0]));
      session.run('mesh.extrude');
      final faces = session.mesh.faceCount;

      // Nothing selected any more at face level that extrude can use? It is —
      // so refuse a different way: a loop cut needs an edge, and the selection
      // after an extrude is the cap it made, at face level.
      session.select(Selection.empty(ElementLevel.face));
      expect(session.run('mesh.extrude'), isNotNull);

      // Mutation: undo unconditionally after a refusal, which is what "throw
      // the empty step away" looks like written the obvious way — and the
      // extrude before it silently comes out, because `endStep` had already
      // discarded the empty step and the undo went one further back.
      expect(session.mesh.faceCount, faces);
    });

    test('a loop cut across an edge adds a ring of faces', () {
      final session = cube()..select(Selection.of(ElementLevel.edge, <int>[0]));

      expect(session.run('mesh.loopCut'), isNull);

      // Six faces become ten: the four the loop crossed are each split in two.
      expect(session.mesh.faceCount, 10);
    });

    test('deleting takes the faces out', () {
      final session = cube()..select(Selection.of(ElementLevel.face, <int>[0]));

      expect(session.run('mesh.delete'), isNull);

      expect(session.mesh.faceCount, 5);
      expect(session.undo(), isTrue);
      expect(session.mesh.faceCount, 6);
    });

    test('a tool the session does not perform is a fault, not a refusal', () {
      final session = cube();

      // Mutation: answer an unknown id with a refusal sentence instead, and a
      // tool added to the rail with no case behind it looks to a person exactly
      // like a tool that had nothing to work on — which is the one bug this
      // arrangement exists to make loud.
      expect(() => session.run('mesh.select'), throwsArgumentError);
      expect(() => session.run('mesh.bevel'), throwsArgumentError);
    });
  });

  group('the picker and the buffers', () {
    test('follow the topology after a cut', () {
      final session = cube()..select(Selection.of(ElementLevel.edge, <int>[0]));
      final before = session.picker;

      session.run('mesh.loopCut');

      // Mutation: skip the rebuild when `topologyChanged` and this is the same
      // object — a tree built against six faces answering clicks on a mesh that
      // now has ten, so a click lands on a face that is not under it.
      expect(identical(session.picker, before), isFalse);
      expect(session.toMeshData().triangleCount, greaterThan(0));
    });

    test('a move refits rather than rebuilds', () {
      final session = cube();
      session.select(all(session.mesh, ElementLevel.vertex));
      final before = session.picker;

      expect(
        session.transformBy(Matrix4.translation(Vector3(0, 0.5, 0))),
        isNull,
      );

      // Positions moved and nothing else did, so the tree is the same tree with
      // new boxes in it. Rebuilding would be correct and would cost a pass over
      // the whole mesh on every frame of a drag.
      expect(identical(session.picker, before), isTrue);
    });
  });

  group('the selection', () {
    test('shift takes an element back out', () {
      final session = cube()
        ..select(Selection.of(ElementLevel.face, <int>[0, 1]));

      session.select(Selection.of(ElementLevel.face, <int>[1]), extend: true);

      // Mutation: use `union` for the extended case, which is what "shift adds"
      // sounds like, and dropping one face out of a selection of forty means
      // building the other thirty-nine again.
      expect(session.selection.ids, <int>[0]);
    });

    test('a level change carries the selection across', () {
      final session = cube()..select(Selection.of(ElementLevel.face, <int>[0]));

      session.setLevel(ElementLevel.vertex);

      // The four corners of the quad. Mutation: clear the selection on a level
      // change instead, and pressing 1 to nudge the corners of the face you
      // just picked empties the viewport.
      expect(session.selection.level, ElementLevel.vertex);
      expect(session.selection.ids, hasLength(4));
    });

    test('shift at a different level replaces rather than mixes', () {
      final session = cube()
        ..select(Selection.of(ElementLevel.face, <int>[0]))
        ..select(Selection.of(ElementLevel.vertex, <int>[7]), extend: true);

      expect(session.selection.level, ElementLevel.vertex);
      expect(session.selection.ids, <int>[7]);
    });
  });

  group('the step an operation takes', () {
    test('is a share of the model rather than a number of metres', () {
      final small = MeshSession(EditMesh.cuboid(size: Vector3.all(0.02)));
      final large = MeshSession(EditMesh.cuboid(size: Vector3.all(200.0)));

      // Mutation: fix the step at 0.1 and an extrusion on the small one moves
      // the cap five times its own width, while on the large one it does not
      // move far enough to see.
      expect(large.step / small.step, closeTo(10000, 1));
    });
  });
}
