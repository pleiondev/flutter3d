/// The check that says whether a writer works.
///
///     dart test test/document_compare_test.dart
///
/// **Every test here breaks something on purpose and asks whether it was
/// noticed.** That is the only way to test a comparison: one that always
/// answered "no differences" would pass a suite built out of documents that are
/// genuinely equal, and would then sign off every broken writer in the
/// repository. So the pairs below differ by exactly one thing each, and the
/// assertion is that the one thing is what comes back.
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

MeshData triangle({
  double x = 0.0,
  VertexLayout layout = VertexLayout.positionNormalTexcoord,
}) {
  final builder = MeshBuilder(layout, reserveVertices: 3, reserveIndices: 3);
  for (var i = 0; i < 3; i++) {
    builder.addVertex(
      position: Vector3(x + i.toDouble(), 0.0, 0.0),
      normal: Vector3(0.0, 0.0, 1.0),
      texcoord: Vector2(0.0, 0.0),
    );
  }
  builder.addTriangle(0, 1, 2);
  return builder.build();
}

ModelDocument docOf(
  MeshData mesh, {
  int materials = 0,
  int images = 0,
  int nodes = 0,
  int animations = 0,
}) => PlainModelDocument(
  surfaces: <ModelSurface>[
    ModelSurface(name: 'a', mesh: mesh, transform: Matrix4.identity()),
  ],
  materials: <SurfaceMaterial>[
    for (var i = 0; i < materials; i++) SurfaceMaterial(name: 'm$i'),
  ],
  images: <EncodedImage>[
    for (var i = 0; i < images; i++)
      EncodedImage(bytes: Uint8List.fromList(<int>[1]), name: 'i$i'),
  ],
  nodes: <ModelNode>[
    for (var i = 0; i < nodes; i++)
      ModelNode(
        name: 'n$i',
        translation: Vector3.zero(),
        rotation: Quaternion.identity(),
        scale: Vector3(1, 1, 1),
        children: const <int>[],
        surfaces: const <int>[],
      ),
  ],
  animations: <AnimationClip>[
    for (var i = 0; i < animations; i++)
      AnimationClip(name: 'clip $i', tracks: const <AnimationTrack>[]),
  ],
);

/// [mesh] with one vertex float moved by [by].
MeshData nudged(MeshData mesh, double by, {int at = 0}) {
  final floats = Float32List.fromList(mesh.vertices);
  floats[at] += by;
  return MeshData(
    layout: mesh.layout,
    vertices: floats,
    indices: Uint32List.fromList(mesh.indices),
  );
}

