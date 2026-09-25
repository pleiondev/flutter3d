/// The engine's data tables are the bytes the generator wrote, and each
/// device is given them once — `G1`.
///
///     dart test test/engine/engine_tables_test.dart
///
/// A table's hash is pinned: a change to the generator that changes a byte
/// changes every golden that samples it, and should be seen here first, on
/// purpose, rather than as a picture that moved.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/src/engine/render/engine_tables.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureFormat;
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

int _fnv1a(Uint8List bytes) => bytes.fold(
  0x811c9dc5,
  (hash, byte) => ((hash ^ byte) * 0x01000193) & 0xffffffff,
);

/// An IEEE half, for the few the tests read. Finite and normal here.
double _half(int bits) {
  final exponent = (bits >> 10) & 0x1f;
  final mantissa = bits & 0x3ff;
  if (exponent == 0) return mantissa / 1024.0 / 16384.0;
  return (1.0 + mantissa / 1024.0) * (1 << exponent) / 32768.0;
}

void main() {
  test('each table is the size its descriptor says', () {
    for (final table in EngineTables.all) {
      final texel = switch (table.format) {
        TextureFormat.r8UNormInt => 1,
        TextureFormat.r16g16b16a16Float => 8,
        _ => throw StateError('no size known for ${table.format}'),
      };
      expect(
        table.bytes.length,
        table.width * table.height * texel,
        reason: table.name,
      );
    }
  });

  test('each table hashes to its pinned value', () {
    // Mutation: change the Gaussian's σ in `tool/make_tables.dart` and rerun
    // it. The noise is still blue and the hash is not this one.
    final hashes = <String, int>{
      for (final table in EngineTables.all) table.name: _fnv1a(table.bytes),
    };
    expect(hashes, <String, int>{
      'blueNoise': 1332832323,
      // Rebaked over −10…+10 stops, so the table reaches the curve's roof.
      'aces2Display': 3220052977,
      // `M2` wrote the sheen's albedo into the second table's z lane,
      // which the published fit leaves empty and nothing read before.
      'ltc': 1806585161,
    });
  });

  test('the LTC table carries the sheen albedo in its spare lane', () {
    // Row `64 + j` of the second table is sqrt(1 − n·v) = j / 63 and column
    // `i` is roughness i / 63; z is the half at byte 4 of each texel.
    final view = ByteData.sublistView(
      EngineTables.all.firstWhere((table) => table.name == 'ltc').bytes,
    );
    double z(int row, int column) => _half(
      view.getUint16(((64 + row) * 64 + column) * 8 + 4, Endian.little),
    );
    // Mutation: skip the sheen loop in `ltcTable`. Every z is nought.
    expect(z(0, 63), greaterThan(0.05));
    // A cloth is brightest at grazing: the albedo grows away from head-on.
    expect(z(60, 63), greaterThan(z(0, 63)));
    // Never more light than arrives.
    for (var row = 0; row < 64; row++) {
      for (var column = 0; column < 64; column++) {
        expect(z(row, column), inInclusiveRange(0.0, 1.0));
      }
    }
  });

  group('blue noise', () {
    final atlas = EngineTables.all
        .firstWhere((table) => table.name == 'blueNoise')
        .bytes;
    Uint8List slice(int s) => Uint8List.fromList([
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 64; x++)
          atlas[((s ~/ 8) * 64 + y) * 512 + (s % 8) * 64 + x],
    ]);

    test('every value occurs sixteen times in every slice', () {
      for (var s = 0; s < 32; s++) {
        final counts = List<int>.filled(256, 0);
        for (final v in slice(s)) {
          counts[v]++;
        }
        expect(counts, everyElement(16), reason: 'slice $s');
      }
    });

    test('neighbours disagree, which white noise would not', () {
      // Blue noise has no low frequencies, so a texel and the one beside it
      // are anticorrelated. White noise would put this near zero.
      for (var s = 0; s < 32; s++) {
        final v = slice(s);
        final mean = v.fold(0, (a, b) => a + b) / v.length;
        var together = 0.0;
        var alone = 0.0;
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            final a = v[y * 64 + x] - mean;
            together += a * (v[y * 64 + (x + 1) % 64] - mean);
            alone += a * a;
          }
        }
        expect(together / alone, lessThan(-0.2), reason: 'slice $s');
      }
    });

    test('slices differ from each other', () {
      expect(slice(0), isNot(slice(1)));
    });
  });

  test('a device is given each table once, when first asked', () {
    final device = FakeBackend();
    final tables = EngineTables.of(device);
    expect(tables.uploads, 0);
    final first = tables.blueNoise;
    expect(EngineTables.of(device).blueNoise, same(first));
    expect(tables.uploads, 1);
    expect(EngineTables.of(FakeBackend()), isNot(same(tables)));
  });
}
