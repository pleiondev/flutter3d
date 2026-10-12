/// The one boundary between the engine and an XR runtime: WebXR, OpenXR,
/// ARKit and ARCore, visionOS — 1.0.
///
/// **A seam, frozen before the runtimes behind it.** A headset's runtime
/// paces the frames, says when each will be shown and where the eyes will
/// be, hands out the images it wants drawn into and takes them back as
/// layers. Every runtime does those things in its own words; [XrSession]
/// says them once, so an application, the view and the simulation are
/// written against one shape and a runtime added in a minor is one more
/// subclass. The fake session (`FakeXrSession`) drives the whole of it in
/// tests; the WebXR and OpenXR sessions are their own packages' work.
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show EnvironmentDepth, LightNode, OffAxisProjection, Scene;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Capability, LinearColor, RigidPose, UnsupportedCapabilityException;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ExternalStateInput;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        XrActionSource,
        XrControl,
        XrControlReading,
        XrHand,
        XrPlane,
        XrPoseInput,
        XrPoseSources,
        XrSceneMesh;
import 'package:vector_math/vector_math.dart' show Vector3;

import 'xr_anchor.dart';
import 'xr_layers.dart';
import 'xr_swapchain.dart';

/// What an XR runtime can do: the modes it runs in and the features beside
/// them.
///
/// **Open, under S0.** A runtime of a later minor brings features these do
/// not name (foveation by eye gaze, body tracking, space warp), so this is
/// a class with constants; a session refuses a missing one with
/// [UnsupportedCapabilityException] naming it, as a device refuses a
/// feature.
final class XrCapability extends Capability {
  const XrCapability._(this.name);

  /// A headset's own display, the world drawn all around.
  static const XrCapability immersiveVr = XrCapability._('immersiveVr');

  /// A headset or a phone showing the real world, the virtual drawn over
  /// it.
  static const XrCapability immersiveAr = XrCapability._('immersiveAr');

  /// A view inside the page or the app, posed by the device but drawn into
  /// Flutter's own surface: a phone held up, a phone in a holder.
  static const XrCapability inline = XrCapability._('inline');

  /// Hands tracked joint by joint (`XrHandJoint`).
  static const XrCapability hands = XrCapability._('hands');

  /// Where the eyes look.
  static const XrCapability eyeGaze = XrCapability._('eyeGaze');

  /// The cameras' picture of the room behind the virtual one.
  static const XrCapability passthrough = XrCapability._('passthrough');

  /// Points fixed to the real world that the runtime keeps ([XrAnchor]).
  static const XrCapability anchors = XrCapability._('anchors');

  /// Flat surfaces found in the room ([XrPlane]).
  static const XrCapability planes = XrCapability._('planes');

  /// A mesh of the room ([XrSceneMesh]).
  static const XrCapability sceneMesh = XrCapability._('sceneMesh');

  /// The room's light, measured ([XrLightEstimate]).
  static const XrCapability lightEstimation = XrCapability._('lightEstimation');

  /// How far the real world is, a picture of depth per view
  /// (`EnvironmentDepth`).
  static const XrCapability depthOcclusion = XrCapability._('depthOcclusion');

  /// A controller that vibrates ([XrSession.vibrate]).
  static const XrCapability haptics = XrCapability._('haptics');

  /// A flat layer in the world beside the projection ([XrQuadLayer]).
  static const XrCapability quadLayers = XrCapability._('quadLayers');

