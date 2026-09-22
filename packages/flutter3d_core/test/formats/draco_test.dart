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

import 'helpers/triangle_match.dart';

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

  test('an edgebreaker mesh decodes to the same triangles as its twin', () {
    // **The same model, encoded the way the tool does by default** — and until
    // the second half of this row, refused by name. Edgebreaker stores no
    // indices and no vertex order: the faces come back in the order the
    // encoder's walk left them and the vertices in the order a second walk
    // reaches them, so neither can be compared by position in a list. What can
    // is the *set of triangles*: every one the uncompressed file has must be
    // here, once, wound the same way.
    final mesh = decodeDraco(_fixture('monster_edgebreaker.drc'));
    expect(mesh.indices.length, 180);

    final position = mesh.attributes.values.firstWhere(
      (a) => a.type == DracoAttributeType.position,
    );
    expect(position.values.length, mesh.pointCount * 3);

    final decoded = Float32List(180 * 3);
    for (var corner = 0; corner < 180; corner++) {
      decoded.setRange(
        corner * 3,
        corner * 3 + 3,
        position.values,
        mesh.indices[corner] * 3,
      );
    }
    expect(
      unmatchedTriangles(_expectedCorners(), decoded, const <double>[
        3.0e-5,
        3.0e-5,
        3.0e-5,
      ]),
      isEmpty,
      reason: 'triangles of the original with no twin in the decoded mesh',
    );
  });

  group('what is refused, and the message says which', () {
    /// The edgebreaker fixture with one byte of its header changed.
    Uint8List edgebreakerWith(int offset, int value) =>
        Uint8List.fromList(_fixture('monster_edgebreaker.drc'))
          ..[offset] = value;

    test('the retired predictive traversal', () {
      // Byte 11 is the first after the header: which of the three traversals
      // stored the symbols. The fixture says 0; 1 was retired before 2.2, and
      // a decoder that read it as either of the others would build a mesh out
      // of whatever those bits happened to spell.
      expect(
        () => decodeDraco(edgebreakerWith(11, 1)),
        throwsA(
          isA<DracoException>().having(
            (e) => e.message,
            'message',
            contains('predictive'),
          ),
        ),
      );
    });

    test('edgebreaker from before bitstream 2.2', () {
      // Byte 6 is the minor version. 2.1 orders the connectivity sections
      // differently, so the same bytes mean something else.
      expect(
        () => decodeDraco(edgebreakerWith(6, 1)),
        throwsA(
          isA<DracoException>().having(
            (e) => e.message,
            'message',
            contains('only 2.2'),
          ),
        ),
      );
    });

    test('an edgebreaker stream cut anywhere', () {
      // Every prefix, because this decoder follows counts it has just read
      // into arrays it has just sized, and the only acceptable failure is the
      // one exception the caller was promised — never a RangeError from
      // somewhere inside a corner table.
      final whole = _fixture('monster_edgebreaker.drc');
      for (var length = 0; length < whole.length; length++) {
        expect(
          () => decodeDraco(Uint8List.sublistView(whole, 0, length)),
          throwsA(isA<DracoException>()),
          reason: 'cut to $length bytes',
        );
      }
    });

    test('an edgebreaker stream with any one byte damaged', () {
      // Damage is worse than truncation: the counts still add up and the
      // symbols still decode, into a surface that may fold back on itself —
      // and half of this decoder is loops that walk round a vertex until they
      // come back to where they started. Each byte, flipped two ways, must end
      // in a mesh or in the one exception; a hang fails the test by timeout
      // and anything else fails it by type.
      final whole = _fixture('monster_edgebreaker.drc');
      for (var at = 0; at < whole.length; at++) {
        for (final mask in const <int>[0xFF, 0x01]) {
          final damaged = Uint8List.fromList(whole)..[at] ^= mask;
          try {
            final mesh = decodeDraco(damaged);
            for (final index in mesh.indices) {
              expect(index, lessThan(mesh.pointCount));
            }
          } on DracoException {
            // Refused by name, which is the other acceptable ending.
          }
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

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
