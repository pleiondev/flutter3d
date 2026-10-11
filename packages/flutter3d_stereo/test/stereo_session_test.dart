/// Stereo on the XR session: a phone in a holder as an inline runtime, and a
/// rig that takes its eyes from any runtime's frame.
///
///     flutter test test/stereo_session_test.dart
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_app/xr_testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show XrPoseSources;
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_test/flutter_test.dart';

/// A head turned by hand.
final class _Head extends HeadTracker {
  final ValueNotifier<HeadPose> notifier = ValueNotifier<HeadPose>(
    HeadPose.still(),
  );

  int started = 0;

  @override
  ValueListenable<HeadPose> get pose => notifier;

  @override
  Future<void> start() async => started++;
}

StereoRig _rig() {
  final rig = StereoRig();
  Scene().add(rig.stage);
  return rig;
}

void main() {
  test('a phone in a holder is an inline session and nothing more', () async {
    final head = _Head();
    final session = HolderXrSession(
      tracker: head,
      viewer: StereoViewer.cardboardV2,
    );
    await expectLater(
      session.start(const XrSessionRequest()),
      throwsA(isA<UnsupportedCapabilityException>()),
      reason: 'a holder has no immersive mode',
    );
    await session.start(const XrSessionRequest(mode: XrCapability.inline));
    expect(head.started, 1);
    expect(session.state, XrSessionState.focused);
    expect(
      () => session.createSwapchain(
        const XrSwapchainRequest(width: 8, height: 8),
      ),
      throwsA(isA<UnsupportedCapabilityException>()),
    );

    // A quarter turn to the left: the right eye ends up in front of the
    // head, as a person's does.
    head.notifier.value = HeadPose(
      rotation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
      position: Vector3.zero(),
    );
    final frame = await session.waitFrame();
    final next = await session.waitFrame();
    expect(next.predictedDisplayTime - frame.predictedDisplayTime, 1 / 60);
    final right = frame.views[1].pose.position;
    expect(right.y, closeTo(1.6, 1e-6));
    // Mutation: place the eyes without turning them with the head and the
    // right eye stays to the right, at +x.
    expect(right.x, closeTo(0.0, 1e-6));
    expect(right.z, lessThan(0.0));
    // The holder's frustum survives the trip through angles.
    final lens = StereoViewer.cardboardV2.projectionFor(
      Eye.left,
      const StereoScreen(width: 0.1324, height: 0.0745),
    );
    final through = frame.views[0].fov.projection();
    expect(through.tanLeft, closeTo(lens.tanLeft, 1e-12));
    expect(through.tanUp, closeTo(lens.tanUp, 1e-12));
    await session.end();
    expect(session.state, XrSessionState.ended);
  });

  test("a rig takes its eyes from a headset's frame", () async {
    final headset = FakeXrSession();
    await headset.start(const XrSessionRequest());
    final frame = await headset.waitFrame();
    final rig = _rig()..applyFrame(frame);
    for (final view in frame.views) {
      final eye = rig.camera(Eye.both[view.index]);
      final at = eye.readWorldPosition();
      // Mutation: apply the eye's pose without taking the head's off it and
      // each eye sits 1.6 m above where it should.
      expect(at.distanceTo(view.pose.position), lessThan(1e-6));
      final projection = eye.projection as OffAxisProjection;
      expect(projection.tanRight, closeTo(math.tan(view.fov.right), 1e-12));
    }
    expect(
      rig.head.readWorldPosition().distanceTo(
        frame.poses[XrPoseSources.head]!.position,
      ),
      lessThan(1e-6),
    );
    // Without a head pose the head is between the eyes.
    final bare = XrFrame(
      index: 0,
      predictedDisplayTime: 0,
      space: XrSpace.local,
      views: frame.views,
    );
    final other = _rig()..applyFrame(bare);
    expect(other.head.readWorldPosition().x, closeTo(0.0, 1e-6));
  });
}
