// The renderer's constants of nature, each written once: the sun's apparent
// radius the sky and the soft shadows share, and the luminous efficacy a
// radiometric watt is turned into lumens by.
import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

void main() {
  test('the sun is 0.2666 degrees in radius, not 0.2664', () {
    // Half the 0.533° the disc spans seen from the Earth. Mutation: the
    // 0.00465 this read before is 0.2664°, and the first expectation fails
    // by three millionths of a radian.
    expect(
      ShadowSettings.sunAngularRadius,
      closeTo(0.2666 * math.pi / 180.0, 5e-7),
    );
    expect(ShadowSettings.sunAngularRadius, 0.004653);
  });

  test('the sky\'s disc and the penumbra are the same sun', () {
    // Mutation: give `SkySettings` its own literal and the two drift apart
    // the next time either is corrected.
    expect(
      const SkySettings().sunAngularRadius,
      ShadowSettings.sunAngularRadius,
    );
  });

  test('a watt at 555 nanometres is 683 lumens', () {
    // The SI's definition of the candela fixes it (CGPM 1979). Mutation: any
    // other number, and every blackbody efficacy scales with it.
    expect(Photometric.luminousEfficacy, 683.0);
  });
}
