/// Taking the document out, and reading it back with somebody else's reader.
///
///     flutter test test/exporting_test.dart
///
/// **The round trip is the test and the rest are its corners.** A writer that
/// dropped a surface, mangled a float or wound a face the other way produces a
/// file that still parses; asserting on the bytes proves only that the bytes are
/// well formed. Reading it back with `ObjLoader` and comparing through
/// `compareModelDocuments` puts both halves in the same sentence.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/exporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A cube and a lathed vase: an edited mesh and a shape that still knows its
/// parameters, which are the two geometries an export has to build differently.
ModelProject workshop() => const ModelProject()
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.translationValues(2, 0, 0),
      ),
    )
    .added(
      (int id) => ModelObject(
        id: id,
        name: 'vase',
        geometry: ParametricGeometry(const ParametricCylinder(segments: 12)),
        transform: Matrix4.identity(),
      ),
    );

/// A project holding one object with no faces at all, which readiness calls an
/// error: some loaders refuse an empty mesh and the rest draw nothing.
ModelProject withEmptyObject() => workshop().added(
  (int id) => ModelObject(
    id: id,
    name: 'ghost',
    geometry: EditedGeometry(EditMesh.empty()),
    transform: Matrix4.identity(),
  ),
);

ExportWritten written(ExportResult result) {
  expect(result, isA<ExportWritten>(), reason: '$result');
  return result as ExportWritten;
}

/// [files] read back by the loader that reads OBJ, with the `.mtl` handed over
/// as the sibling it asks for.
Future<ModelDocument> readBack(List<ExportFile> files) {
  final byName = <String, Uint8List>{
    for (final ExportFile file in files) file.name: file.bytes,
  };
  return ObjLoader().load(
    files.first.bytes,
    resolveUri: (AssetRequest request) async {
      final found = byName[request.uri];
      if (found == null) {
        fail('the .obj asked for "${request.uri}" and it was not written');
      }
      return found;
    },
  );
}

