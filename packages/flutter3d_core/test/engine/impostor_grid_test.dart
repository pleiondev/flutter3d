/// `C4`: the octahedral grid an impostor is baked on. The GPU and the software
/// stages read it through their own copies; this holds the Dart one that the
/// bake uses, which is the one the other two were written against.
///
/// Tolerances are single precision: `Vector3` keeps its components in a
/// `Float32List`.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('encode and decode are each other\'s inverse over the sphere', () {
    final random = math.Random(7);
    for (var i = 0; i < 500; i++) {
      final d = Vector3(
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
      );
      if (d.length2 < 1e-6) continue;
      d.normalize();
      final uv = impostorEncode(d);
      expect(uv.x, inInclusiveRange(0, 1));
      expect(uv.y, inInclusiveRange(0, 1));
      final back = impostorDecode(uv.x, uv.y);
      expect((back - d).length, lessThan(1e-6), reason: '$d');
    }
  });

  test('up is the middle of the atlas and down its corners', () {
    final up = impostorEncode(Vector3(0, 1, 0));
    expect(up.x, closeTo(0.5, 1e-6));
    expect(up.y, closeTo(0.5, 1e-6));
    for (final (c, r) in <(int, int)>[(0, 0), (7, 0), (0, 7), (7, 7)]) {
      expect(impostorViewDirection(c, r).y, closeTo(-1, 1e-6));
    }
  });

  test('a card faces its direction with a level right-hand axis', () {
    for (final d in <Vector3>[
      Vector3(0, 0, 1),
      Vector3(1, 0.3, -0.2)..normalize(),
      Vector3(0, 1, 0),
      Vector3(0, -1, 0),
    ]) {
      final right = impostorRight(d);
      expect(right.length, closeTo(1, 1e-6));
      expect(right.dot(d), closeTo(0, 1e-6));
      if (d.y.abs() < 0.999) expect(right.y, closeTo(0, 1e-6));
    }
    // From the front, right is +X: what a camera on +Z looking back sees.
    final front = impostorRight(Vector3(0, 0, 1));
    expect(front.x, closeTo(1, 1e-6));
  });

  test('the card mesh stands in the sphere it is measured by', () {
    final card = impostorCard(centre: Vector3(1, 2, 3), radius: 0.5);
    expect(card.vertexCount, 4);
    expect(card.triangleCount, 2);
    final bounds = card.computeBounds();
    expect(bounds.center.x, closeTo(1, 1e-6));
    expect(bounds.center.y, closeTo(2, 1e-6));
    expect(bounds.max.x - bounds.min.x, closeTo(1, 1e-6));
  });
}
