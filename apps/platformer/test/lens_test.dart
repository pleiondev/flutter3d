/// The lens the game is played through.
///
///     flutter test test/lens_test.dart
///
/// **This exists because the game was played at the wrong one for its whole
/// life and nothing said so.** The camera was built with a 60° lens and a 220 m
/// far plane, chosen for levels 120 by 260 metres — and a second, bare
/// `PerspectiveProjection()` sat beside it as the thing a widened view returned
/// to. The camera's projection is rebuilt every frame from that second one, so
/// the first was overwritten before anybody ever saw it: 45° and a kilometre,
/// for months.
///
/// A test on the *numbers* would not have caught that; the numbers were right
/// where they were written. What was wrong was that there were two of them. So
/// what is pinned here is the shape of the fix — one base, one operation — and
/// the two things the operation must not do.
library;

import 'package:flutter3d/flutter3d.dart' show PerspectiveProjection;
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/lens.dart';

void main() {
  test('the game is played wider than the engine default, and not as deep', () {
    // Mutation: give `Lens.base` the bare `PerspectiveProjection()` the camera
    // was really running on. Both of these fail, and they are the two numbers
    // that were silently thrown away.
    const bare = PerspectiveProjection();

    expect(Lens.base.fovYRadians, greaterThan(bare.fovYRadians),
        reason: 'a narrow lens in a third-person platformer hides the ledge '
            'you are aiming at');
    expect(Lens.base.far, lessThan(bare.far),
        reason: 'a kilometre of depth range over a 260 m level is precision '
            'spent on nothing');
  });

  test('widening opens the view and leaves everything else alone', () {
    // **The claim the bug actually violated.** Widening rebuilt the projection
    // from a different base, so the far plane and the field of view both
    // reverted. Mutation: build `widened` from `const PerspectiveProjection()`
    // instead of from `base` — the far plane jumps back to a kilometre here.
    final wide = Lens.widened(0.12);

    expect(wide.fovYRadians, closeTo(Lens.base.fovYRadians + 0.12, 1e-9));
    expect(wide.far, Lens.base.far, reason: 'the far plane moved');
    expect(wide.near, Lens.base.near, reason: 'the near plane moved');
  });

  test('and widening by nothing is the lens itself', () {
    // The property that makes it safe to call every frame: a camera at rest
    // must be looking through exactly what the level was authored for, not
    // through something a rounding away from it.
    expect(Lens.widened(0.0).fovYRadians, Lens.base.fovYRadians);
    expect(Lens.widened(0.0).far, Lens.base.far);
  });
}
