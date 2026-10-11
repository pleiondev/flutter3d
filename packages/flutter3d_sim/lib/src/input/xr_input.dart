/// What a headset's runtime tracks, as the simulation takes it: poses as
/// external input on the tape, and controllers and hands as sources of the
/// actions a game declares.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Assimilation,
        AssimilationContext,
        ExternalStateInput,
        LoopRegistry,
        PluginFormatException,
        ReadingKind,
        ReadingQuality,
        Registration;
import 'package:vector_math/vector_math.dart';

import 'game_action.dart';
import 'input_state.dart';

/// Which hand a tracked thing is held in or is.
///
/// **Open.** WebXR names a third, `none`, for a source held in neither (a
/// gaze, a screen tap), and a runtime with a tracked body may name more, so
/// this is a class with constants: [name] is the wire name, [byName] reads
/// it back.
final class XrHand {
  const XrHand._(this.name);

  /// The left hand.
  static const XrHand left = XrHand._('left');

  /// The right hand.
  static const XrHand right = XrHand._('right');

  /// Neither: a source with no hand, a gaze or a tap on a screen.
  static const XrHand none = XrHand._('none');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrHand> values = <XrHand>[left, right, none];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrHand? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'XrHand.$name';
}

/// One joint of a tracked hand, as OpenXR's `XR_EXT_hand_tracking` and
/// WebXR's hand input name them.
///
/// **Open.** The 26 of OpenXR in its order (WebXR has the same less the
/// palm); a runtime that tracks forearm joints adds more, so this is a
/// class with constants.
final class XrHandJoint {
  const XrHandJoint._(this.name, this.index);

  static const XrHandJoint palm = XrHandJoint._('palm', 0);
  static const XrHandJoint wrist = XrHandJoint._('wrist', 1);
  static const XrHandJoint thumbMetacarpal = XrHandJoint._(
    'thumbMetacarpal',
    2,
  );
  static const XrHandJoint thumbProximal = XrHandJoint._('thumbProximal', 3);
  static const XrHandJoint thumbDistal = XrHandJoint._('thumbDistal', 4);
  static const XrHandJoint thumbTip = XrHandJoint._('thumbTip', 5);
  static const XrHandJoint indexMetacarpal = XrHandJoint._(
    'indexMetacarpal',
    6,
  );
  static const XrHandJoint indexProximal = XrHandJoint._('indexProximal', 7);
  static const XrHandJoint indexIntermediate = XrHandJoint._(
    'indexIntermediate',
    8,
  );
  static const XrHandJoint indexDistal = XrHandJoint._('indexDistal', 9);
  static const XrHandJoint indexTip = XrHandJoint._('indexTip', 10);
  static const XrHandJoint middleMetacarpal = XrHandJoint._(
    'middleMetacarpal',
    11,
  );
  static const XrHandJoint middleProximal = XrHandJoint._('middleProximal', 12);
  static const XrHandJoint middleIntermediate = XrHandJoint._(
    'middleIntermediate',
    13,
  );
  static const XrHandJoint middleDistal = XrHandJoint._('middleDistal', 14);
  static const XrHandJoint middleTip = XrHandJoint._('middleTip', 15);
  static const XrHandJoint ringMetacarpal = XrHandJoint._('ringMetacarpal', 16);
  static const XrHandJoint ringProximal = XrHandJoint._('ringProximal', 17);
  static const XrHandJoint ringIntermediate = XrHandJoint._(
    'ringIntermediate',
    18,
  );
  static const XrHandJoint ringDistal = XrHandJoint._('ringDistal', 19);
  static const XrHandJoint ringTip = XrHandJoint._('ringTip', 20);
  static const XrHandJoint littleMetacarpal = XrHandJoint._(
    'littleMetacarpal',
    21,
  );
  static const XrHandJoint littleProximal = XrHandJoint._('littleProximal', 22);
  static const XrHandJoint littleIntermediate = XrHandJoint._(
    'littleIntermediate',
    23,
  );
  static const XrHandJoint littleDistal = XrHandJoint._('littleDistal', 24);
  static const XrHandJoint littleTip = XrHandJoint._('littleTip', 25);

