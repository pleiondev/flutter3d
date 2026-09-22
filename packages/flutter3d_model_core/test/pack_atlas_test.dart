/// `PackAtlas` — `pro-uv-08n`: one texture across several objects.
///
///     dart test test/pack_atlas_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A quad whose UVs fill the whole unit square — what an object looks like
/// before it shares one with anybody.
EditMesh sheet({bool withUv = true}) {
  final builder = EditMeshBuilder();
  builder
    ..addVertex(Vector3(0, 0, 0))
    ..addVertex(Vector3(1, 0, 0))
    ..addVertex(Vector3(1, 1, 0))
    ..addVertex(Vector3(0, 1, 0));
  final int face = builder.addFace(<int>[0, 1, 2, 3]);
  final EditMesh mesh = builder.build();
  if (withUv) {
    mesh.beginStep();
    mesh.forEachHalfEdge(face, (int he) {
      final Vector3 at = mesh.positionOf(mesh.originOf(he));
      mesh.setUv(he, Vector2(at.x, at.y));
    });
    mesh.endStep();
  }
  mesh.clearJournal();
  return mesh;
}

ModelHistory opened({int objects = 3, bool lastWithoutUv = false}) {
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      for (var i = 0; i < objects; i++)
        ModelObject(
          id: i + 1,
          name: 'prop$i',
          geometry: EditedGeometry(
            sheet(withUv: !(lastWithoutUv && i == objects - 1)),
          ),
          transform: Matrix4.identity(),
          materialSlots: <int>[i],
        ),
    ],
    materials: <ProjectMaterial>[
      for (var i = 0; i < objects; i++)
        ProjectMaterial(surface: SurfaceMaterial(name: 'm$i')),
    ],
    nextId: objects + 1,
  );
  return ModelHistory(project);
}

EditMesh meshOf(ModelHistory history, int id) =>
    (history.project[id]!.geometry as EditedGeometry).mesh;

/// Every corner UV of [mesh].
List<Vector2> uvsOf(EditMesh mesh) {
  final out = <Vector2>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) => out.add(mesh.uvOf(half)));
  }
  return out;
}

void main() {
  group('three props', () {
    test('each land in a cell of their own, inside the square', () {
      final ModelHistory history = opened();
      expect(history.run(const PackAtlas(objectIds: <int>[1, 2, 3])), isNull);

      final boxes = <int, (Vector2, Vector2)>{};
      for (final int id in <int>[1, 2, 3]) {
        final List<Vector2> uvs = uvsOf(meshOf(history, id));
        final Vector2 min = Vector2.all(double.infinity);
        final Vector2 max = Vector2.all(double.negativeInfinity);
        for (final Vector2 uv in uvs) {
          Vector2.min(min, uv, min);
          Vector2.max(max, uv, max);
          // Everything is inside the square, which is what makes it one
          // texture rather than three overlapping ones.
          expect(uv.x, inInclusiveRange(-1e-6, 1 + 1e-6));
          expect(uv.y, inInclusiveRange(-1e-6, 1 + 1e-6));
        }
        boxes[id] = (min, max);
      }

      // **No two cells overlap.** Mutation: scale every object into the whole
      // square instead of into a cell. Every prop then samples every other
      // prop's texels, which is the one thing an atlas must not do.
      for (final List<int> pair in <List<int>>[
        <int>[1, 2],
        <int>[1, 3],
        <int>[2, 3],
      ]) {
        final (Vector2 aMin, Vector2 aMax) = boxes[pair[0]]!;
        final (Vector2 bMin, Vector2 bMax) = boxes[pair[1]]!;
        final bool apart =
            aMax.x <= bMin.x + 1e-9 ||
            bMax.x <= aMin.x + 1e-9 ||
            aMax.y <= bMin.y + 1e-9 ||
            bMax.y <= aMin.y + 1e-9;
        expect(
          apart,
          isTrue,
          reason: 'cells ${pair[0]} and ${pair[1]} overlap',
        );
      }
    });

    test('and all three point at one material', () {
      final ModelHistory history = opened();
      expect(history.run(const PackAtlas(objectIds: <int>[1, 2, 3])), isNull);
      // **Nine props with one texture is one draw call instead of nine**, and
      // an atlas whose objects still named nine materials would be all of
      // the packing and none of the gain.
      for (final int id in <int>[1, 2, 3]) {
        expect(history.project[id]!.materialSlots, <int>[0]);
      }
      // The materials nobody draws with are left in the project: deleting one
      // out from under something that names it by index is a document that
      // no longer opens.
      expect(history.project.materials, hasLength(3));
    });

    test('an object keeps the shape of its own layout, smaller', () {
      final ModelHistory history = opened();
      final List<Vector2> before = uvsOf(meshOf(history, 2));
      expect(history.run(const PackAtlas(objectIds: <int>[1, 2, 3])), isNull);
      final List<Vector2> after = uvsOf(meshOf(history, 2));

      // The square stays a square: every corner moved by the same scale and
      // the same offset, so a face somebody laid out carefully is still laid
      // out that way.
      final double scaleX =
          (after[1].x - after[0].x) / (before[1].x - before[0].x);
      for (var i = 1; i < before.length; i++) {
        final double dx = before[i].x - before[0].x;
        expect(after[i].x - after[0].x, closeTo(dx * scaleX, 1e-5));
      }
      expect(scaleX, lessThan(1));
    });

    test('and undo puts every UV back', () {
      final ModelHistory history = opened();
      final List<Vector2> before = uvsOf(meshOf(history, 1));
      expect(history.run(const PackAtlas(objectIds: <int>[1, 2, 3])), isNull);
      expect(history.undo(), isTrue);
      expect(uvsOf(meshOf(history, 1)), before);
      expect(history.project[2]!.materialSlots, <int>[1]);
    });
  });

  group('refusals', () {
    test('one object is not a share', () {
      final ModelHistory history = opened();
      expect(
        history.run(const PackAtlas(objectIds: <int>[1])),
        contains('not a share'),
      );
    });

    test('an object with no UVs, saying to unwrap it', () {
      final ModelHistory history = opened(lastWithoutUv: true);
      expect(
        history.run(const PackAtlas(objectIds: <int>[1, 2, 3])),
        contains('unwrap'),
      );
    });

    test('an object that is not there', () {
      final ModelHistory history = opened();
      expect(
        history.run(const PackAtlas(objectIds: <int>[1, 99])),
        contains('99'),
      );
    });

    test('and a margin that is not a fraction of a side', () {
      final ModelHistory history = opened();
      expect(
        history.run(const PackAtlas(objectIds: <int>[1, 2], margin: 0.9)),
        contains('not a fraction'),
      );
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      final ModelCommand? read = modelCommandFromJson(
        const PackAtlas(objectIds: <int>[1, 2, 3], margin: 0.02).toJson(),
      );
      expect(read, isA<PackAtlas>());
      final PackAtlas back = read! as PackAtlas;
      expect(back.objectIds, <int>[1, 2, 3]);
      expect(back.margin, 0.02);
    });
  });
}
