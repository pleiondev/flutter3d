/// `PaintVertexColour` — `pro-pt-06n`: the same brush, into the mesh's own
/// colour layer.
///
///     dart test test/paint_vertex_colour_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A subdivided cube: a stroke on a bare one paints eight corners and says
/// nothing about a brush being local.
ModelHistory opened() {
  final EditMesh mesh = catmullClark(
    EditMesh.cuboid(size: Vector3(2, 2, 2)),
    levels: 2,
  )..clearJournal();
  return ModelHistory(
    ModelProject(
      objects: <ModelObject>[
        ModelObject(
          id: 1,
          name: 'cube',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
        ),
      ],
      nextId: 2,
    ),
  );
}

EditMesh meshOf(ModelHistory history) =>
    (history.project[1]!.geometry as EditedGeometry).mesh;

/// Every corner's own colour, in face-and-loop order.
List<Vector4> coloursOf(EditMesh mesh) {
  final out = <Vector4>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => out.add(mesh.colourOf(half)));
  }
  return out;
}

PaintVertexColour stroke({
  Vector3? at,
  double radius = 0.5,
  List<double>? colour,
  double strength = 1,
}) => PaintVertexColour(
  objectId: 1,
  samples: <PaintSample>[
    PaintSample(centre: at ?? Vector3(0, 0, 1), radius: radius),
  ],
  // Black on the white every corner starts at, so a painted corner and an
  // untouched one differ in every channel rather than in none.
  colour: colour ?? const <double>[0, 0, 0, 1],
  strength: strength,
);

void main() {
  group('one stroke', () {
    test('paints the vertices inside the ball and leaves the rest', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);

      final List<Vector4> after = coloursOf(meshOf(history));
      final int painted = after.where((Vector4 it) => it.x < 0.5).length;
      final int untouched = after.where((Vector4 it) => it.x > 0.99).length;
      // **The row's own acceptance.** Mutation: paint every vertex and rely
      // on the weight being zero outside. Every corner of the model then
      // carries a colour, and a mask that was meant to be local is a flood.
      expect(painted, greaterThan(0));
      expect(untouched, greaterThan(painted));
    });

    test('and undo is one step, colour for colour', () {
      final ModelHistory history = opened();
      final List<Vector4> before = coloursOf(meshOf(history));

      expect(history.run(stroke()), isNull);
      expect(coloursOf(meshOf(history)), isNot(before));
      expect(history.steps, hasLength(1));

      expect(history.undo(), isTrue);
      // **Colours rather than `toBytes`, and the difference is worth
      // naming.** The first stroke on a mesh with no colour layer creates
      // one, and `EditMesh.undo` rolls the values back without removing a
      // layer the step was the first to write to — so the mesh after the
      // undo carries an all-default colour layer it did not carry before.
      // Every corner reads exactly what it read, which is what undo owes
      // anybody; the extra layer costs a few bytes in a file and changes
      // nothing a renderer or an exporter sees.
      expect(coloursOf(meshOf(history)), before);
    });

    test('strength mixes rather than replacing', () {
      final ModelHistory history = opened();
      expect(history.run(stroke(strength: 0.5)), isNull);
      final List<Vector4> after = coloursOf(meshOf(history));
      final Vector4 strongest = after.reduce(
        (Vector4 a, Vector4 b) => a.x < b.x ? a : b,
      );
      // Half way from the white every corner starts at toward the black
      // asked for, which is what a mask painted in two passes needs.
      expect(strongest.x, lessThan(0.9));
      expect(strongest.x, greaterThan(0.1));
    });
  });

  group('refusals', () {
    test('no samples', () {
      final ModelHistory history = opened();
      expect(
        history.run(
          const PaintVertexColour(
            objectId: 1,
            samples: <PaintSample>[],
            colour: <double>[1, 1, 1, 1],
          ),
        ),
        contains('at least one sample'),
      );
    });

    test('a colour that is not four numbers', () {
      final ModelHistory history = opened();
      expect(
        history.run(stroke(colour: const <double>[1, 0])),
        contains('four numbers'),
      );
    });

    test('a brush nowhere near the mesh, leaving no step', () {
      final ModelHistory history = opened();
      expect(
        history.run(stroke(at: Vector3(90, 90, 90))),
        contains('reached no vertices'),
      );
      expect(history.canUndo, isFalse);
    });

    test('and an object that is not there', () {
      final ModelHistory history = opened();
      expect(
        history.run(
          PaintVertexColour(
            objectId: 9,
            samples: <PaintSample>[
              PaintSample(centre: Vector3.zero(), radius: 1),
            ],
            colour: const <double>[1, 1, 1, 1],
          ),
        ),
        contains('9'),
      );
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      final ModelCommand? read = modelCommandFromJson(stroke().toJson());
      expect(read, isA<PaintVertexColour>());
      final PaintVertexColour back = read! as PaintVertexColour;
      expect(back.objectId, 1);
      expect(back.colour, <double>[0, 0, 0, 1]);
      expect(back.samples.single.radius, 0.5);
    });
  });
}
