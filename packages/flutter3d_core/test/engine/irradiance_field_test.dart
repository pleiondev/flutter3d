/// A field of probes, and what it refuses to let through — `gfx-81n`.
///
///     dart test test/engine/irradiance_field_test.dart
///
/// Three things decide whether a probe scheme is usable, and none of them is
/// the irradiance itself: the octahedral mapping has to be continuous, the
/// gutter has to carry the wrapped-around value, and the visibility test has to
/// stop light crossing a wall. Get the first wrong and directions alias; the
/// second, and every probe shows as a bright dot; the third, and a dark room
/// glows along its edges. All three read as lighting artefacts rather than as
/// bugs, which is why each has its own test here.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

IrradianceField _field({int tile = 8, int depthTile = 16}) => IrradianceField(
  origin: Vector3.zero(),
  spacing: Vector3(1.0, 1.0, 1.0),
  countX: 2,
  countY: 2,
  countZ: 2,
  tile: tile,
  depthTile: depthTile,
);

void main() {
  group('the octahedral mapping', () {
    test('a direction survives a round trip', () {
      // Sixty-four directions off a spiral rather than the six axes: the axes
      // land on the corners and the middle of the square, which are exactly the
      // points a broken mapping still gets right.
      for (var i = 0; i < 64; i++) {
        final z = 1.0 - 2.0 * (i + 0.5) / 64;
        final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
        final theta = i * 2.399963229728653;
        final direction = Vector3(
          radius * math.cos(theta),
          radius * math.sin(theta),
          z,
        );
        final uv = encodeOctahedral(direction);
        final back = decodeOctahedral(uv.x, uv.y);
        expect(
          back.dot(direction),
          closeTo(1.0, 1e-5),
          reason: 'direction $i came back as $back',
        );
      }
    });

    test('the whole square is used', () {
      // Every corner of the unit square is a real direction, which is what
      // makes the mapping worth its arithmetic: a hemispherical one would waste
      // half of every tile.
      for (final corner in <Vector2>[
        Vector2(0.0, 0.0),
        Vector2(1.0, 0.0),
        Vector2(0.0, 1.0),
        Vector2(1.0, 1.0),
      ]) {
        final direction = decodeOctahedral(corner.x, corner.y);
        expect(direction.length, closeTo(1.0, 1e-6));
        expect(direction.z, lessThan(0.0), reason: 'a corner is the far pole');
      }
    });
  });

  group('the gutter', () {
    test('the border carries the interior it wraps around to', () {
      // Without this a bilinear read near a tile edge reaches a texel belonging
      // to the next probe, and the field shows a grid of bright dots.
      final field = _field(tile: 4);
      // Paint the whole tile of probe zero, then check a border texel took the
      // value of the interior texel it mirrors.
      for (var i = 0; i < 4 * 4; i++) {
        final x = i % 4;
        final y = i ~/ 4;
        final at = ((0 * 6 + y + 1) * 6 + x + 1) * 3;
        field.irradiance[at] = (i + 1).toDouble();
      }
      field.fillGutters();

      // Top border, column 0, mirrors interior column 3 of row 0.
      const stride = 6;
      final border = ((0 * stride + 0) * stride + 1) * 3;
      final source = ((0 * stride + 1) * stride + 4) * 3;
      expect(field.irradiance[border], field.irradiance[source]);
      expect(field.irradiance[border], isNot(0.0));
    });

    test('every probe gets its own border, not its neighbour’s', () {
      final field = _field(tile: 4);
      const stride = 6;
      // Probe one only.
      for (var i = 0; i < 4 * 4; i++) {
        final at = ((1 * stride + i ~/ 4 + 1) * stride + i % 4 + 1) * 3;
        field.irradiance[at] = 5.0;
      }
      field.fillGutters();

      final zeroBorder = ((0 * stride + 0) * stride + 1) * 3;
      final oneBorder = ((1 * stride + 0) * stride + 1) * 3;
      expect(field.irradiance[oneBorder], 5.0);
      expect(field.irradiance[zeroBorder], 0.0);
    });
  });

  group('the visibility test', () {
    test('nearer than what the probe sees is fully visible', () {
      final field = _field();
      final direction = Vector3(0.0, 0.0, 1.0);
      field.writeDepth(0, direction, 5.0);
      expect(field.visibility(0, direction, 2.0), 1.0);
    });

    test('past it the weight falls off rather than snapping', () {
      // Chebyshev rather than a yes or no: a binary test makes a hard edge
      // exactly where the probes happen to sit.
      final field = _field();
      final direction = Vector3(0.0, 0.0, 1.0);
      // A probe looking into a corner: some near, some far, so the variance is
      // real and the falloff is soft.
      final at = _depthTexel(field, 0, direction);
      field.depth[at] = 4.0;
      field.depth[at + 1] = 20.0;

      final near = field.visibility(0, direction, 4.5);
      final far = field.visibility(0, direction, 9.0);
      expect(near, lessThan(1.0));
      expect(far, lessThan(near));
      expect(far, greaterThan(0.0));
    });

    test('a flat wall cuts sharply', () {
      // Every ray in that direction came back the same length, so the variance
      // is nothing and anything past the wall is not visible. This is the case
      // that stops light leaking into the next room.
      final field = _field();
      final direction = Vector3(0.0, 0.0, 1.0);
      field.writeDepth(0, direction, 3.0);
      expect(field.visibility(0, direction, 6.0), lessThan(0.001));
    });
  });

  group('sampling', () {
    test('a point in a uniformly lit field reads that colour', () {
      final field = _field();
      final colour = Vector3(0.2, 0.4, 0.6);
      for (var p = 0; p < field.probeCount; p++) {
        for (var i = 0; i < 64; i++) {
          final z = 1.0 - 2.0 * (i + 0.5) / 64;
          final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
          final theta = i * 2.399963229728653;
          final d = Vector3(
            radius * math.cos(theta),
            radius * math.sin(theta),
            z,
          );
          field
            ..writeIrradiance(p, d, colour)
            ..writeDepth(p, d, 100.0);
        }
      }
      field.fillGutters();

      final got = field.sample(Vector3(0.5, 0.5, 0.5), Vector3(0.0, 1.0, 0.0));
      expect(got.x, closeTo(colour.x, 1e-5));
      expect(got.y, closeTo(colour.y, 1e-5));
      expect(got.z, closeTo(colour.z, 1e-5));
    });

    test('a probe that cannot see the point does not light it', () {
      // The leak test, as arithmetic. One probe is bright and blind — it sees a
      // wall a tenth of a unit away — and the rest are dark. A field without a
      // visibility test would average the bright one in.
      final field = _field();
      for (var p = 0; p < field.probeCount; p++) {
        for (var i = 0; i < 64; i++) {
          final z = 1.0 - 2.0 * (i + 0.5) / 64;
          final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
          final theta = i * 2.399963229728653;
          final d = Vector3(
            radius * math.cos(theta),
            radius * math.sin(theta),
            z,
          );
          field
            ..writeIrradiance(
              p,
              d,
              p == 0 ? Vector3(1.0, 0.0, 0.0) : Vector3.zero(),
            )
            ..writeDepth(p, d, p == 0 ? 0.1 : 100.0);
        }
      }
      field.fillGutters();

      final got = field.sample(Vector3(0.5, 0.5, 0.5), Vector3(0.0, 1.0, 0.0));
      expect(
        got.x,
        lessThan(0.05),
        reason: 'the blind probe leaked its red through a wall: $got',
      );
    });
  });
}

int _depthTexel(IrradianceField field, int probe, Vector3 direction) {
  final uv = encodeOctahedral(direction);
  final stride = field.depthTile + 2;
  final x = (uv.x * field.depthTile).floor().clamp(0, field.depthTile - 1) + 1;
  final y = (uv.y * field.depthTile).floor().clamp(0, field.depthTile - 1) + 1;
  return ((probe * stride + y) * stride + x) * 2;
}
