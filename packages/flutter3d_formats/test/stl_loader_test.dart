/// `StlLoader`: binary and ASCII, against the five fixtures
/// `tool/build_stl.dart` writes.
///
///     dart test test/stl_loader_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/stl/$name').readAsBytesSync();

void main() {
  group('isBinaryStl', () {
    test('a real binary file matches its own header count', () {
      expect(isBinaryStl(_fixture('tetrahedron.stl')), isTrue);
    });

    test('an ASCII file does not, even one that starts with "solid"', () {
      // Mutation: check only the leading bytes for 'solid' and call that
      // binary. Every ASCII fixture here starts with exactly that word.
      expect(isBinaryStl(_fixture('tetrahedron_ascii.stl')), isFalse);
    });

    test('fewer than 84 bytes is never binary', () {
      expect(isBinaryStl(Uint8List(83)), isFalse);
    });
  });

  group('sniffModelFormat', () {
    test('a binary STL sniffs as stl', () {
      expect(sniffModelFormat(_fixture('tetrahedron.stl')), ModelFormat.stl);
    });

    test('an ASCII STL sniffs as stl, not obj', () {
      // Mutation: drop the `looksLikeAsciiStl` check and let this fall
      // through to the OBJ default, which is exactly what the format shares
      // a "plain text" shape with.
      expect(
        sniffModelFormat(_fixture('tetrahedron_ascii.stl')),
        ModelFormat.stl,
      );
    });

    test('an OBJ file still sniffs as obj', () {
      expect(
        sniffModelFormat(Uint8List.fromList('v 0 0 0\n'.codeUnits)),
        ModelFormat.obj,
      );
    });
  });

  group('binary decode', () {
    test('a tetrahedron decodes to 4 triangles, 12 vertices', () async {
      final document = await StlLoader().load(_fixture('tetrahedron.stl'));
      final mesh = document.surfaces.single.mesh;
      expect(mesh.triangleCount, 4);
      expect(mesh.vertexCount, 12);
    });

    test('a cube decodes to 12 triangles', () async {
      final document = await StlLoader().load(_fixture('cube.stl'));
      expect(document.surfaces.single.mesh.triangleCount, 12);
    });

    test('sendable: decodes from a plain dart test, no Flutter SDK', () async {
      // The point of this whole file running under `dart test` rather than
      // `flutter test` — see `decode_without_flutter_test.dart` for the
      // package-wide version of this claim.
      final document = await StlLoader().load(_fixture('tetrahedron.stl'));
      expect(document.surfaces, isNotEmpty);
    });
  });

  group('the two dialects agree', () {
    test(
      'the same tetrahedron decodes to the same geometry either way',
      () async {
        final binary = await StlLoader().load(_fixture('tetrahedron.stl'));
        final ascii = await StlLoader().load(_fixture('tetrahedron_ascii.stl'));
        final problems = compareModelDocuments(
          binary,
          ascii,
          // Text keeps only as many digits as `writeln` gives a double;
          // binary keeps the exact float32. Loose enough to not be the
          // point of this test, tight enough that a wrong axis or a
          // transposed vertex still fails it.
          tolerance: 1e-4,
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      },
    );
  });

  group('degenerate normals', () {
    test('fromFile recomputes only the zero ones, and says so', () async {
      final document = await StlLoader(
        normals: StlNormals.fromFile,
      ).load(_fixture('degenerate_normals.stl'));
      final mesh = document.surfaces.single.mesh;
      final offset = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
      final stride = mesh.layout.floatsPerVertex;

      // Facets 0 and 2 had a zeroed normal record; every one of the four
      // facets' first vertex is where each facet's normal lives, one per
      // triangle (3 vertices apart).
      for (var facet = 0; facet < 4; facet++) {
        final base = facet * 3 * stride + offset;
        final nx = mesh.vertices[base];
        final ny = mesh.vertices[base + 1];
        final nz = mesh.vertices[base + 2];
        final length = nx * nx + ny * ny + nz * nz;
        // Mutation: leave a degenerate normal as the zero vector instead of
        // recomputing it. Every facet's normal must be unit length once
        // decoded, recomputed or not.
        expect(length, closeTo(1.0, 1e-4), reason: 'facet $facet');
      }
      expect(
        document.warnings,
        contains(contains('2 facet(s) had a zero-length normal')),
      );
    });

    test(
      'recomputed ignores the file even where it was not degenerate',
      () async {
        final trusting = await StlLoader(
          normals: StlNormals.fromFile,
        ).load(_fixture('tetrahedron.stl'));
        final recomputed = await StlLoader(
          normals: StlNormals.recomputed,
        ).load(_fixture('tetrahedron.stl'));
        // Every normal in this fixture is already the true face normal, so
        // recomputing changes nothing — the two modes agree when the file was
        // honest, which is what makes `recomputed` a safe default to reach for.
        final problems = compareModelDocuments(trusting, recomputed);
        expect(problems, isEmpty);
      },
    );
  });

  group('ASCII grammar tolerance', () {
    test('uppercase keywords and an unnamed solid both parse', () async {
      final document = await StlLoader().load(
        _fixture('single_triangle_shouting.stl'),
      );
      final mesh = document.surfaces.single.mesh;
      expect(mesh.triangleCount, 1);
      expect(mesh.vertexCount, 3);
    });
  });

  group('authoredAttributes', () {
    test('position and normal, never texcoord/tangent/color', () async {
      final document = await StlLoader().load(_fixture('tetrahedron.stl'));
      expect(document.surfaces.single.authoredAttributes, <String>{
        'position',
        'normal',
      });
    });
  });
}
