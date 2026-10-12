/// Stereo on the XR session: a phone in a holder as one more runtime behind
/// `XrSession`, and a rig that takes its eyes from any runtime's frame.
library;

import 'dart:async';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'
    show
        XrCapability,
        XrFieldOfView,
        XrFrame,
        XrFrameEnd,
        XrSession,
        XrSessionRequest,
        XrSessionState,
        XrSpace,
        XrView;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Portable, RigidPose;
import 'package:flutter3d_sim/flutter3d_sim.dart' show XrPoseSources;

import 'head_tracker.dart';
import 'stereo_rig.dart';
import 'stereo_viewer.dart';

/// A phone in a holder, or held up, as an inline XR session: the head from
/// a [HeadTracker], the eyes [interpupillaryDistance] apart, and each eye's
/// frustum from the holder's lenses ([viewer] over [screen]) or a centered
/// pair [fovY] tall at [aspect] without one.
///
/// **The same boundary as a headset's.** A view, a lesson or a game that
/// drives an `XrSession` drives this one the same way; what differs is
/// that the frames go to Flutter's own surface ([XrCapability.inline]), so
/// there is no swapchain and nothing to compose, and the runtime's clock is
/// the phone's own. Frames come as fast as they are asked for, each
/// predicted for [period] after the last.
final class HolderXrSession extends XrSession {
  /// A session following [tracker].
  HolderXrSession({
    required this.tracker,
    this.viewer,
    this.screen,
    this.interpupillaryDistance = 0.064,
    this.fovY = 1.0,
    this.aspect = 1.0,
    this.period = 1 / 60,
    this.eyeHeight = 1.6,
  });

  /// Where the head is.
  final HeadTracker tracker;

  /// The holder's lenses, or null for a phone with none.
  final StereoViewer? viewer;

  /// The phone's screen, which [viewer]'s frusta are cut to; a 6-inch
  /// screen when null.
  final StereoScreen? screen;

  /// Metres between the eyes, when no [viewer] says where its lenses are.
  final double interpupillaryDistance;

  /// Each eye's vertical field of view without a [viewer], radians.
  final double fovY;

  /// Each eye's width over its height without a [viewer], a unitless
  /// ratio.
  final double aspect;

  /// Seconds between the frames' display times.
  final double period;

  /// How far above the session's floor the head is, meters: a sensor that
  /// knows only a rotation puts the head here.
  final double eyeHeight;

  @override
  String get runtimeName => 'stereo holder';

  @override
  Set<XrCapability> get capabilities => const <XrCapability>{
    XrCapability.inline,
  };

  XrSessionState _state = XrSessionState.idle;
  final StreamController<XrSessionState> _states =
      StreamController<XrSessionState>.broadcast(sync: true);
  int _next = 0;
  XrSpace _space = XrSpace.localFloor;

  @override
  XrSessionState get state => _state;

  @override
  Stream<XrSessionState> get states => _states.stream;

  void _move(XrSessionState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> start(XrSessionRequest request) async {
    requireCapabilities(request);
    _space = request.space;
    await tracker.start();
    _move(XrSessionState.focused);
  }

  @override
  Future<XrFrame> waitFrame() async {
    if (!_state.draws) {
      throw StateError('the session is ${_state.name}: no frames to wait for');
    }
    final index = _next++;
    final head = tracker.pose.value;
    final position = head.position + Vector3(0.0, eyeHeight, 0.0);
    final turn = head.orientation.asRotationMatrix();
    final shown = screen ?? const StereoScreen(width: 0.1324, height: 0.0745);
    return XrFrame(
      index: index,
      predictedDisplayTime: index * period,
      predictedDisplayPeriod: period,
      space: _space,
      poses: <String, RigidPose>{
        XrPoseSources.head: RigidPose(
          position: position,
          orientation: head.orientation,
        ),
      },
      views: <XrView>[
        for (final eye in Eye.both)
          XrView(
            index: eye.index,
            pose: RigidPose(
              position:
                  position +
                  turn.transformed(Vector3(_offsetOf(eye), 0.0, 0.0)),
              orientation: head.orientation,
            ),
            fov: _fovOf(eye, shown),
          ),
      ],
    );
  }

  double _offsetOf(Eye eye) => switch (viewer) {
    final holder? => holder.eyeOffset(eye),
    null => (identical(eye, Eye.left) ? -0.5 : 0.5) * interpupillaryDistance,
  };

  XrFieldOfView _fovOf(Eye eye, StereoScreen shown) {
    final projection = switch (viewer) {
      final holder? => holder.projectionFor(eye, shown),
      null => OffAxisProjection.symmetric(fovY: fovY, aspect: aspect),
    };
    return XrFieldOfView(
      left: Portable.atan(projection.tanLeft),
      right: Portable.atan(projection.tanRight),
      up: Portable.atan(projection.tanUp),
      down: Portable.atan(projection.tanDown),
    );
  }

  /// Nothing to compose: the view drew the frame into Flutter's surface.
  @override
  void endFrame(XrFrameEnd end) {}

  @override
  Future<void> end() async {
    await tracker.stop();
    _move(XrSessionState.ended);
  }
}

/// Taking a rig's eyes from a runtime.
extension StereoRigSession on StereoRig {
  /// Puts the head where [frame] says it is and each eye where its view
  /// is, relative to the head, with the view's own frustum between the
  /// rig's [StereoRig.near] and [StereoRig.far]: what a rig does with a
  /// frame from any `XrSession`, a headset's or a holder's.
  ///
  /// The head is the frame's `xr.head` pose, or the middle of the first
  /// two eyes when the runtime gives none.
  void applyFrame(XrFrame frame) {
    final views = frame.views;
    if (views.isEmpty) return;
    final head =
        frame.poses[XrPoseSources.head] ??
        RigidPose(
          position: views.length > 1
              ? (views[0].pose.position + views[1].pose.position).scaled(0.5)
              : views[0].pose.position,
          orientation: views[0].pose.orientation,
        );
    applyHead(
      RigidPose(orientation: head.orientation, position: head.position),
    );
    final back = head.orientation.asRotationMatrix()..transpose();
    for (final view in views.take(Eye.both.length)) {
      final eye = Eye.both[view.index];
      final offset = back.transformed(view.pose.position - head.position);
      final turn = back.multiplied(view.pose.orientation.asRotationMatrix());
      applyEye(
        eye,
        projection: view.fov.projection(near: near, far: far),
        offset: offset,
        rotation: Quaternion.fromRotation(turn),
      );
    }
  }
}