void main() {
  test('a document compared with itself has nothing to report', () {
    // The one case that has to be quiet. Mutation: report anything at all here
    // and every conversion in the repository starts failing, which is the
    // failure mode a comparison is least likely to be trusted through.
    expect(
      compareModelDocuments(docOf(triangle()), docOf(triangle())),
      isEmpty,
    );
  });

  group('what a lost thing looks like', () {
    test('a dropped surface is named with both counts', () {
      final source = docOf(triangle());
      final readBack = PlainModelDocument(surfaces: const <ModelSurface>[]);

      final found = compareModelDocuments(source, readBack);

      expect(found, hasLength(1));
      expect(found.single.said, contains('surfaces: 1 in, 0 out'));
    });

    test('materials, images, nodes and animations each get their own line', () {
      final source = docOf(
        triangle(),
        materials: 2,
        images: 1,
        nodes: 3,
        animations: 1,
      );
      final readBack = docOf(triangle());

      final found = compareModelDocuments(source, readBack);

      // Mutation: check only the surfaces, which is the count a converter is
      // least likely to get wrong. A writer that drops every material and every
      // image then passes, and the model comes back untextured and signed off.
      expect(found.map((DocumentDifference d) => d.said).join('\n'), '''
materials: 2 in, 0 out
images: 1 in, 0 out
nodes: 3 in, 0 out
animations: 1 in, 0 out''');
    });

    test('nothing is said about geometry once the counts disagree', () {
      final source = docOf(triangle(), materials: 1);
      final readBack = docOf(nudged(triangle(), 5.0));

      // Both halves are wrong, and only the counts are reported. Pairing
      // surfaces by index across documents that hold different numbers of
      // things names surfaces that are not each other — so a file that lost one
      // surface of forty would report the other thirty-nine as changed too, and
      // the one real fault would be the fortieth line.
      expect(compareModelDocuments(source, readBack), hasLength(1));
    });
  });

  group('what a mangled thing looks like', () {
    test('a changed layout is reported and the buffers are not read', () {
      final source = docOf(triangle());
      final readBack = docOf(triangle(layout: VertexLayout.positionNormal));

      final found = compareModelDocuments(source, readBack);

      // One line, not one per vertex: buffers written against different layouts
      // are not comparable float by float, and reading them as though they were
      // would report every number in the file.
      expect(found, hasLength(1));
      expect(found.single.said, contains('layout'));
    });

    test('a moved vertex is reported with both numbers', () {
      final source = docOf(triangle());
      final readBack = docOf(nudged(triangle(), 0.5));

      final found = compareModelDocuments(source, readBack);

      // Mutation: compare `vertexCount` instead of the floats. The counts match
      // — the same number of vertices arrived — and every one of them is
      // somewhere else, which is exactly what an endianness slip produces.
      expect(found, hasLength(1));
      expect(found.single.said, contains('vertex float 0'));
      expect(found.single.said, contains('0.5'));
    });

    test('a shuffled index is reported', () {
      final source = docOf(triangle());
      final flipped = triangle();
      final readBack = docOf(
        MeshData(
          layout: flipped.layout,
          vertices: Float32List.fromList(flipped.vertices),
          indices: Uint32List.fromList(<int>[0, 2, 1]),
        ),
      );

      final found = compareModelDocuments(source, readBack);

      // The same three vertices wound the other way: the file parses, draws,
      // and is inside out under backface culling. Nothing about the vertex
      // buffer says so.
      expect(found, hasLength(1));
      expect(found.single.said, contains('index 1'));
    });

    test('one surface is reported once, however many floats moved', () {
      final source = docOf(triangle());
      final all = triangle();
      final readBack = docOf(
        MeshData(
          layout: all.layout,
          vertices: Float32List.fromList(<double>[
            for (final double v in all.vertices) v + 1.0,
          ]),
          indices: Uint32List.fromList(all.indices),
        ),
      );

      // Mutation: drop the `break` and report every float. A surface of forty
      // thousand vertices produces forty thousand identical lines, and the
      // second surface that is wrong for a different reason is somewhere below
      // them.
      expect(compareModelDocuments(source, readBack), hasLength(1));
    });
  });

  group('tolerance', () {
    test('a rounded vertex passes when the writer was allowed to round', () {
      final source = docOf(triangle());
      final readBack = docOf(nudged(triangle(), 0.0004));

      // What OBJ needs: it writes decimal text to a fixed number of digits, so
      // held to the bytes every vertex in every export would be reported.
      expect(compareModelDocuments(source, readBack, tolerance: 1e-3), isEmpty);
    });

    test('a real move still fails a generous tolerance', () {
      final source = docOf(triangle());
      final readBack = docOf(nudged(triangle(), 0.5));

      // Mutation: let the tolerance answer "same" for everything — return an
      // empty list whenever one was passed — and the check becomes a check that
      // the writer produced a file, which it already knew.
      expect(
        compareModelDocuments(source, readBack, tolerance: 1e-3),
        hasLength(1),
      );
    });

    test('a NaN is a difference and not a match', () {
      final source = docOf(triangle());
      final broken = triangle();
      final readBack = docOf(
        MeshData(
          layout: broken.layout,
          vertices: Float32List.fromList(broken.vertices)..[0] = double.nan,
          indices: Uint32List.fromList(broken.indices),
        ),
      );

      // A NaN loses every comparison it is in, so `difference > tolerance` is
      // false for one and the vertex passes. Mutation: write it that way round
      // and a file whose positions have become arithmetic nothing — the shape
      // that disappears on some drivers and takes the draw call with it — is
      // signed off as a clean round trip.
      expect(compareModelDocuments(source, readBack), hasLength(1));
      expect(
        compareModelDocuments(source, readBack, tolerance: 1e9),
        hasLength(1),
      );
    });
  });
}