  /// A curved layer around the viewer ([XrCylinderLayer]).
  static const XrCapability cylinderLayers = XrCapability._('cylinderLayers');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrCapability> values = <XrCapability>[
    immersiveVr,
    immersiveAr,
    inline,
    hands,
    eyeGaze,
    passthrough,
    anchors,
    planes,
    sceneMesh,
    lightEstimation,
    depthOcclusion,
    haptics,
    quadLayers,
    cylinderLayers,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrCapability? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  @override
  final String name;

  @override
  String get askedBy => '`XrSession.capabilities`';

  @override
  String toString() => 'XrCapability.$name';
}

/// Where a session is in its life, as the runtime says.
///
/// **Open.** OpenXR's lifecycle with WebXR's folded in: a runtime that
/// names another state (OpenXR's `synchronized`, a paused app on a phone)
/// adds one, so this is a class with constants.
final class XrSessionState {
  const XrSessionState._(this.name);

  /// Made and not started.
  static const XrSessionState idle = XrSessionState._('idle');

  /// Started; the runtime has not shown a frame yet.
  static const XrSessionState ready = XrSessionState._('ready');

  /// Frames are shown and the input is somebody else's: a system menu over
  /// the app, WebXR's `visible-blurred`.
  static const XrSessionState visible = XrSessionState._('visible');

  /// Frames are shown and the input is the app's.
  static const XrSessionState focused = XrSessionState._('focused');

  /// The runtime asked the session to stop drawing.
  static const XrSessionState stopping = XrSessionState._('stopping');

  /// Ended: by [XrSession.end], or by the runtime.
  static const XrSessionState ended = XrSessionState._('ended');

  /// The runtime or its device went away; the session cannot go on.
  static const XrSessionState lost = XrSessionState._('lost');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrSessionState> values = <XrSessionState>[
    idle,
    ready,
    visible,
    focused,
    stopping,
    ended,
    lost,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrSessionState? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  /// Whether frames are drawn in this state.
  bool get draws => this == visible || this == focused;

  @override
  String toString() => 'XrSessionState.$name';
}

/// The space a session's poses are stated in: where its origin is and
/// which way is up.
///
/// **Open.** WebXR's and OpenXR's reference spaces; a runtime that names
/// another (a localized map, a space under a vehicle) adds one.
final class XrSpace {
  const XrSpace._(this.name);

  /// At the viewer's eyes, moving with them.
  static const XrSpace viewer = XrSpace._('viewer');

  /// Where the session started, at the eyes' height then.
  static const XrSpace local = XrSpace._('local');

  /// Where the session started, on the floor.
  static const XrSpace localFloor = XrSpace._('localFloor');

  /// A room-scale space with its origin on the floor at the play area's
  /// center.
  static const XrSpace stage = XrSpace._('stage');

  /// A space for walking far from where it began, whose origin may be
  /// moved by the runtime as it learns the world.
  static const XrSpace unbounded = XrSpace._('unbounded');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrSpace> values = <XrSpace>[
    viewer,
    local,
    localFloor,
    stage,
    unbounded,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrSpace? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'XrSpace.$name';
}

/// What a session is asked to start as.
final class XrSessionRequest {
  /// A session in [mode] whose poses are in [space], refused unless the
  /// runtime has every one of [required] and given what it has of
  /// [optional].
  const XrSessionRequest({
    this.mode = XrCapability.immersiveVr,
    this.space = XrSpace.localFloor,
    this.required = const <XrCapability>{},
    this.optional = const <XrCapability>{},
  });

  /// [XrCapability.immersiveVr], [XrCapability.immersiveAr] or
  /// [XrCapability.inline].
  final XrCapability mode;

  /// The space the frames' poses are in.
  final XrSpace space;

  /// What the session is refused without.
  final Set<XrCapability> required;

  /// What it uses where the runtime has it.
  final Set<XrCapability> optional;
}

/// How wide one view sees, as four angles from its own forward axis in
/// radians: OpenXR's `XrFovf`. [left] and [down] are negative for a view
/// that sees past its axis that way, as they are for every headset.
final class XrFieldOfView {
  /// The four angles, in radians.
  const XrFieldOfView({
    required this.left,
    required this.right,
    required this.up,
    required this.down,
  });

  /// Radians from the axis to the left edge, negative to its left.
  final double left;

