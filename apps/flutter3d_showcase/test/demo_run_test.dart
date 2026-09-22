/// The camera a page's first frame draws with is the one `configureView`
/// asked for, not the one `OrbitController`'s own constructor happened to
/// default to.
library;

import 'package:flutter3d_showcase/pages/shadows/soft_shadows.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/page_harness.dart';

void main() {
  test(
    "a page's first frame already stands where configureView put it",
    () async {
      // `SoftShadowsDemo.configureView` sets distance 8.0 — nowhere near
      // `DemoRun.start`'s own construction defaults (3.5) — and, like most
      // pages, never calls `context.orbit.apply()` itself: it was relying on
      // `DemoRun` to have done that already.
      //
      // Mutation: drop `context.orbit.apply()` from `DemoRun.start`. The
      // camera then stays at the constructor's distance of 3.5 until the
      // first drag calls `rotate()`, which is what made a page's very first
      // pixel of rotation look like the view jumping to where it should have
      // started — this reads the camera before any drag happens at all.
      final device = cpuDevice();
      final DemoRun run = await DemoRun.start(device, SoftShadowsDemo());
      try {
        final Vector3 eye = run.context.camera.readWorldPosition();
        final double distance = eye.length; // the demo's target is the origin
        expect(
          distance,
          closeTo(8.0, 1e-6),
          reason:
              'the camera sits $distance from the target; configureView '
              'asked for 8.0 and nothing should have left it anywhere else',
        );
      } finally {
        run.dispose();
      }
    },
  );
}
