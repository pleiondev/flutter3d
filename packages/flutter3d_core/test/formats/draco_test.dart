/// A Draco-compressed mesh decodes to the mesh it was made from — `gfx-82n`.
///
///     dart test test/formats/draco_test.dart
///
/// **The fixtures were made by Draco's own encoder from a model this repository
/// already ships.** `apps/flutter3d_editor/assets/templates/shooter/`'s monster
/// went through `@gltf-transform/cli draco`, once each way, and the expected
/// corner positions beside them were read out of the *uncompressed* file. So
/// the comparison is between somebody else's compressor and this decoder, with
/// the original as the referee — which is the arrangement `gfx-78n` established
/// is the only one worth having: four bugs in the zstd decoder on that row all
/// looked right and were caught only because a real encoder disagreed.
///
/// **Corners, not vertices.** Draco deduplicates per primitive, so the
/// compressed mesh has sixty-four vertices where the glTF it came from shares
/// an accessor of nineteen hundred across six primitives. Comparing counts
/// would compare two different and equally correct answers; comparing where
/// each triangle corner *lands* compares the thing that has to match.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _fixtures = 'test/formats/fixtures/draco';

Uint8List _fixture(String name) => File('$_fixtures/$name').readAsBytesSync();

/// Where each of the 180 triangle corners sits in the uncompressed twin.
Float32List _expectedCorners() {
  final bytes = _fixture('monster_expected_corners.bin');
  return Float32List.view(bytes.buffer, bytes.offsetInBytes, 180 * 3);
}

void main() {
  test('a sequential mesh decodes to where its twin puts every corner', () {
    final mesh = decodeDraco(_fixture('monster_sequential.drc'));
    expect(mesh.indices.length, 180);

    final position = mesh.attributes.values.firstWhere(
      (a) => a.type == DracoAttributeType.position,
    );
    expect(position.components, 3);
    expect(position.values.length, 64 * 3);

    final expected = _expectedCorners();
    var worst = 0.0;
    for (var corner = 0; corner < mesh.indices.length; corner++) {
      final vertex = mesh.indices[corner];
      for (var c = 0; c < 3; c++) {
        final difference =
            (position.values[vertex * 3 + c] - expected[corner * 3 + c]).abs();
        worst = math.max(worst, difference);
      }
    }

    // **Half a quantisation step, which is the whole error budget.** The model
    // was encoded at fourteen bits over a range of 0.95, so one step is 5.8e-5
    // and nothing can land further than half of that from where it started.
    // The bound is that number rather than a round one, because a decoder that
    // is merely *close* is a decoder with a bug in it somewhere: this one is
    // exact up to the rounding the encoder did.
    expect(worst, lessThan(3.0e-5), reason: 'worst corner moved by $worst');
  });

  test('the normals come back as unit vectors', () {
    // Octahedral: two integers a point, three floats out, through a transform
    // full of sign cases. Anything wrong in it gives vectors that are still
    // finite and no longer unit, which is why the length is what this checks.
    final mesh = decodeDraco(_fixture('monster_sequential.drc'));
    final normals = mesh.attributes.values.firstWhere(
      (a) => a.type == DracoAttributeType.normal,
    );
    expect(normals.components, 3);
    expect(normals.values.length, 64 * 3);

    for (var i = 0; i < 64; i++) {
      final x = normals.values[i * 3];
      final y = normals.values[i * 3 + 1];
      final z = normals.values[i * 3 + 2];
      expect(
        math.sqrt(x * x + y * y + z * z),
        closeTo(1.0, 1e-5),
        reason: 'normal $i is not a unit vector',
      );
    }
  });

  test('the triangles are the ones the encoder was given', () {
    // Sequential connectivity is stored as plain indices, so this is the
    // cheapest statement that the index width was read from the point count
    // rather than assumed: at sixty-four points they are single bytes, and any
    // other reading produces indices past the end of the attribute.
    final mesh = decodeDraco(_fixture('monster_sequential.drc'));
    expect(
      mesh.indices.take(9),
      orderedEquals(<int>[0, 1, 2, 0, 2, 3, 4, 0, 3]),
    );
    for (final index in mesh.indices) {
      expect(index, lessThan(64));
    }
  });

  group('what is refused, and the message says which', () {
    test('an edgebreaker mesh is refused by name', () {
      // **The half of this row that is not built.** The same model, encoded the
      // way the tool does by default. Refusing it by name is the honest answer:
      // a decoder that guessed at the connectivity would produce a mesh with
      // the right vertex count and the wrong faces, which draws as a knot.
      expect(
        () => decodeDraco(_fixture('monster_edgebreaker.drc')),
        throwsA(
          isA<DracoException>().having(
            (e) => e.message,
            'message',
            contains('edgebreaker'),
          ),
        ),
      );
    });

    test('a file that is not Draco at all', () {
      expect(
        () => decodeDraco(Uint8List.fromList('not draco here'.codeUnits)),
        throwsA(
          isA<DracoException>().having(
            (e) => e.message,
            'message',
            contains('DRACO magic'),
          ),
        ),
      );
    });

    test('a truncated stream', () {
      final whole = _fixture('monster_sequential.drc');
      expect(
        () => decodeDraco(Uint8List.sublistView(whole, 0, 40)),
        throwsA(isA<DracoException>()),
      );
    });
  });
}