  /// Radians from the axis to the right edge.
  final double right;

  /// Radians from the axis to the top edge.
  final double up;

  /// Radians from the axis to the bottom edge, negative below it.
  final double down;

  /// The asymmetric frustum these angles make, between [near] and [far]
  /// meters.
  OffAxisProjection projection({double near = 0.05, double far = 500.0}) =>
      OffAxisProjection.fromAngles(
        left: left,
        right: right,
        down: down,
        up: up,
        near: near,
        far: far,
      );

  @override
  String toString() => 'XrFieldOfView($left, $right, $up, $down)';
}

/// One view a runtime wants drawn for a frame: an eye, or a camera of a
/// phone's AR.
final class XrView {
  /// The view at [index], seen from [pose] through [fov].
  const XrView({required this.index, required this.pose, required this.fov});

  /// Which of the frame's views it is, from nought: the left eye before the
  /// right. Its layer in the projection layer's image.
  final int index;

  /// Where the eye is, in the frame's space.
  final RigidPose pose;

  /// How wide it sees.
  final XrFieldOfView fov;
}

/// A controller or a tracked hand, as one frame reads it.
final class XrInputSource {
  /// A source in [hand], read as [controls].
  const XrInputSource({
    required this.hand,
    this.profiles = const <String>[],
    this.controls = const <XrControl, XrControlReading>{},
    this.isHand = false,
  });

  /// Which hand holds it, or is it.
  final XrHand hand;

  /// The interaction profiles the runtime matched, most specific first:
  /// WebXR's `profiles`, OpenXR's interaction profile path's last part
  /// (`oculus-touch-v3`, `generic-trigger-squeeze-thumbstick`).
  final List<String> profiles;

  /// What each control reads this frame.
  final Map<XrControl, XrControlReading> controls;

  /// Whether this is a tracked hand rather than a held controller.
  final bool isHand;
}

/// The room's light as the runtime measured it, for the frame's
/// environment.
final class XrLightEstimate {
  /// Light from all around in [ambient] at [ambientIntensity], with a main
  /// light from [direction] at [intensity] in [color], when the runtime
  /// finds one.
  XrLightEstimate({
    required this.ambient,
    required this.ambientIntensity,
    Vector3? direction,
    this.color,
    this.intensity,
  }) : _direction = direction?.clone();

  /// The color of the light from all around, linear: what the runtime's
  /// spherical harmonics or ambient color amount to.
  final LinearColor ambient;

  /// How much light comes from all around, in lux.
  final double ambientIntensity;

  final Vector3? _direction;

  /// Where the main light comes from, a unit vector pointing to it; null
  /// when there is none.
  Vector3? get direction => _direction?.clone();

  /// The main light's color, linear; null when there is none.
  final LinearColor? color;

  /// The main light's illuminance, in lux; null when there is none.
  final double? intensity;

  /// Lights [scene] as the room is lit: its ambient color and intensity,
  /// and [main], when given and the runtime found a main light, turned to
  /// shine from [direction] in [color] at [intensity].
  void applyTo(Scene scene, {LightNode? main}) {
    scene
      ..ambientColor = ambient
      ..ambientIntensity = ambientIntensity;
    final from = _direction;
    if (main == null || from == null) return;
    main
      ..color = color ?? main.color
      ..intensity = intensity ?? main.intensity
      ..lookAt(main.readWorldPosition() - from);
  }
}

/// One frame of a session: when it will be shown, where the eyes and the
/// hands will be, and what the room looks like.
///
/// Made by the runtime in [XrSession.waitFrame]; the engine reads it and
/// answers with an [XrFrameEnd].
final class XrFrame {
  /// The frame [index], shown at [predictedDisplayTime].
  XrFrame({
    required this.index,
    required this.predictedDisplayTime,
    required this.space,
    required List<XrView> views,
    this.predictedDisplayPeriod = 1 / 90,
    this.shouldRender = true,
    Map<String, RigidPose> poses = const <String, RigidPose>{},
    List<XrInputSource> inputs = const <XrInputSource>[],
    List<XrPlane> planes = const <XrPlane>[],
    List<String> lostPlanes = const <String>[],
    List<XrSceneMesh> meshes = const <XrSceneMesh>[],
    this.light,
    this.depth,
  }) : views = List<XrView>.unmodifiable(views),
       poses = Map<String, RigidPose>.unmodifiable(poses),
       inputs = List<XrInputSource>.unmodifiable(inputs),
       planes = List<XrPlane>.unmodifiable(planes),
       lostPlanes = List<String>.unmodifiable(lostPlanes),
       meshes = List<XrSceneMesh>.unmodifiable(meshes);

