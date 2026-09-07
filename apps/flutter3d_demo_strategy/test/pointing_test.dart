/// Turning a click into a place on the map.
///
///     flutter test test/pointing_test.dart
///
/// **This arithmetic used to be three lines inside a pointer callback**, which
/// is to say it could only be exercised by opening a window and clicking in it.
/// Two of its answers are wrong in ways a screenshot cannot show: a ray aimed at
/// the horizon divides by very nearly nothing and lands a kilometre off the map,
/// and a ray aimed above it lands behind the camera. Both are one click away
/// from ordinary play — the map camera looks down a shallow slope, and the sky
/// is at the top of every frame.
library;

import 'package:flutter3d_demo_strategy/src/pointing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a ray aimed down lands where it crosses the plane', () {
    // Forty-five degrees from twenty metres up: the crossing is twenty metres
    // along, which is a number that can be checked by hand.
    final Vector3? at = groundUnder(
      Vector3(10.0, 20.0, 5.0),
      Vector3(0.0, -1.0, 1.0)..normalize(),
      planeY: 0.0,
    );

    expect(at, isNotNull);
    expect(at!.x, closeTo(10.0, 1e-6));
    expect(at.z, closeTo(25.0, 1e-6));
  });

  test('and the plane it crosses is the one it was given', () {
    // Mutation: ignore `planeY` and use nought. The map camera focuses on the
    // hillside under it, which is fourteen metres up at the shallowest point of
    // the document, so a click would land metres past where it was aimed.
    final Vector3? high = groundUnder(
      Vector3(0.0, 20.0, 0.0),
      Vector3(0.0, -1.0, 1.0)..normalize(),
      planeY: 10.0,
    );

    expect(high, isNotNull);
    expect(high!.z, closeTo(10.0, 1e-6));
  });

  test('the answer is a place in plan, with no height on it', () {
    // Carried through as a goal, and every reader of a goal — the flow field,
    // the arrangement, the fog — asks about a place rather than a height. A
    // height here would make one spot clicked from two camera distances into
    // two goals, and the simulation builds a field per distinct goal.
    final Vector3? at = groundUnder(
      Vector3(0.0, 30.0, 0.0),
      Vector3(0.0, -1.0, 0.0),
      planeY: 12.0,
    );

    expect(at!.y, 0.0);
  });

  test('a ray aimed at the sky lands nowhere', () {
    // Mutation: drop the guard and let the division run. The denominator is
    // positive, the parameter comes out negative, and the click lands behind
    // the camera — off the back of the map, where a crowd would be sent by a
    // player who clicked the sky.
    expect(
      groundUnder(
        Vector3(0.0, 20.0, 0.0),
        Vector3(0.0, 0.5, 1.0)..normalize(),
        planeY: 0.0,
      ),
      isNull,
    );
  });

  test('and one aimed along the horizon lands nowhere either', () {
    // The dangerous case, because it is not obviously wrong: a ray a hair below
    // level does cross the plane, thousands of metres away. Answering it would
    // send the crowd off the edge of the map at a click nobody meant.
    expect(
      groundUnder(Vector3(0.0, 20.0, 0.0), Vector3(0.0, 0.0, 1.0), planeY: 0.0),
      isNull,
    );
    expect(
      groundUnder(
        Vector3(0.0, 20.0, 0.0),
        Vector3(0.0, -1e-5, 1.0)..normalize(),
        planeY: 0.0,
      ),
      isNull,
    );
  });

  test('a camera already below the plane is looking at nothing', () {
    // Aimed down from under the ground it is asking about. There is no
    // crossing ahead of the ray, and the arithmetic would happily report one
    // behind it.
    expect(
      groundUnder(
        Vector3(0.0, -5.0, 0.0),
        Vector3(0.0, -1.0, 0.0),
        planeY: 0.0,
      ),
      isNull,
    );
  });
}