void main() {
  group('OBJ, out and back', () {
    test('the shape comes back where it was and the size it was', () async {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;

      final source = toModelDocument(project);
      final back = await readBack(files);

      // **Not `compareModelDocuments` with zero differences, and the reason is
      // worth writing down.** That check is for a format that promises the same
      // buffers back; OBJ promises the same *shape* and changes the buffers on
      // purpose, twice. It has no node tree, so `ObjWriter` bakes each surface's
      // world matrix into its vertices — the cube at x=2 goes out at 1.5 rather
      // than −0.5. And it addresses positions, texcoords and normals as three
      // independent streams, so the writer deduplicates and the loader rebuilds:
      // the cylinder's 78 vertices come back as 76 with the same 288 indices.
      // Both are lossless in shape and neither is expressible as a tolerance.
      //
      // What OBJ does promise is the world-space geometry, so that is what is
      // asserted: the bounds a game engine would frame a camera on.
      final a = source.computeBounds();
      final b = back.computeBounds();
      expect(b.min.x, closeTo(a.min.x, 1e-4));
      expect(b.min.y, closeTo(a.min.y, 1e-4));
      expect(b.min.z, closeTo(a.min.z, 1e-4));
      expect(b.max.x, closeTo(a.max.x, 1e-4));
      expect(b.max.y, closeTo(a.max.y, 1e-4));
      expect(b.max.z, closeTo(a.max.z, 1e-4));

      // Mutation: drop the bake and write local vertices. Every surface comes
      // back at the origin, the bounds collapse to one object's box, and a
      // model of forty props opens as forty props in the same place.
      expect(a.max.x, greaterThan(2.0), reason: 'the cube is placed at x=2');
    });

    test('the triangles and the surfaces both survive', () async {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;

      final back = await readBack(files);

      // Against the project rather than a written-down number, so that changing
      // the fixture cannot leave this passing about the wrong shape.
      expect(back.triangleCount, project.triangleCount);
      expect(back.surfaces, hasLength(project.objects.length));
    });

    test('a lathed vase comes out as triangles, and that is the point', () {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.obj),
      ).files;
      final text = utf8.decode(files.first.bytes);

      // A cylinder of twelve segments is built on the way out —
      // `ParametricShape.drawn` — so it exports as well as any mesh does.
      // Mutation: have the converter answer an empty mesh for a parametric
      // shape and the vase leaves the file entirely, silently.
      expect(text, contains('o vase'));
      expect(text, contains('o cube'));
    });

    test('the material library is written and the obj names it', () {
      final painted = ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(
              name: 'brass',
              baseColor: Vector4(0.8, 0.6, 0.2, 1),
            ),
          ),
        ],
      ).added(
        (int id) => ModelObject(
          id: id,
          name: 'bolt',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
          materialSlots: const <int>[0],
        ),
      );

      final files = written(
        planExport(painted, format: ExportFormat.obj, name: 'thing'),
      ).files;

      // Two files, and the first names the second. Mutation: write only the
      // `.obj` and the `mtllib` line points at a file nobody saved, so the
      // model opens grey wherever it is taken.
      expect(files, hasLength(2));
      expect(files[0].name, 'thing.obj');
      expect(files[1].name, 'thing.mtl');
      expect(utf8.decode(files[0].bytes), contains('mtllib thing.mtl'));
      expect(utf8.decode(files[1].bytes), contains('brass'));
    });
  });

  group('the engine container', () {
    test('a project exports and reads back as the same geometry', () {
      final project = workshop();
      final files = written(
        planExport(project, format: ExportFormat.f3d),
      ).files;

      expect(files, hasLength(1));
      expect(files.single.name, 'model.f3d');

      final back = F3dDocument.parse(files.single.bytes);

      // `.f3d` is binary and holds the floats exactly, so this one is held to
      // the bytes rather than to a tolerance — which is the difference the
      // parameter exists to express.
      expect(
        compareModelDocuments(toModelDocument(project), back),
        isEmpty,
      );
      expect(back.nodes, hasLength(project.objects.length));
    });
  });

  group('what stops an export', () {
    test('an empty project is refused, not written empty', () {
      final result = planExport(
        const ModelProject(),
        format: ExportFormat.obj,
      );

      // `ObjWriter` writes an empty file on purpose and says why — a format has
      // to be able to represent nothing. A person pressing Export on an empty
      // document has made a mistake, and that is a different question.
      expect(result, isA<ExportRefused>());
      expect((result as ExportRefused).because, contains('nothing in this'));
    });

    test('an object with no faces blocks, and says how many', () {
      final result = planExport(
        withEmptyObject(),
        format: ExportFormat.obj,
      );

      // Mutation: let errors through as warnings. The file is written with an
      // empty mesh in it, which some loaders refuse outright and the rest draw
      // as nothing — and nobody was asked.
      expect(result, isA<ExportBlocked>());
      final blocked = result as ExportBlocked;
      expect(blocked.issues, hasLength(1));
      expect(blocked.issues.single.object?.name, 'ghost');
      expect(blocked.says, contains('One thing'));
    });

    test('force writes it anyway and still says what is wrong', () {
      final result = planExport(
        withEmptyObject(),
        format: ExportFormat.obj,
        force: true,
      );

      // "I know" is an answer to a question, not a reason to stop asking:
      // the warnings ride along with the bytes. Mutation: drop them when forced
      // and the export goes quiet exactly when it has most to say.
      final ok = written(result);
      expect(ok.files, isNotEmpty);
      expect(ok.warnings.any((String w) => w.contains('ghost')), isTrue);
    });

    test('a warning does not block, and comes back with the bytes', () {
      // A quad is a warning: the writer cuts it, so the file loads, and it may
      // not cut it the way somebody would have.
      final quads = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'box',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );

      final ok = written(planExport(quads, format: ExportFormat.obj));

      expect(ok.files, isNotEmpty);
      expect(
        ok.warnings.any((String w) => w.contains('three sides')),
        isTrue,
        reason: 'the cuboid is six quads',
      );
    });

    test('a flattened hierarchy is said out loud for OBJ and not for f3d', () {
      final rigged = workshop();
      final child = rigged.objects.last;
      final withParent = rigged.withObject(
        child.copyWith(parent: rigged.objects.first.id),
      );

      final obj = written(planExport(withParent, format: ExportFormat.obj));
      final f3d = written(planExport(withParent, format: ExportFormat.f3d));

      // OBJ has no node tree at all, so a rig comes back as one level. `.f3d`
      // keeps it. Mutation: warn for both and the sentence stops meaning
      // anything, because it is not true of the container.
      expect(obj.warnings.any((String w) => w.contains('no node tree')), isTrue);
      expect(f3d.warnings.any((String w) => w.contains('no node tree')), isFalse);
    });
  });
}