  /// Every value this version names, in OpenXR's order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrHandJoint> values = <XrHandJoint>[
    palm,
    wrist,
    thumbMetacarpal,
    thumbProximal,
    thumbDistal,
    thumbTip,
    indexMetacarpal,
    indexProximal,
    indexIntermediate,
    indexDistal,
    indexTip,
    middleMetacarpal,
    middleProximal,
    middleIntermediate,
    middleDistal,
    middleTip,
    ringMetacarpal,
    ringProximal,
    ringIntermediate,
    ringDistal,
    ringTip,
    littleMetacarpal,
    littleProximal,
    littleIntermediate,
    littleDistal,
    littleTip,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrHandJoint? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  /// Where OpenXR lists it: `XrHandJointEXT`'s value.
  final int index;

  @override
  String toString() => 'XrHandJoint.$name';
}

/// Where a tracked thing is and which way it is turned: a position in
/// meters and an orientation, in the space a runtime reports it in.
///
/// The shape both runtimes hand over (OpenXR's `XrPosef`, WebXR's
/// `XRRigidTransform`). Immutable: the vectors are copied in and out.
final class XrPose {
  /// [position] in meters, turned by [orientation].
  XrPose({required Vector3 position, required Quaternion orientation})
    : _position = position.clone(),
      _orientation = orientation.clone();

  /// At the space's origin, turned nowhere.
  XrPose.identity()
    : _position = Vector3.zero(),
      _orientation = Quaternion.identity();

  final Vector3 _position;
  final Quaternion _orientation;

  /// Where it is, in meters.
  Vector3 get position => _position.clone();

  /// Which way it is turned.
  Quaternion get orientation => _orientation.clone();

  /// The seven numbers an [ExternalStateInput] carries: the position, then
  /// the quaternion as x, y, z, w.
  List<double> get components => <double>[
    _position.x,
    _position.y,
    _position.z,
    _orientation.x,
    _orientation.y,
    _orientation.z,
    _orientation.w,
  ];

  /// The pose [components] wrote. Throws a [PluginFormatException] for a
  /// list that is not seven numbers.
  factory XrPose.fromComponents(List<double> components) {
    if (components.length != 7) {
      throw PluginFormatException(
        'a pose is seven numbers (a position and a quaternion), not '
        '${components.length}',
        components,
      );
    }
    return XrPose(
      position: Vector3(components[0], components[1], components[2]),
      orientation: Quaternion(
        components[3],
        components[4],
        components[5],
        components[6],
      ),
    );
  }

  /// This pose as input from [source] for the step it is fed to: seven
  /// numbers with no unit (meters and a unit quaternion), predicted for
  /// [displayTime] on the runtime's clock, which goes on the tape as the
  /// reading's source time.
  ///
  /// **A predicted reading.** A runtime states where the head will be when
  /// the frame is shown, not where it was measured, so the kind is
  /// [ReadingKind.predicted].
  ExternalStateInput toInput(
    String source, {
    double? displayTime,
    ReadingQuality? quality,
  }) => ExternalStateInput(
    source: source,
    value: components,
    sourceTime: displayTime,
    kind: ReadingKind.predicted,
    quality: quality,
  );

  /// The pose [input] carries. Throws a [PluginFormatException] for one
  /// that is not seven numbers.
  factory XrPose.fromInput(ExternalStateInput input) =>
      XrPose.fromComponents(input.value);

  @override
  bool operator ==(Object other) =>
      other is XrPose &&
      other._position == _position &&
      other._orientation.x == _orientation.x &&
      other._orientation.y == _orientation.y &&
      other._orientation.z == _orientation.z &&
      other._orientation.w == _orientation.w;

  @override
  int get hashCode => Object.hash(
    _position.x,
    _position.y,
    _position.z,
    _orientation.x,
    _orientation.y,
    _orientation.z,
    _orientation.w,
  );

  @override
  String toString() => 'XrPose($_position, $_orientation)';
}

