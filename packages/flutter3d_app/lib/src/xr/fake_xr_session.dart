/// A runtime for tests: an XR session with no headset behind it, whose
/// frames a test scripts and whose layers it reads back.
library;

import 'dart:async';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show RigidPose;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show XrPoseSources;
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'xr_anchor.dart';
import 'xr_session.dart';
import 'xr_swapchain.dart';

/// An [XrSession] with nothing behind it: frames come when asked, at a
/// fixed period, from [frameAt]; what the engine ends them with is kept in
/// [ended].
///
/// **Every seam of the contract, driven from a test.** Its capabilities are
/// what the test gives it, so a refusal is tested by leaving one out; its
/// frames carry whatever poses, inputs, planes, light and depth [frameAt]
/// puts in them; its swapchain is an array texture on the engine's own
/// device; its anchors are kept in memory under ids it makes, and outlive
/// a session the way a runtime's persisted anchors do when the same store
/// is handed to the next one.
final class FakeXrSession extends XrSession {
  /// A session reporting [capabilities], whose frame `n` is shown at
  /// [startTime] plus `n` times [period] and is made by [frameAt] (two eyes
  /// 64 mm apart at 1.6 m, looking down −z, by default).
  FakeXrSession({
    Set<XrCapability>? capabilities,
    this.period = 1 / 90,
    this.startTime = 100.0,
    XrFrame Function(FakeXrSession session, int index)? frameAt,
    Map<String, XrAnchor>? anchorStore,
  }) : capabilities = Set<XrCapability>.unmodifiable(
         capabilities ?? XrCapability.values.toSet(),
       ),
       frameAt = frameAt ?? standardFrame,
       anchorStore = anchorStore ?? <String, XrAnchor>{};

  @override
  String get runtimeName => 'fake XR runtime';

  @override
  final Set<XrCapability> capabilities;

  /// Seconds between frames.
  final double period;

  /// The display time of the first frame, seconds.
  final double startTime;

  /// What frame [index] is.
  final XrFrame Function(FakeXrSession session, int index) frameAt;

  /// The anchors the runtime keeps, by id: hand the same map to the next
  /// session to restore them there.
  final Map<String, XrAnchor> anchorStore;

  XrSessionState _state = XrSessionState.idle;
  final StreamController<XrSessionState> _states =
      StreamController<XrSessionState>.broadcast(sync: true);

  /// What the session was started as; null before [start].
  XrSessionRequest? get request => _request;
  XrSessionRequest? _request;

  /// How many frames [waitFrame] has handed out: what a test reads to see
  /// the engine asked for no frame it did not end ([ended]).
  int get framesWaited => _next;
  int _next = 0;

  /// Every frame the engine ended, in order.
  final List<XrFrameEnd> ended = <XrFrameEnd>[];

  /// Every pulse played.
  final List<XrHaptic> pulses = <XrHaptic>[];

  /// The swapchains made.
  final List<FakeXrSwapchain> swapchains = <FakeXrSwapchain>[];

  @override
  XrSessionState get state => _state;

  @override
  Stream<XrSessionState> get states => _states.stream;

  /// Moves the session to [state], as a runtime does on its own: a system
  /// menu over the app ([XrSessionState.visible]), the headset taken off
  /// ([XrSessionState.lost]).
  void moveTo(XrSessionState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> start(XrSessionRequest request) async {
    requireCapabilities(request);
    _request = request;
    moveTo(XrSessionState.ready);
    moveTo(XrSessionState.focused);
  }

  @override
  Future<XrFrame> waitFrame() async {
    if (!_state.draws) {
      throw StateError('the session is ${_state.name}: no frames to wait for');
    }
    return frameAt(this, _next++);
  }

  @override
  void endFrame(XrFrameEnd end) => ended.add(end);

  @override
  Future<void> end() async => moveTo(XrSessionState.ended);

  @override
  XrSwapchain createSwapchain(XrSwapchainRequest request) {
    final swapchain = FakeXrSwapchain(request.descriptor);
    swapchains.add(swapchain);
    return swapchain;
  }

  @override
  Future<XrAnchor> placeAnchor(XrAnchorRequest request) async {
    if (!capabilities.contains(XrCapability.anchors)) {
      throw refusal(XrCapability.anchors);
    }
    final anchor = XrAnchor(
      id: 'fake-anchor-${anchorStore.length + 1}',
      pose: request.pose,
      space: request.space,
      geo: request.geo,
    );
    anchorStore[anchor.id] = anchor;
    return anchor;
  }

  @override
  Future<XrAnchor?> restoreAnchor(String id) async {
    if (!capabilities.contains(XrCapability.anchors)) {
      throw refusal(XrCapability.anchors);
    }
    return anchorStore[id];
  }

  @override
  void vibrate(XrHaptic haptic) {
    if (!capabilities.contains(XrCapability.haptics)) {
      throw refusal(XrCapability.haptics);
    }
    pulses.add(haptic);
  }

  /// The default frame [index] of [session]: a head at 1.6 m looking down
  /// −z, two eyes 64 mm apart with a headset's asymmetric angles, in the
  /// session's space.
  static XrFrame standardFrame(FakeXrSession session, int index) {
    final head = RigidPose(
      position: Vector3(0.0, 1.6, 0.0),
      orientation: Quaternion.identity(),
    );
    return XrFrame(
      index: index,
      predictedDisplayTime: session.startTime + index * session.period,
      predictedDisplayPeriod: session.period,
      space: session.request?.space ?? XrSpace.localFloor,
      poses: <String, RigidPose>{XrPoseSources.head: head},
      views: <XrView>[
        for (final (i, x) in <(int, double)>[(0, -0.032), (1, 0.032)])
          XrView(
            index: i,
            pose: RigidPose(
              position: Vector3(x, 1.6, 0.0),
              orientation: Quaternion.identity(),
            ),
            fov: i == 0
                ? const XrFieldOfView(
                    left: -0.94,
                    right: 0.79,
                    up: 0.87,
                    down: -0.96,
                  )
                : const XrFieldOfView(
                    left: -0.79,
                    right: 0.94,
                    up: 0.87,
                    down: -0.96,
                  ),
          ),
      ],
    );
  }
}

/// The fake runtime's images: one array texture on the device that draws,
/// made at the first [acquire], counted in and out.
final class FakeXrSwapchain extends XrSwapchain {
  /// Images shaped like [descriptor].
  FakeXrSwapchain(this.descriptor);

  @override
  final TextureDescriptor descriptor;

  TextureHandle? _image;
  GraphicsDevice? _device;

  /// How many times [acquire] has run.
  int get acquired => _acquired;
  int _acquired = 0;

  /// How many times [release] has run.
  int get released => _released;
  int _released = 0;

  /// The image, once acquired.
  TextureHandle? get image => _image;

  @override
  TextureHandle acquire(GraphicsDevice device) {
    if (_acquired != _released) {
      throw StateError('an image is acquired twice without a release');
    }
    _acquired++;
    _device = device;
    return _image ??= device.createTexture(descriptor);
  }

  @override
  Future<void> release() async {
    if (_acquired == _released) {
      throw StateError('an image is released that was not acquired');
    }
    _released++;
  }

  @override
  void dispose() {
    final image = _image;
    if (image != null) _device?.releaseTexture(image);
    _image = null;
  }
}
