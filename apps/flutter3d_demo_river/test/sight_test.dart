/// How far the game's camera sees, and what is fitted to it: the river's
/// water, kept only where the picture shows it, and the shadows' cascades,
/// fitted to as far as the haze lets anything be seen.
library;

import 'package:flame_test/flame_test.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_river/src/river_game.dart';
import 'package:flutter3d_demo_river/src/river_water.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a reach the shaking picture leaves by a few metres is kept', () {
    // The picture shows reaches 3 to 6; a shake drops its bottom edge into
    // reach 2 and back. Mutation: keep only what the picture shows, and
    // reach 2 goes and comes back, its bed blinking through.
    expect(RiverWater.keeps(2, 3, 6), isTrue);
    expect(RiverWater.keeps(7, 3, 6), isTrue);
    // A whole reach out of it is let go.
    expect(RiverWater.keeps(1, 3, 6), isFalse);
    expect(RiverWater.keeps(8, 3, 6), isFalse);
  });

  test('the water is kept from under the jet\'s tail to past the top of the '
      'picture', () async {
    // Mutation: leave the half field of view out of `RiverWater.seen`, and
    // the top and the bottom of the picture are both the middle of it, nine
    // metres ahead of the jet: nothing behind the jet is kept.
    final game = await initializeGame(RiverGame.new);
    game.open3d(cpuTestDevice(width: 32, height: 24).device);
    await game.ready();
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
      await game.ready();
    }
    final (:near, :far) = RiverWater.seen(game.camera3d);
    final distance = game.distance;
    // The chase camera stands eleven metres behind the jet and 12.7 up,
    // looking at the water nine ahead of it through 0.85 rad: the bottom of
    // its picture meets the water about three metres behind the jet's
    // middle, the top about eighty ahead.
    expect(near, lessThan(distance));
    expect(near, greaterThan(distance - 8.0));
    expect(far, greaterThan(distance + 60.0));
    expect(far, lessThan(distance + 100.0));
  });

  test(
    'the shadows are fitted to as far as the haze lets anything be seen',
    () {
      // Mutation: drop `shadows:` from `RiverGame.renderSettings`, and the
      // cascades are fitted to the default sixty metres, the near two ending
      // about thirty metres from the camera.
      final shadows = RiverGame().renderSettings().shadows;
      expect(RiverGame.seenThroughHaze, closeTo(978.0, 1.0));
      expect(shadows.viewDistance, RiverGame.seenThroughHaze);
    },
  );
}
