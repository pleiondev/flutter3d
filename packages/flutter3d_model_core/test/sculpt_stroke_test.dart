/// `SculptStroke` — `pro-sc-06`: a whole stroke as one command, one undo
/// step, and a history that counts bytes rather than steps.
///
/// `sculpt_brush_test.dart` (`flutter3d_mesh`) already covers what each brush
/// does to a `SculptMesh`. This file covers what only exists once a brush is
/// a command: the refusals, the JSON round trip an agent and a journal both
/// read, a stroke landing on the document's own mesh, undo being byte-exact,
/// the row's own "a hundred strokes cost far less than a hundred copies"
/// measurement, and `historyBudgetBytes` dropping the oldest steps when a
/// session asks for more memory than it may have.
///
///     dart test test/sculpt_stroke_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A flat grid of [side] × [side] vertices spanning `0..1` in x and y, at
/// `z = 0` — a surface with enough vertices for a brush's footprint to be a
/// small fraction of the whole, which is the shape the row's own acceptance
/// is written about.
EditMesh grid(int side) {
  final builder = EditMeshBuilder();
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      builder.addVertex(Vector3(x / (side - 1), y / (side - 1), 0));
    }
  }
  for (var y = 0; y < side - 1; y++) {
    for (var x = 0; x < side - 1; x++) {
      final int at = y * side + x;
      builder.addFace(<int>[at, at + 1, at + side + 1, at + side]);
    }
  }
  final EditMesh mesh = builder.build();
  // Nothing before the grid existed, so nothing to go back to — the same
  // thing an import does.
  mesh.clearJournal();
  return mesh;
}

({ModelHistory history, EditMesh mesh, int objectId}) sheet({
  int side = 160,
  int? budgetBytes,
}) {
  final EditMesh mesh = grid(side);
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 7,
        name: 'sheet',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
      ),
    ],
  );
  return (
    history: budgetBytes == null
        ? ModelHistory(project)
        : ModelHistory(project, historyBudgetBytes: budgetBytes),
    mesh: mesh,
    objectId: 7,
  );
}

SculptStroke draw({
  required int objectId,
  double radius = 0.06,
  double strength = 0.5,
  List<Vector3>? points,
  List<double> pressures = const <double>[],
}) => SculptStroke(
  objectId: objectId,
  kind: BrushKind.draw,
  radius: radius,
  strength: strength,
  points: points ?? <Vector3>[Vector3(0.5, 0.5, 0)],
  pressures: pressures,
);

Float32List positionsOf(EditMesh mesh) {
  final out = Float32List(mesh.vertexSlotCount * 3);
  final at = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, at);
    out[v * 3] = at.x;
    out[v * 3 + 1] = at.y;
    out[v * 3 + 2] = at.z;
  }
  return out;
}

