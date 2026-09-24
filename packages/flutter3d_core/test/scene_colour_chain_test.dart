/// Where each level of the copy of the scene sits in its one texture — `M3`.
///
///     dart test test/scene_colour_chain_test.dart
library;

import 'package:flutter3d_core/src/engine/render/scene_colour_chain.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

void main() {
  test('the base, then five halvings down a column beside it', () {
    final chain = SceneColourChain(64, 48);
    expect(chain.levels, SceneColourChain.maxLevels);
    expect(chain.atlasWidth, 96);
    expect(chain.atlasHeight, 48);
    expect(chain.rect(0), const ScreenRect(width: 64, height: 48));
    expect(chain.rect(1), const ScreenRect(x: 64, width: 32, height: 24));
    expect(
      chain.rect(2),
      const ScreenRect(x: 64, y: 24, width: 16, height: 12),
    );
    expect(chain.rect(5), const ScreenRect(x: 64, y: 45, width: 2, height: 1));
    expect(
      <int>[for (var k = 0; k < 6; k++) chain.taps(k)],
      <int>[1, 1, 2, 4, 8, 16],
    );
  });

  test('no two levels overlap, and every one is inside the texture', () {
    // Mutation: start the column at y 0 for every level. The levels land on
    // each other.
    for (final (w, h) in <(int, int)>[(64, 48), (37, 23), (1, 1), (2, 900)]) {
      final chain = SceneColourChain(w, h);
      final rects = <ScreenRect>[
        for (var k = 0; k < chain.levels; k++) chain.rect(k),
      ];
      for (final r in rects) {
        expect(r.width, greaterThan(0));
        expect(r.x + r.width, lessThanOrEqualTo(chain.atlasWidth));
        expect(r.y + r.height, lessThanOrEqualTo(chain.atlasHeight));
      }
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          final p = rects[a];
          final q = rects[b];
          final apart =
              p.x + p.width <= q.x ||
              q.x + q.width <= p.x ||
              p.y + p.height <= q.y ||
              q.y + q.height <= p.y;
          expect(apart, isTrue, reason: '$w×$h levels $a and $b');
        }
      }
    }
  });

  test('a scene too small to halve five times has fewer levels', () {
    expect(SceneColourChain(1, 1).levels, 1);
    expect(SceneColourChain(8, 100).levels, 4);
  });
}
