/// `ModelWriter`: one list of writers, found by name or by suffix, each one
/// writing exactly what its own writer class writes.
///
///     dart test test/model_writer_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One triangle in the full layout, named by a node so glTF has a graph to
/// walk — the fixture `export_report_test.dart` round-trips clean.
PlainModelDocument _triangle() {
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
  return PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        name: 'a',
        mesh: builder.build(),
        transform: Matrix4.identity(),
      ),
    ],
    nodes: <ModelNode>[
      ModelNode(name: 'a', surfaces: <int>[0]),
    ],
  );
}

/// A format this package does not ship, the way an application adds one.
final class _Ply implements ModelWriter {
  const _Ply();

  @override
  String get name => 'ply';

  @override
  String get suffix => '.ply';

  @override
  String get says => 'a scanner\'s point cloud';

  @override
  ModelWrite write(ModelDocument document, {String baseName = 'model'}) =>
      ModelWrite(<WrittenFile>[
        WrittenFile('$baseName.ply', Uint8List.fromList('ply'.codeUnits)),
      ]);
}

void main() {
  group('finding a writer', () {
    test('every built-in writer answers to a name of its own', () {
      final names = <String>[
        for (final ModelWriter writer in builtInModelWriters)
          writer.name.toLowerCase(),
      ];
      expect(names.toSet(), hasLength(names.length));
    });

    test('by name first, so "stl" is the binary writer and "stlAscii" the '
        'text one', () {
      // Mutation: look the suffix up first. Both STL writers end in `.stl`,
      // and asking for the text one by name would hand back the binary one.
      expect(modelWriterNamed('stl')?.name, 'stl');
      expect(modelWriterNamed('stlAscii')?.name, 'stlAscii');
    });

    test('by suffix, with or without the dot, in any case', () {
      expect(modelWriterNamed('.GLB')?.name, 'glb');
      expect(modelWriterNamed('usdz')?.name, 'usdz');
    });

    test('a JSON .gltf is not among them', () {
      expect(modelWriterNamed('gltf'), isNull);
    });

    test('a writer an application adds is found through the same call', () {
      final writers = <ModelWriter>[...builtInModelWriters, const _Ply()];
      expect(modelWriterNamed('.PLY', writers: writers)?.name, 'ply');
      expect(modelWriterNamed('ply'), isNull);
    });
  });

  group('each built-in writer', () {
    test('writes the bytes its own writer class writes', () {
      // Mutation: build a writer with a different option than the class's
      // own default — `compressGeometry: true` for GLB, say. Every caller
      // that moved from the class to the list would change its output.
      final document = _triangle();
      expect(
        const F3dModelWriter().write(document).files.single.bytes,
        F3dWriter(document).write(),
      );
      expect(
        const GlbModelWriter().write(document).files.single.bytes,
        GltfWriter(document).writeGlb(),
      );
      expect(
        const StlModelWriter()
            .write(document, baseName: 'tri')
            .files
            .single
            .bytes,
        StlWriter(document, name: 'tri').write(),
      );
      expect(
        const StlModelWriter(
          ascii: true,
        ).write(document, baseName: 'tri').files.single.bytes,
        StlWriter(document, name: 'tri').writeAscii(),
      );
      expect(
        const UsdzModelWriter()
            .write(document, baseName: 'tri')
            .files
            .single
            .bytes,
        UsdzWriter(document, name: 'tri').write(),
      );
      final obj = const ObjModelWriter().write(document, baseName: 'tri');
      expect(obj.files.first.bytes, ObjWriter(document, name: 'tri').write());
    });

    test('names its first file from the base name and its own suffix', () {
      for (final ModelWriter writer in builtInModelWriters) {
        final written = writer.write(_triangle(), baseName: 'tri');
        expect(
          written.files.first.name,
          'tri${writer.suffix}',
          reason: writer.name,
        );
      }
    });

    test('a binary one this package reads back round-trips clean through '
        'exportChecked', () async {
      for (final CheckedModelWriter writer in <CheckedModelWriter>[
        const F3dModelWriter(),
        const GlbModelWriter(),
      ]) {
        final report = await exportChecked(_triangle(), writer);
        expect(report.differences, isEmpty, reason: writer.name);
      }
    });
  });
}
