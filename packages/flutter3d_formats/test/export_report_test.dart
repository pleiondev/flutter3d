/// `fmt-12`'s own row: `ExportReport {files, writerWarnings, differences}`
/// = write → read back → compare, over all four writers.
///
///     dart test test/export_report_test.dart
library;

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

MeshData _triangle() {
  final builder = MeshBuilder(
    VertexLayout.positionNormalTexcoord,
    reserveVertices: 3,
    reserveIndices: 3,
  );
  for (var i = 0; i < 3; i++) {
    builder.addVertex(
      position: Vector3(i.toDouble(), 0.0, 0.0),
      normal: Vector3(0.0, 0.0, 1.0),
      texcoord: Vector2(0.0, 0.0),
    );
  }
  builder.addTriangle(0, 1, 2);
  return builder.build();
}

ModelSurface _surface(String name, MeshData mesh) =>
    ModelSurface(name: name, mesh: mesh, transform: Matrix4.identity());

/// `GltfLoader` always reads a mesh back in [VertexLayout.standard] (or
/// [VertexLayout.skinned]) — generating tangents and a default vertex
/// colour when the file's own accessors did not carry them — so a source
/// mesh in a *narrower* layout always reads back wider, a "difference"
/// that is really just what glTF loading always does, not something this
/// row's own `exportToGlb` broke. This fixture carries the full layout
/// already, so the round trip has nothing to widen.
MeshData _fullTriangle() {
  final builder = MeshBuilder(
    VertexLayout.standard,
    reserveVertices: 3,
    reserveIndices: 3,
  );
  for (var i = 0; i < 3; i++) {
    builder.addVertex(
      position: Vector3(i.toDouble(), 0.0, 0.0),
      normal: Vector3(0.0, 0.0, 1.0),
      texcoord: Vector2(0.0, 0.0),
      tangent: Vector4(1.0, 0.0, 0.0, 1.0),
      color: Vector4(1.0, 1.0, 1.0, 1.0),
    );
  }
  builder.addTriangle(0, 1, 2);
  return builder.build();
}

void main() {
  group('exportToGlb', () {
    test('a plain surface round-trips with nothing to report', () async {
      // Unlike OBJ, STL and .f3d, glTF has a real node graph and
      // `GltfWriter` reads it, not `document.surfaces` directly —
      // `PlainModelDocument`'s own `nodes` defaults to empty rather than
      // falling back to `ModelDocument`'s "one node per surface", so this
      // fixture names one explicitly.
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface('a', _fullTriangle())],
        nodes: <ModelNode>[ModelNode(name: 'a', surfaces: <int>[0])],
      );
      final report = await exportToGlb(document);
      expect(report.files.keys, <String>['model.glb']);
      expect(report.writerWarnings, isEmpty);
      expect(report.differences, isEmpty);
      expect(report.isClean, isTrue);
    });
  });

  group('exportToObj', () {
    test('a plain surface has no warnings', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface('a', _triangle())],
      );
      final report = await exportToObj(document);
      expect(report.files.keys, <String>['model.obj']);
      expect(report.writerWarnings, isEmpty);
    });

    test(
      'a skinned document warns about the skin OBJ cannot carry — '
      "fmt-12's own literal example",
      () async {
        final document = PlainModelDocument(
          surfaces: <ModelSurface>[_surface('a', _triangle())],
          skins: <ModelSkin>[
            ModelSkin(
              joints: <int>[0],
              inverseBindMatrices: <Matrix4>[Matrix4.identity()],
              name: 'rig',
            ),
          ],
        );
        final report = await exportToObj(document);
        expect(
          report.writerWarnings,
          contains(predicate<String>((w) => w.contains('skin'))),
        );
      },
    );

    test('a document naming a material writes the .mtl file too', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(
            name: 'a',
            mesh: _triangle(),
            transform: Matrix4.identity(),
            materialIndex: 0,
          ),
        ],
        materials: <SurfaceMaterial>[SurfaceMaterial(name: 'red')],
      );
      final report = await exportToObj(document);
      expect(report.files.keys, <String>['model.obj', 'model.mtl']);
    });
  });

  group('exportToStl', () {
    test('a single surface has no warnings', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface('a', _triangle())],
      );
      final report = await exportToStl(document);
      expect(report.writerWarnings, isEmpty);
    });

    test('two surfaces warn about the merge STL cannot avoid', () async {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          _surface('a', _triangle()),
          _surface('b', _triangle()),
        ],
      );
      final report = await exportToStl(document);
      expect(
        report.writerWarnings,
        contains(predicate<String>((w) => w.contains('merged'))),
      );
      // The round trip's own honest difference: STL really did come back
      // as one surface, not two — this is what the warning above explains,
      // not a bug `differences` is hiding.
      expect(
        report.differences,
        contains(
          predicate<DocumentDifference>((d) => d.said.contains('surfaces')),
        ),
      );
    });
  });

  group('exportToF3d', () {
    test('a plain surface round-trips with nothing to report', () {
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[_surface('a', _triangle())],
      );
      final report = exportToF3d(document);
      expect(report.files.keys, <String>['model.f3d']);
      expect(report.writerWarnings, isEmpty);
      expect(report.differences, isEmpty);
    });
  });
}
