/// An object's levels of detail, in the file it is exported to.
///
///     dart test test/lod_export_test.dart
///
/// **They were in the project and nowhere else.** `AddLod`, `SetLodRatio` and
/// `RegenerateLods` edit `ModelObject.lods`, a cache turns each into a mesh and
/// a screen shows them, and the converter to a `ModelDocument` never read the
/// field. `.f3d` has a section for levels and `.glb` writes `MSFT_lod`, and
/// both wrote nothing, because nothing reached them: the only models the
/// engine drew with a `LodGroup` had been made by some other tool.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const List<LodSpec> _twoLevels = <LodSpec>[
  LodSpec(ratio: 0.5, maxScreenFraction: 0.4),
  LodSpec(ratio: 0.2, maxScreenFraction: 0.1),
];

/// A sphere, because a level is a simplification and a cube has nothing to
/// take away.
ModelProject _sphere({
  List<LodSpec> lods = _twoLevels,
  List<ModifierSlot> modifiers = const <ModifierSlot>[],
}) => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'ball',
    geometry: EditedGeometry(
      const ParametricSphere(segments: 24, rings: 12).toEditMesh(),
    ),
    transform: Matrix4.translation(Vector3(1.0, 2.0, 3.0)),
    lods: lods,
    modifiers: modifiers,
  ),
);

Uint8List _written(ModelProject project, ExportFormat format) {
  final result = planExport(project, format: format, force: true);
  return (result as ExportWritten).files.first.bytes;
}

void main() {
  group('in the document', () {
    test('a level is a surface its node names and no node draws', () {
      final document = toModelDocument(_sphere(), withLods: true);
      final node = document.nodes.single;

      expect(document.surfaces, hasLength(3));
      expect(node.surfaces, <int>[0]);
      expect(
        <List<int>>[for (final lod in node.lods) lod.surfaceIndices],
        <List<int>>[
          <int>[1],
          <int>[2],
        ],
      );
      expect(
        <double>[for (final lod in node.lods) lod.maxScreenFraction],
        <double>[0.4, 0.1],
      );
    });

    test('each is in the layout of the mesh it was cut from', () {
      // Mutation: hand the simplifier's own answer over as it comes. It
      // carries position, normal and UV and nothing else, eight floats a
      // vertex, and the renderer's vertex stage reads a tangent past the end
      // of it (`RangeError` on the software backend).
      final document = toModelDocument(_sphere(), withLods: true);
      final base = document.surfaces[0].mesh;

      for (final surface in document.surfaces.skip(1)) {
        expect(
          surface.mesh.layout.floatsPerVertex,
          base.layout.floatsPerVertex,
        );
        expect(
          surface.mesh.vertices.length,
          surface.mesh.vertexCount * base.layout.floatsPerVertex,
        );
      }
    });

    test('each is coarser than the one before, by about what was asked', () {
      final document = toModelDocument(_sphere(), withLods: true);
      final full = document.surfaces[0].mesh.triangleCount;
      final half = document.surfaces[1].mesh.triangleCount;
      final fifth = document.surfaces[2].mesh.triangleCount;

      expect(half, lessThan(full));
      expect(fifth, lessThan(half));
      expect(half / full, closeTo(0.5, 0.1));
      expect(fifth / full, closeTo(0.2, 0.1));
    });

    test('and stands where the object stands, painted as it is painted', () {
      final document = toModelDocument(_sphere(), withLods: true);
      final base = document.surfaces.first;

      for (final level in document.surfaces.skip(1)) {
        expect(level.transform, base.transform);
        expect(level.materialIndex, base.materialIndex);
        expect(level.skinIndex, base.skinIndex);
        expect(level.flipWinding, base.flipWinding);
      }
    });

    test('nobody who did not ask gets one', () {
      // The default, because a writer that knows nothing of levels walks
      // every surface and would put all three balls in the same place.
      final document = toModelDocument(_sphere());

      expect(document.surfaces, hasLength(1));
      expect(document.nodes.single.lods, isEmpty);
    });

    test(
      'a level is cut from the mesh the file carries, modifiers and all',
      () {
        // Two balls side by side. A level cut from the raw geometry would be
        // one ball, and the far view of the pair would lose half of it.
        final pair = _sphere(
          lods: const <LodSpec>[LodSpec(ratio: 0.5, maxScreenFraction: 0.4)],
          modifiers: <ModifierSlot>[
            ModifierSlot(
              modifier: ArrayModifier(count: 2, offset: Vector3(3.0, 0.0, 0.0)),
              enabled: true,
              inExport: true,
            ),
          ],
        );
        final document = toModelDocument(pair, withLods: true);
        final level = document.surfaces[1].mesh;

        expect(level.computeBounds().max.x, greaterThan(2.0));
      },
    );

    test('asking twice of an unchanged project simplifies nothing twice', () {
      final project = _sphere();
      final converter = ProjectModelDocument();
      final first = converter.of(project, withLods: true).surfaces[1].mesh;
      final second = converter.of(project, withLods: true).surfaces[1].mesh;

      expect(second, same(first));
    });
  });

  group('in the file', () {
    test('.f3d carries them and gives them back', () {
      final read = F3dDocument.parse(_written(_sphere(), ExportFormat.f3d));
      final node = read.nodes.singleWhere((n) => n.lods.isNotEmpty);

      expect(node.lods, hasLength(2));
      expect(node.lods.first.maxScreenFraction, closeTo(0.4, 1e-6));
      expect(
        read.surfaces[node.lods.last.surfaceIndices.single].mesh.triangleCount,
        lessThan(read.surfaces[node.surfaces.single].mesh.triangleCount),
      );
    });

    test('.glb carries them and gives them back', () async {
      final read = await GltfLoader().load(
        _written(_sphere(), ExportFormat.glb),
      );
      final node = read.nodes.singleWhere((n) => n.lods.isNotEmpty);

      expect(node.lods, hasLength(2));
      expect(
        read.surfaces[node.lods.last.surfaceIndices.single].mesh.triangleCount,
        lessThan(read.surfaces[node.surfaces.single].mesh.triangleCount),
      );
    });

    test('a format with no word for a level writes the one mesh', () async {
      final full = toModelDocument(_sphere()).surfaces.single.mesh;
      final read = await ObjLoader().load(
        _written(_sphere(), ExportFormat.obj),
      );

      expect(
        read.surfaces.fold<int>(0, (sum, s) => sum + s.mesh.triangleCount),
        full.triangleCount,
      );
    });

    test('every format says which it is', () {
      expect(
        <ExportFormat>[
          for (final format in ExportFormat.values)
            if (format.carriesLods) format,
        ],
        <ExportFormat>[ExportFormat.f3d, ExportFormat.glb],
      );
    });
  });
}
