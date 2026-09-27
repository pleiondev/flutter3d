/// An `.spz` file reads into the same cloud as its `.ply` twin — `C6`.
///
///     dart test test/formats/splat_spz_test.dart
///
/// **The fixtures were written by the format's reference library**, not by
/// this repository (`tool/make_spz_fixture.py`): one cloud packed as versions
/// 2, 3 and 4, and each file decoded back *by the reference* into a PLY. So a
/// constant this reader has wrong — the colour scale, the scale's log offset,
/// which end of a quaternion the largest component's index sits at — shows
/// here as a disagreement with the reference, not as agreement with itself.
///
/// The twins are in a PLY's axes (right, down, front) and the files in SPZ's
/// (right, up, back), so reading them equal needs the half turn about X too,
/// spherical harmonics included.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const String _dir = 'test/formats/fixtures/splat/spz';

Uint8List _bytes(String name) => File('$_dir/$name').readAsBytesSync();

/// Every array of [actual] against [expected], to float precision.
void _expectSame(SplatCloud actual, SplatCloud expected) {
  expect(actual.count, expected.count);
  expect(actual.shDegree, expected.shDegree);
  void same(String name, Float32List a, Float32List b, double tolerance) {
    expect(a.length, b.length, reason: name);
    for (var i = 0; i < a.length; i++) {
      final scale = b[i].abs() > 1 ? b[i].abs() : 1.0;
      expect(
        (a[i] - b[i]).abs(),
        lessThanOrEqualTo(tolerance * scale),
        reason: '$name[$i]: ${a[i]} against ${b[i]}',
      );
    }
  }

  same('centres', actual.centres, expected.centres, 1e-6);
  same('colours', actual.colours, expected.colours, 1e-5);
  same('scales', actual.scales, expected.scales, 1e-5);
  same('rotations', actual.rotations, expected.rotations, 1e-5);
  same('shRest', actual.shRest, expected.shRest, 1e-6);
}

void main() {
  for (final version in <int>[2, 3, 4]) {
    test('version $version reads as the reference decodes it', () {
      final spz = parseSplatSpz(
        _bytes('cloud_v$version.spz'),
        axes: SplatAxes.rightDownFront,
      );
      final twin = parseSplatPly(
        _bytes('cloud_v$version.ply'),
        keepHigherBands: true,
      );
      expect(spz.count, 48);
      expect(spz.shDegree, 2);
      _expectSame(spz, twin);
    });
  }

  test('the stored axes are right, up, back: the twin turned half about X', () {
    final stored = parseSplatSpz(_bytes('cloud_v3.spz'));
    final ply = parseSplatSpz(
      _bytes('cloud_v3.spz'),
      axes: SplatAxes.rightDownFront,
    );
    for (var i = 0; i < stored.count; i++) {
      expect(stored.centres[i * 3], ply.centres[i * 3]);
      expect(stored.centres[i * 3 + 1], -ply.centres[i * 3 + 1]);
      expect(stored.centres[i * 3 + 2], -ply.centres[i * 3 + 2]);
      expect(stored.rotations[i * 4 + 1], -ply.rotations[i * 4 + 1]);
      expect(stored.rotations[i * 4 + 3], ply.rotations[i * 4 + 3]);
      // Band 1 is `y, z, x`: the first two change sign, the third does not.
      expect(stored.shRest[i * 24], -ply.shRest[i * 24]);
      expect(stored.shRest[i * 24 + 3], -ply.shRest[i * 24 + 3]);
      expect(stored.shRest[i * 24 + 6], ply.shRest[i * 24 + 6]);
    }
  });

  test('the higher bands can be left behind', () {
    final cloud = parseSplatSpz(_bytes('cloud_v4.spz'), keepHigherBands: false);
    expect(cloud.shDegree, 0);
    expect(cloud.shRest, isEmpty);
    expect(cloud.count, 48);
  });

  test('colour bytes are sRGB, clamped and decoded as a PLY is', () {
    // The twin test above holds the SPZ reader to the PLY one, so it would
    // pass with both left undecoded; this holds the SPZ reader to the curve.
    // Mutation: pass `SplatColourSpace.linear` down in place of the argument
    // and the default read equals the linear one.
    final raw = parseSplatSpz(
      _bytes('cloud_v4.spz'),
      colourSpace: SplatColourSpace.linear,
    );
    final decoded = parseSplatSpz(_bytes('cloud_v4.spz'));
    for (var i = 0; i < raw.count; i++) {
      for (var c = 0; c < 3; c++) {
        final channel = raw.colours[i * 4 + c];
        expect(channel, greaterThanOrEqualTo(0.0));
        final clamped = channel.clamp(0.0, 1.0);
        final linear = clamped <= 0.04045
            ? clamped / 12.92
            : math.pow((clamped + 0.055) / 1.055, 2.4);
        expect(decoded.colours[i * 4 + c], closeTo(linear, 1e-6));
      }
    }
  });

  test('both headers are recognised by their first bytes', () {
    expect(looksLikeSpz(_bytes('cloud_v4.spz')), isTrue);
    expect(looksLikeSpz(_bytes('cloud_v2.spz')), isTrue);
    expect(looksLikeSpz(_bytes('cloud_v2.ply')), isFalse);
  });

  group('refuses, and says why', () {
    Matcher refusal(String text) => throwsA(
      isA<SplatSpzException>().having(
        (SplatSpzException e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('a file that is neither layout', () {
      expect(
        () => parseSplatSpz(_bytes('cloud_v2.ply')),
        refusal('not an SPZ'),
      );
    });

    test('a version 4 file cut short', () {
      final whole = _bytes('cloud_v4.spz');
      expect(
        () => parseSplatSpz(Uint8List.sublistView(whole, 0, whole.length - 40)),
        refusal('past the end'),
      );
    });

    test('a version from the future', () {
      final bytes = Uint8List.fromList(_bytes('cloud_v4.spz'));
      bytes[4] = 5;
      expect(() => parseSplatSpz(bytes), refusal('version 5'));
    });

    // The legacy stream with its extension flag set and a record appended,
    // the way the reference writes one: `u32 type, u32 length, payload`.
    Uint8List withExtension(int type) {
      final inner = Uint8List.fromList(gzip.decode(_bytes('cloud_v3.spz')));
      inner[14] |= 0x2;
      final record = ByteData(12)
        ..setUint32(0, type, Endian.little)
        ..setUint32(4, 4, Endian.little);
      return Uint8List.fromList(
        gzip.encode(<int>[...inner, ...record.buffer.asUint8List()]),
      );
    }

    test('a stream that stores its cloud in other axes', () {
      expect(
        () => parseSplatSpz(withExtension(0xADBE0003)),
        refusal('SPZ_ADOBE_coordinate_system'),
      );
    });

    test('but not a vendor record it has no use for', () {
      expect(parseSplatSpz(withExtension(0xADBE0002)).count, 48);
    });
  });
}