  /// Counted from the session's first frame.
  final int index;

  /// When the runtime will show it, seconds on the runtime's clock: what
  /// the loop's `DisplayTime` is told.
  final double predictedDisplayTime;

  /// The runtime's frame period, seconds: a 90 Hz headset's is 1/90.
  final double predictedDisplayPeriod;

  /// Whether the runtime will show what is drawn; false while the session
  /// is visible but hidden, when a frame is ended with no layers.
  final bool shouldRender;

  /// The space [views] and [poses] are in.
  final XrSpace space;

  /// The views to draw, in order.
  final List<XrView> views;

  /// The tracked poses of this frame, by their tape source names
  /// (`XrPoseSources`): the head, each controller's grip and aim, each
  /// hand's joints.
  final Map<String, RigidPose> poses;

  /// The controllers and hands, read for this frame.
  final List<XrInputSource> inputs;

  /// Planes found or changed since the last frame.
  final List<XrPlane> planes;

  /// The ids of planes no longer tracked.
  final List<String> lostPlanes;

  /// Scene meshes made or changed since the last frame.
  final List<XrSceneMesh> meshes;

  /// The room's light, when the runtime measured it this frame.
  final XrLightEstimate? light;

  /// How far the real world is, when the runtime measured it this frame.
  final EnvironmentDepth? depth;

  /// This frame as the simulation's input for the step that takes it:
  /// every pose, plane and mesh, with the display time as their source
  /// time. What goes on the tape, so a session replays bit for bit.
  List<ExternalStateInput> toInputs() => <ExternalStateInput>[
    for (final MapEntry(key: source, value: pose) in poses.entries)
      if (XrPoseSources.isPose(source))
        pose.toInput(source, displayTime: predictedDisplayTime),
    for (final plane in planes)
      plane.toInput(displayTime: predictedDisplayTime),
    for (final id in lostPlanes)
      XrPlane.lost(id, displayTime: predictedDisplayTime),
    for (final mesh in meshes) mesh.toInput(displayTime: predictedDisplayTime),
  ];

  /// What each control reads this frame, by the source id an action map
  /// binds it under (`XrActionSource.sourceId`).
  Map<String, XrControlReading> get controlReadings =>
      <String, XrControlReading>{
        for (final source in inputs)
          for (final MapEntry(key: control, value: reading)
              in source.controls.entries)
            XrActionSource.sourceId(source.hand, control): reading,
      };
}

/// What the engine hands back for a frame: the layers the runtime
/// composes, in order, the first at the back.
final class XrFrameEnd {
  /// [frame] ended with [layers].
  XrFrameEnd({required this.frame, List<XrLayer> layers = const <XrLayer>[]})
    : layers = List<XrLayer>.unmodifiable(layers);

  /// The frame this ends.
  final XrFrame frame;

  /// What is shown, back to front: none for a frame not drawn.
  final List<XrLayer> layers;
}

/// A pulse a controller plays.
final class XrHaptic {
  /// [hand]'s controller vibrating at [amplitude] (0 to 1) for [duration],
  /// at [frequency] hertz or the runtime's own when null.
  const XrHaptic({
    required this.hand,
    this.amplitude = 1.0,
    this.duration = const Duration(milliseconds: 50),
    this.frequency,
  });