/// The names an XR session's poses go on the tape under, as
/// [ExternalStateInput.source]: `xr.head`, `xr.left.grip`,
/// `xr.right.aim`, `xr.left.hand.indexTip`.
///
/// One spelling, written here once, so a session that feeds them and a
/// system that reads them agree without either knowing the other.
abstract final class XrPoseSources {
  /// What every pose's source starts with.
  static const String prefix = 'xr.';

  /// The head: the viewer's pose, between the eyes.
  static const String head = 'xr.head';

  /// Where [hand]'s controller is held: the grip.
  static String grip(XrHand hand) => 'xr.${hand.name}.grip';

  /// Where [hand]'s controller points: the aim ray's origin and direction.
  static String aim(XrHand hand) => 'xr.${hand.name}.aim';

  /// [joint] of the tracked [hand].
  static String joint(XrHand hand, XrHandJoint joint) =>
      'xr.${hand.name}.hand.${joint.name}';

  /// Whether [source] names an XR pose.
  static bool isPose(String source) => source.startsWith(prefix);
}

/// The poses of the step being run, as they arrived from an XR session:
/// what a system reads where the player's head and hands are.
///
/// **Read from the step's input, so a replay reads the same.** A session
/// feeds each frame's poses as [ExternalStateInput] (see [XrPose.toInput]);
/// they go on the tape with the step that took them, and this assimilation
/// keeps the latest of each source. A system asks the world for it
/// (`world.resource<XrPoses>()`), and a recorded session played back gives
/// it the same poses bit for bit — what lets a server verify a headset's
/// run as it verifies a keyboard's.
///
/// A source that sent nothing this step keeps its last pose: a controller
/// out of view stays where it was last seen. [install] adds it to a loop.
final class XrPoses extends Assimilation {
  /// An empty table.
  XrPoses();

  final Map<String, XrPose> _latest = <String, XrPose>{};

  /// The name it is installed under.
  static const String systemName = 'xr.poses';

  /// Adds a table to [loop] as an assimilation under [systemName], and
  /// keeps it as the world's resource from the first step.
  static Registration install(LoopRegistry loop) =>
      loop.addAssimilation(systemName, XrPoses());

  /// The latest pose from [source], or null before the first.
  XrPose? operator [](String source) => _latest[source];

  /// The head's latest pose, or null before the first.
  XrPose? get head => _latest[XrPoseSources.head];

  /// Every source that has sent a pose, in the order they first arrived.
  Iterable<String> get sources => _latest.keys;

  @override
  void assimilate(AssimilationContext context) {
    for (final input in context.inputs) {
      if (!XrPoseSources.isPose(input.source) || input.value.length != 7) {
        continue;
      }
      _latest[input.source] = XrPose.fromInput(input);
    }
    context.world.setResource<XrPoses>(this);
  }
}

/// A control on a tracked controller or a hand: a trigger, a stick, a face
/// button, a pinch.
///
/// **Open.** The names follow OpenXR's interaction profiles' component
/// paths and WebXR's standard gamepad mapping; a profile with a control
/// these do not name adds one, so this is a class with constants.
final class XrControl {
  const XrControl._(this.name);

  static const XrControl trigger = XrControl._('trigger');
  static const XrControl squeeze = XrControl._('squeeze');
  static const XrControl thumbstick = XrControl._('thumbstick');
  static const XrControl touchpad = XrControl._('touchpad');
  static const XrControl buttonA = XrControl._('a');
  static const XrControl buttonB = XrControl._('b');
  static const XrControl buttonX = XrControl._('x');
  static const XrControl buttonY = XrControl._('y');
  static const XrControl menu = XrControl._('menu');
  static const XrControl thumbrest = XrControl._('thumbrest');

  /// A tracked hand's thumb and index finger together.
  static const XrControl pinch = XrControl._('pinch');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrControl> values = <XrControl>[
    trigger,
    squeeze,
    thumbstick,
    touchpad,
    buttonA,
    buttonB,
    buttonX,
    buttonY,
    menu,
    thumbrest,
    pinch,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrControl? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'XrControl.$name';
}

/// What one [XrControl] reads in one frame: whether it is pressed or
/// touched, how far it is pulled, and where a stick or a pad is.
final class XrControlReading {
  /// A reading; everything at rest by default.
  const XrControlReading({
    this.pressed = false,
    this.touched = false,
    this.value = 0.0,
    this.x = 0.0,
    this.y = 0.0,
  });

