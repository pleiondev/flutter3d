/// The holder, as the frustum it gives each eye.
///
///     flutter test test/stereo_viewer_test.dart
///
/// What is worth testing here is the asymmetry. A pair of centred frustums is
/// easy to write and wrong in a holder: the lens sits nearer the middle of the
/// phone than the middle of the half it looks at, so each eye reaches further
/// outward than inward. Every test below is about that difference or about the
/// two ways it can be limited — by the lens, or by the glass the phone has.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone of ordinary size, in the orientation a holder puts it in.
const StereoScreen phone = StereoScreen(width: 0.147, height: 0.068);

/// The rig has to hang under a scene for a world position to mean anything.
StereoRig inScene({double near = 0.05, double far = 500.0}) {
  final scene = Scene();
  final rig = StereoRig(near: near, far: far);
  scene.add(rig.stage);
  return rig;
}

OffAxisProjection frustumOf(StereoRig rig, Eye eye) =>
    rig.camera(eye).projection as OffAxisProjection;

void main() {
  group('the frustum a holder gives an eye', () {
    test('is wider away from the nose than towards it', () {
      final left = StereoViewer.cardboardV2.projectionFor(Eye.left, phone);
      expect(left.tanLeft.abs(), greaterThan(left.tanRight));
    });

    test('mirrors between the eyes', () {
      const viewer = StereoViewer.cardboardV2;
      final left = viewer.projectionFor(Eye.left, phone);
      final right = viewer.projectionFor(Eye.right, phone);
      expect(right.tanRight, closeTo(left.tanLeft.abs(), 1e-12));
      expect(right.tanLeft.abs(), closeTo(left.tanRight, 1e-12));
      expect(right.tanUp, closeTo(left.tanUp, 1e-12));
      expect(right.tanDown, closeTo(left.tanDown, 1e-12));
    });

    test('sits off the middle of the screen by the tray height', () {
      // 35 mm of glass below the lens axis and the remaining 33 mm above it,
      // both at 39 mm from the lens. Which side is taller follows from the
      // phone: this one is 68 mm across, so the axis lands just below middle.
      final left = StereoViewer.cardboardV2.projectionFor(Eye.left, phone);
      expect(left.tanDown.abs(), closeTo(0.035 / 0.039, 1e-9));
      expect(left.tanUp, closeTo(0.033 / 0.039, 1e-9));
      expect(left.tanUp, isNot(closeTo(left.tanDown.abs(), 1e-3)));
    });

    test('takes the screen when the screen is the smaller of the two', () {
      // Half of 147 mm less half of 64 mm leaves 41.5 mm of glass outside the
      // lens, at 39 mm from it: a tangent of about 1.06, where 60° allows 1.73.
      final left = StereoViewer.cardboardV2.projectionFor(Eye.left, phone);
      expect(left.tanLeft.abs(), closeTo(0.0415 / 0.039, 1e-9));
      expect(left.tanLeft.abs(), lessThan(math.tan(60 * math.pi / 180)));
    });

    test('takes the lens when the lens is the smaller of the two', () {
      // A screen this size reaches far past what a 40° window passes.
      const wide = StereoScreen(width: 0.30, height: 0.20);
      final left = StereoViewer.cardboardV1.projectionFor(Eye.left, wide);
      expect(left.tanLeft.abs(), closeTo(math.tan(40 * math.pi / 180), 1e-12));
      expect(left.tanUp, closeTo(math.tan(40 * math.pi / 180), 1e-12));
    });

    test('stays drawable when the numbers are nonsense', () {
      // Lenses further apart than the screen is wide: the outward reach goes
      // negative, and a frustum of no width would be a matrix of infinities.
      const narrow = StereoScreen(width: 0.05, height: 0.02);
      final left = StereoViewer.cardboardV2.projectionFor(Eye.left, narrow);
      expect(left.tanLeft.abs(), greaterThan(0.0));
      expect(
        left.toMatrix(1.0).storage.every((double v) => v.isFinite),
        isTrue,
      );
    });

    test('carries the near and far planes it was given', () {
      final left = StereoViewer.cardboardV2.projectionFor(
        Eye.left,
        phone,
        near: 0.1,
        far: 42.0,
      );
      expect(left.near, 0.1);
      expect(left.far, 42.0);
    });
  });

  group('the two profiles', () {
    test('differ where the published profiles differ', () {
      expect(StereoViewer.cardboardV1.interLensDistance, 0.060);
      expect(StereoViewer.cardboardV2.interLensDistance, 0.064);
      expect(
        StereoViewer.cardboardV1.screenToLensDistance,
        greaterThan(StereoViewer.cardboardV2.screenToLensDistance),
      );
      expect(
        StereoViewer.cardboardV1.outerFieldOfView,
        lessThan(StereoViewer.cardboardV2.outerFieldOfView),
      );
    });

    test('put each eye half the lens distance off centre', () {
      const viewer = StereoViewer.cardboardV2;
      expect(viewer.eyeOffset(Eye.left), -0.032);
      expect(viewer.eyeOffset(Eye.right), 0.032);
    });

    test('copyWith changes one number and keeps the rest', () {
      final tighter = StereoViewer.cardboardV2.copyWith(
        interLensDistance: 0.058,
      );
      expect(tighter.interLensDistance, 0.058);
      expect(
        tighter.screenToLensDistance,
        StereoViewer.cardboardV2.screenToLensDistance,
      );
    });
  });

  group('a screen measured in logical pixels', () {
    test('is an inch for every 160 of them', () {
      final screen = StereoScreen.fromLogicalPixels(width: 800, height: 400);
      expect(screen.width, closeTo(0.127, 1e-9));
      expect(screen.height, closeTo(0.0635, 1e-9));
    });

    test('takes a density when the application knows one', () {
      final screen = StereoScreen.fromLogicalPixels(
        width: 800,
        height: 400,
        dotsPerInch: 200,
      );
      expect(screen.width, closeTo(0.1016, 1e-9));
    });
  });

  group('the rig under a holder', () {
    test('places the eyes at the lenses and aims them through', () {
      final rig = inScene()..applyViewer(StereoViewer.cardboardV2, phone);
      // 1e-6 rather than 1e-9: a world position has been through float32
      // matrices by the time it is read back, the way the rig's own tests
      // already allow for.
      expect(rig.camera(Eye.left).readWorldPosition().x, closeTo(-0.032, 1e-6));
      expect(rig.camera(Eye.right).readWorldPosition().x, closeTo(0.032, 1e-6));

      final left = frustumOf(rig, Eye.left);
      expect(left.tanLeft.abs(), greaterThan(left.tanRight));
    });

    test('keeps the holder rather than falling back to a centred pair', () {
      final rig = inScene()..applyViewer(StereoViewer.cardboardV2, phone);
      final before = frustumOf(rig, Eye.left);
      rig.fitToViewport(width: 2000, height: 1000);
      final after = frustumOf(rig, Eye.left);
      expect(after.tanLeft, before.tanLeft);
      expect(after.tanRight, before.tanRight);
    });

    test("carries the rig's own near and far into the frustum", () {
      final rig = inScene(near: 0.2, far: 90.0)
        ..applyViewer(StereoViewer.cardboardV2, phone);
      final left = frustumOf(rig, Eye.left);
      expect(left.near, 0.2);
      expect(left.far, 90.0);
    });
  });
}
