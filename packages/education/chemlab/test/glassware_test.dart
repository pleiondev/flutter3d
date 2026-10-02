import 'dart:typed_data';

import 'package:chemlab/chemlab.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profiles', () {
    for (final (name, profile) in [
      ('tube', tubeProfile()),
      ('beaker', beakerProfile()),
      ('flask', flaskProfile()),
      ('cylinder', cylinderProfile()),
    ]) {
      test('a $name starts on the axis and never goes below its base', () {
        // Mutation: start the profile off the axis, and the base is a hole.
        expect(profile.first.x, 0);
        expect(profile.every((p) => p.y >= 0 && p.x >= 0), isTrue);
      });
    }

    test('a liquid is cut at its level and capped on the axis', () {
      // Mutation: drop the cap, and the liquid is an open cup.
      for (final profile in [
        tubeLiquidProfile(0.4),
        flatLiquidProfile(0.19, 0.004, 0.25),
        flaskLiquidProfile(0.2),
      ]) {
        expect(profile.last.x, 0);
        expect(profile.last.y, closeTo(profile[profile.length - 2].y, 1e-12));
      }
    });

    test('a liquid stays inside its glass', () {
      // Mutation: give the tube's liquid the glass's own radius.
      final glass = tubeProfile()
          .map((p) => p.x)
          .reduce((a, b) => a > b ? a : b);
      final inside = tubeLiquidProfile(
        0.6,
      ).map((p) => p.x).reduce((a, b) => a > b ? a : b);
      expect(inside, lessThan(tubeRadius));
      expect(glass, greaterThan(inside));
    });

    test('the flask liquid narrows with the cone as it rises', () {
      final low = flaskLiquidProfile(0.08)[4].x;
      final high = flaskLiquidProfile(0.35)[4].x;
      expect(high, lessThan(low));
    });
  });

  group('the label band', () {
    test('sits just outside the tube and covers the turn asked for', () {
      // Mutation: put it on the glass, and the two fight for every pixel.
      final band = labelBand(wrap: 1.6);
      expect(band.profile.every((p) => p.x > tubeRadius), isTrue);
      expect(band.sweepAngle, 1.6);
    });

    test('its texture runs edge to edge: u over the turn, v up the band', () {
      final mesh = labelBand().build();
      final layout = mesh.layout;
      final uvs = <(double, double)>[];
      final data = mesh.vertexBytes;
      final stride = layout.strideInBytes;
      final uvOffset = layout.floatOffsetOf('texcoord') * 4;
      for (var i = 0; i < mesh.vertexCount; i++) {
        uvs.add((
          data.getFloat32(i * stride + uvOffset, Endian.little),
          data.getFloat32(i * stride + uvOffset + 4, Endian.little),
        ));
      }
      double low(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
      double high(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);
      expect(low(uvs.map((e) => e.$1)), closeTo(0, 1e-6));
      expect(high(uvs.map((e) => e.$1)), closeTo(1, 1e-6));
      expect(low(uvs.map((e) => e.$2)), closeTo(0, 1e-6));
      expect(high(uvs.map((e) => e.$2)), closeTo(1, 1e-6));
    });
  });

  test('a label is turned half round for the lathe', () {
    // Mutation: flip the rows only, and the text reads mirrored.
    final pixels = Uint8List.fromList([
      for (var i = 0; i < 6; i++) ...[i, i, i, 255],
    ]);
    final turned = forLathe(Rgba8Image(width: 3, height: 2, pixels: pixels));
    expect(turned.pixels.sublist(0, 4), [5, 5, 5, 255]);
    expect(turned.pixels.sublist(20, 24), [0, 0, 0, 255]);
  });
}