  /// Pressed past the runtime's threshold.
  final bool pressed;

  /// Touched, where the control can tell.
  final bool touched;

  /// How far it is pulled, a fraction from nought to one: a trigger's
  /// travel.
  final double value;

  /// A stick's or a pad's first axis, a fraction from −1 (left) to 1
  /// (right).
  final double x;

  /// Its second axis, a fraction from −1 (back, down) to 1 (forward, up).
  final double y;

  @override
  bool operator ==(Object other) =>
      other is XrControlReading &&
      other.pressed == pressed &&
      other.touched == touched &&
      other.value == value &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(pressed, touched, value, x, y);

  @override
  String toString() =>
      'XrControlReading(${pressed ? 'pressed' : 'up'}, $value, $x, $y)';
}

/// Controllers and hands as sources of a game's actions: each control is a
/// source id, `xr:<hand>/<control>`, bound to an [InputAction].
///
/// **The same spelling the action map keeps.** `flutter3d_game`'s
/// `InputSource` is a string with a device prefix (`key:`, `pad:`); an XR
/// control is `InputSource(XrActionSource.sourceId(hand, control))`, so a
/// player's rebinding of the trigger is saved beside the keyboard's and a
/// game reads `use` whichever device pressed it. This class is the path
/// for a program with no action map: a table of its own from ids to
/// actions, written into [input] as a frame's readings arrive.
///
/// A button action is pressed and released on the control's edges and
/// given its travel; an axis action takes the stick's x, or a trigger's
/// travel; a dual-axis action takes the stick.
final class XrActionSource {
  /// Writes into [input] the actions [bindings] names for each source id.
  XrActionSource({
    required this.input,
    required Map<String, InputAction<Object>> bindings,
  }) : bindings = Map<String, InputAction<Object>>.unmodifiable(bindings);

  /// The input the actions are written into.
  final InputState input;

  /// Which action each source id drives.
  final Map<String, InputAction<Object>> bindings;

  /// The source id of [control] on [hand]'s controller or hand.
  static String sourceId(XrHand hand, XrControl control) =>
      'xr:${hand.name}/${control.name}';

  final Set<String> _down = <String>{};

  /// Writes [readings], by source id, into [input]: one frame's controls.
  /// A source with no binding is passed over.
  void apply(Map<String, XrControlReading> readings) {
    for (final MapEntry(key: id, value: reading) in readings.entries) {
      final action = bindings[id];
      switch (action) {
        case null:
          continue;
        case final GameAction button:
          if (reading.pressed && _down.add(id)) input.press(button);
          if (!reading.pressed && _down.remove(id)) input.release(button);
          if (reading.value > 0.0) {
            input.setActionValue(button, reading.value.clamp(0.0, 1.0));
          } else {
            input.clearActionValue(button);
          }
        case final AxisAction axis:
          input.setAxis(
            axis,
            (reading.x != 0.0 ? reading.x : reading.value).clamp(-1.0, 1.0),
          );
        case final DualAxisAction pair:
          input.setDualAxis(pair, reading.x, reading.y);
        default:
          throw UnsupportedError(
            'no XR control drives a ${action.kind.name} action yet '
            '(${action.name} on $id)',
          );
      }
    }
  }

  /// Lets go of every control: a controller put down or lost, a session
  /// that ended.
  void letGo() {
    for (final id in _down) {
      if (bindings[id] case final GameAction button) {
        input
          ..release(button)
          ..clearActionValue(button);
      }
    }
    _down.clear();
    for (final action in bindings.values) {
      switch (action) {
        case final AxisAction axis:
          input.clearAxis(axis);
        case final DualAxisAction pair:
          input.clearDualAxis(pair);
        default:
          break;
      }
    }
  }
}
