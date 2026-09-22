/// `gfx-31n`: a bloom that covers the same share of the frame at any size.
///
///     flutter test test/bloom_reach_test.dart
///
/// **The defect, in one sentence.** `BloomSettings.levels` is a count of
/// halvings, and each halving doubles the glow's reach *in pixels* — so a
/// chain of five reaches a fixed number of pixels, which is a different
/// fraction of the picture at 512 than at 1024. Export a frame at twice the
/// size and the bloom covers half as much of it, from settings nobody
/// touched.
///
/// Checked as arithmetic rather than by rendering two frames and comparing
/// glows: the claim is about a count, and a claim about a count should be
/// held to a count.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero leaves the count exactly alone, and is the default', () {
    // Every frame recorded before this row was recorded with `levels` meaning
    // what it says. That has to keep being true or the goldens move for a
    // reason nobody would connect to a resolution.
    expect(const BloomSettings().referenceHeight, 0);
    for (final height in <int>[64, 512, 1080, 4320]) {
      expect(
        bloomLevelsFor(const BloomSettings(levels: 5), frameHeight: height),
        5,
      );
    }
  });

  test('the same height is the same chain', () {
    expect(
      bloomLevelsFor(
        const BloomSettings(levels: 5, referenceHeight: 512),
        frameHeight: 512,
      ),
      5,
    );
  });

  test('a doubling of the frame is one more halving', () {
    const settings = BloomSettings(levels: 5, referenceHeight: 512);
    expect(bloomLevelsFor(settings, frameHeight: 1024), 6);
    expect(bloomLevelsFor(settings, frameHeight: 2048), 7);
    expect(
      bloomLevelsFor(settings, frameHeight: 256),
      4,
      reason: 'and a halving of the frame is one fewer',
    );
  });

  test('a fraction of a doubling rounds, because a level is whole', () {
    // The chain cannot grow by half a level, so a frame 1.5x taller takes one
    // more rather than none — which keeps the reach closer to the right
    // fraction than truncating would.
    const settings = BloomSettings(levels: 5, referenceHeight: 512);
    expect(bloomLevelsFor(settings, frameHeight: 768), 6);
    expect(bloomLevelsFor(settings, frameHeight: 600), 5);
  });

  test('a frame with no height is the count unchanged, not a crash', () {
    // A viewport animating open is a real state and a zero-height frame is
    // what it looks like from here; `log(0)` is not an answer to give it.
    expect(
      bloomLevelsFor(
        const BloomSettings(levels: 5, referenceHeight: 512),
        frameHeight: 0,
      ),
      5,
    );
  });
}