void main() {
  group('the stroke reaches the document', () {
    test('and moves the vertices under it, leaving the rest alone', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);
      final Float32List before = positionsOf(mesh);

      expect(history.run(draw(objectId: objectId)), isNull);

      final Float32List after = positionsOf(mesh);
      var moved = 0;
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (after[v * 3 + 2] != before[v * 3 + 2]) moved++;
      }
      expect(moved, greaterThan(0));
      // **A brush is local, and a test that only asked "did anything move"
      // would pass on a command that moved everything.** Mutation: drop the
      // radius check inside `verticesWithinRadius` and every stroke becomes
      // a global displacement — still "a stroke that worked" by any looser
      // assertion here.
      expect(moved, lessThan(mesh.vertexCount ~/ 4));
    });

    test('a stroke is one step, however many points it has', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);

      expect(
        history.run(
          draw(
            objectId: objectId,
            points: <Vector3>[
              for (var i = 0; i < 20; i++) Vector3(0.2 + i * 0.03, 0.5, 0),
            ],
          ),
        ),
        isNull,
      );

      // Twenty dabs, one ⌘Z. A command per pointer sample would need twenty.
      expect(history.steps, hasLength(1));
      expect(mesh.undoDepth, 1);
      expect(history.undoSays, 'sculpt');
    });

    test('a point at zero pressure moves the brush without sculpting', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);
      final Float32List before = positionsOf(mesh);

      expect(
        history.run(
          draw(
            objectId: objectId,
            points: <Vector3>[Vector3(0.5, 0.5, 0), Vector3(0.2, 0.2, 0)],
            pressures: <double>[1, 0],
          ),
        ),
        isNull,
      );

      final Float32List after = positionsOf(mesh);
      final int atSecond = 12 * 60 + 12; // near (0.2, 0.2)
      expect(after[atSecond * 3 + 2], before[atSecond * 3 + 2]);
    });
  });

  group('undo', () {
    test('puts every float back exactly as it was', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);
      final Float32List before = positionsOf(mesh);

      expect(history.run(draw(objectId: objectId)), isNull);
      expect(positionsOf(mesh), isNot(before));
      expect(history.undo(), isTrue);

      // **Byte-exact, the row's own word.** Mutation: undo a stroke by
      // re-running the brush with a negated strength. It looks right on a
      // draw brush and is wrong for every other one, and wrong even for
      // draw wherever a falloff or a clamp is not its own inverse — the
      // failure a journal of previous values cannot have.
      expect(positionsOf(mesh), before);
    });

    test('and redo puts it back', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);
      expect(history.run(draw(objectId: objectId)), isNull);
      final Float32List sculpted = positionsOf(mesh);

      expect(history.undo(), isTrue);
      expect(history.redo(), isTrue);

      expect(positionsOf(mesh), sculpted);
    });

    test('a stroke after an undo sculpts the shape that is there now', () {
      final (:history, :mesh, :objectId) = sheet(side: 60);
      final Float32List before = positionsOf(mesh);

      expect(history.run(draw(objectId: objectId)), isNull);
      expect(history.undo(), isTrue);
      expect(history.run(draw(objectId: objectId)), isNull);
      final Float32List once = positionsOf(mesh);

      // **The kept sculpt mesh has to notice an undo.** Mutation: keep the
      // cached `SculptMesh` regardless of what else moved the mesh. The
      // second stroke would then push from the *undone* positions and land
      // twice as far out, and nothing about the command would look wrong.
      expect(history.undo(), isTrue);
      expect(history.run(draw(objectId: objectId)), isNull);
      expect(positionsOf(mesh), once);
      expect(positionsOf(mesh), isNot(before));
    });
  });

  group('what a hundred strokes cost', () {
    test('far less than a hundred copies of the mesh', () {
      const int side = 160;
      final (:history, :mesh, :objectId) = sheet(side: side);

      for (var i = 0; i < 100; i++) {
        expect(
          history.run(
            draw(
              objectId: objectId,
              // Spread over the sheet rather than stacked, so the run is a
              // hundred distinct footprints rather than one chunk written a
              // hundred times.
              points: <Vector3>[
                Vector3(0.1 + (i % 10) * 0.08, 0.1 + (i ~/ 10) * 0.08, 0),
              ],
              strength: 0.05,
            ),
          ),
          isNull,
        );
      }

      final int oneCopy = mesh.vertexCount * 3 * 4;
      // The row's own acceptance, stated at whatever size this fixture
      // happens to be: it is a ratio, and the ratio is what the chunked,
      // journalled shape buys. Copying the whole document per stroke — the
      // obvious way to make undo byte-exact — is the hundred copies.
      expect(mesh.journalBytes, lessThan(oneCopy * 100 * 0.1));
      // And each stroke on its own really is the footprint the row names:
      // around one per cent of the mesh, not a fixed overhead that happens
      // to be small on this fixture.
      expect(mesh.journalBytes / 100, lessThan(oneCopy * 0.03));
    });
  });

  group('the byte budget', () {
    test('drops the oldest steps, keeping the newest undoable', () {
      final (:history, :mesh, :objectId) = sheet(side: 60, budgetBytes: 5000);

      for (var i = 0; i < 20; i++) {
        expect(
          history.run(
            draw(
              objectId: objectId,
              points: <Vector3>[Vector3(0.2 + i * 0.03, 0.5, 0)],
              strength: 0.05,
            ),
          ),
          isNull,
        );
      }

      // **Bytes, not steps** — `depth` is 64 and would have kept all twenty.
      expect(history.steps.length, lessThan(20));
      expect(mesh.journalBytes, lessThanOrEqualTo(5000));
      // The newest is never dropped: whatever a person just did stays
      // undoable.
      expect(history.canUndo, isTrue);
      expect(history.undo(), isTrue);
    });

    test('and a step and its mesh journal go together', () {
      final (:history, :mesh, :objectId) = sheet(side: 60, budgetBytes: 5000);
      for (var i = 0; i < 20; i++) {
        expect(
          history.run(
            draw(
              objectId: objectId,
              points: <Vector3>[Vector3(0.2 + i * 0.03, 0.5, 0)],
              strength: 0.05,
            ),
          ),
          isNull,
        );
      }

      // **Mutation: drop the `HistoryStep` and leave the journal entry.**
      // The memory the budget exists to reclaim would stay, and the mesh
      // would be holding more steps than the history can ever walk. The
      // other way round is worse: a step offering an undo whose journal
      // entry has gone takes the *wrong* one back, since `EditMesh.undo`
      // pops whatever is on top of its own stack.
      expect(mesh.undoDepth, history.steps.length);

      var taken = 0;
      while (history.undo()) {
        taken++;
      }
      expect(taken, greaterThan(0));
      expect(mesh.undoDepth, 0);
    });
  });

  group('refusals', () {
    test('an object that is not there', () {
      final (:history, :mesh, :objectId) = sheet(side: 20);
      expect(history.run(draw(objectId: 999)), contains('999'));
    });

    test('an object with no mesh', () {
      final ModelProject project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 3,
            name: 'empty',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity(),
          ),
        ],
      );
      expect(
        ModelHistory(project).run(draw(objectId: 3)),
        contains('no mesh to sculpt'),
      );
    });

    test('a stroke with no points', () {
      final (:history, :mesh, :objectId) = sheet(side: 20);
      expect(
        history.run(draw(objectId: objectId, points: <Vector3>[])),
        contains('at least one point'),
      );
    });

    test('pressures that do not match the points', () {
      final (:history, :mesh, :objectId) = sheet(side: 20);
      expect(
        history.run(
          draw(
            objectId: objectId,
            points: <Vector3>[Vector3.zero(), Vector3(0.1, 0, 0)],
            pressures: <double>[1],
          ),
        ),
        contains('2 points and 1 pressures'),
      );
    });

    test('a brush that reaches nothing', () {
      final (:history, :mesh, :objectId) = sheet(side: 20);
      expect(
        history.run(draw(objectId: objectId, radius: 0)),
        contains('reaches nothing'),
      );
      // A radius that is positive but lands off the sheet is a different
      // refusal: the brush is fine, there was simply nothing under it.
      expect(
        history.run(
          draw(
            objectId: objectId,
            radius: 0.01,
            points: <Vector3>[Vector3(50, 50, 0)],
          ),
        ),
        contains('reached no vertices'),
      );
      // A refusal is not a step.
      expect(history.canUndo, isFalse);
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      const SculptStroke stroke = SculptStroke(
        objectId: 7,
        kind: BrushKind.clay,
        radius: 0.25,
        strength: 0.4,
        points: <Vector3>[],
        falloff: BrushFalloff.sharp,
        symmetryX: true,
      );
      final Map<String, Object?> json = <String, Object?>{
        ...stroke.toJson(),
        'points': <Object?>[
          <double>[0, 0, 0],
          <double>[1, 0, 0],
        ],
        'pressures': <double>[1, 0.5],
      };

      final ModelCommand? read = modelCommandFromJson(json);
      expect(read, isA<SculptStroke>());
      final SculptStroke back = read! as SculptStroke;
      expect(back.kind, BrushKind.clay);
      expect(back.falloff, BrushFalloff.sharp);
      expect(back.symmetryX, isTrue);
      expect(back.points, hasLength(2));
      expect(back.pressures, <double>[1, 0.5]);
      expect(back.radius, 0.25);
    });

    test('and is one of the names an agent can call', () {
      // The MCP tool table is this list — see `ModelCommand`'s own doc
      // comment. A command missing from it is one no agent can run.
      expect(modelCommandNames, contains('sculptStroke'));
    });

    test('a brush that is not a brush does not read back', () {
      expect(
        modelCommandFromJson(<String, Object?>{
          'name': 'sculptStroke',
          'objectId': 7,
          'kind': 'airbrush',
          'radius': 0.1,
          'strength': 0.5,
          'points': <Object?>[
            <double>[0, 0, 0],
          ],
        }),
        isNull,
      );
    });
  });
}