  /// Whose controller.
  final XrHand hand;

  /// How strong, a fraction from nought to one.
  final double amplitude;

  /// How long.
  final Duration duration;

  /// Hertz, or null for the runtime's own.
  final double? frequency;
}

/// The engine's one boundary to an XR runtime.
///
/// **A runtime extends this** — `WebXrSession`, `OpenXrSession` and the
/// test's `FakeXrSession` — and the engine drives it: [start] with what it
/// asks for, then each frame [waitFrame] for when it will be shown and
/// where everything will be, draw, and [endFrame] with the layers to
/// compose. Every member that is a feature (anchors, haptics, layers
/// beyond the projection) has a body that refuses it by name, so a session
/// written against 1.0 compiles against every 1.x, and a feature a minor
/// adds arrives the same way.
///
/// **Each hook takes one object.** A frame, a request, an end: each can
/// gain fields in a minor, where a list of parameters could not.
abstract base class XrSession {
  /// A session; the runtime opens nothing until [start].
  XrSession();

  /// Who the session is, as a refusal names it: `WebXR`, `OpenXR (Quest)`.
  String get runtimeName;

  /// What the runtime can do, asked before [start].
  Set<XrCapability> get capabilities;

  /// Where the session is in its life.
  XrSessionState get state;

  /// [state] as it changes.
  Stream<XrSessionState> get states;

  /// Starts the session as [request] asks. Throws an
  /// [UnsupportedCapabilityException] naming the first capability of
  /// `request.required` (or its mode) the runtime does not have — see
  /// [requireCapabilities].
  Future<void> start(XrSessionRequest request);

  /// Waits for the runtime's next frame and says what it will be: the
  /// runtime's pace, so it completes when the runtime is ready for the
  /// frame to be drawn.
  Future<XrFrame> waitFrame();

  /// Hands the runtime what was drawn for `end.frame`, as layers.
  void endFrame(XrFrameEnd end);

  /// Ends the session; [state] becomes [XrSessionState.ended].
  Future<void> end();

  /// A swapchain of images the runtime shows, of the shape [request] asks:
  /// what the projection layer is drawn into. Refused by default, by a
  /// session that draws into Flutter's own surface ([XrCapability.inline]).
  XrSwapchain createSwapchain(XrSwapchainRequest request) =>
      throw UnsupportedCapabilityException(
        XrCapability.immersiveVr,
        backend: runtimeName,
        reason: 'an inline session draws into the view, not into images',
      );

  /// Fixes a point to the real world, as [request] asks. Refused by
  /// default ([XrCapability.anchors]).
  Future<XrAnchor> placeAnchor(XrAnchorRequest request) =>
      Future<XrAnchor>.error(refusal(XrCapability.anchors));

  /// The anchor kept under [id] in an earlier session, where the runtime
  /// persists anchors; null when it does not know the id. Refused by
  /// default ([XrCapability.anchors]).
  Future<XrAnchor?> restoreAnchor(String id) =>
      Future<XrAnchor?>.error(refusal(XrCapability.anchors));

  /// Plays [haptic] on a controller. Refused by default
  /// ([XrCapability.haptics]).
  void vibrate(XrHaptic haptic) => throw refusal(XrCapability.haptics);

  /// The refusal of [capability] by this runtime.
  UnsupportedCapabilityException refusal(XrCapability capability) =>
      UnsupportedCapabilityException(capability, backend: runtimeName);

  /// Throws the refusal of the first of [request]'s mode and required
  /// capabilities this runtime lacks; what [start] calls first.
  void requireCapabilities(XrSessionRequest request) {
    for (final capability in <XrCapability>[
      request.mode,
      ...request.required,
    ]) {
      if (!capabilities.contains(capability)) throw refusal(capability);
    }
  }
}
