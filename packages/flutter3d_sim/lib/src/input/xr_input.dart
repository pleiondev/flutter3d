/// What a headset's runtime tracks, as the simulation takes it: poses as
/// external input on the tape, and controllers and hands as sources of the
/// actions a game declares.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show RigidPose;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Assimilation,
        AssimilationContext,
        ExternalStateInput,
        LoopRegistry,
        ReadingKind,
        ReadingQuality,
        Registration;

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

  /// Centre of the palm, OpenXR index 0. WebXR does not track it.
  static const XrHandJoint palm = XrHandJoint._('palm', 0);

  /// Joint between the forearm and the hand, OpenXR index 1.
  static const XrHandJoint wrist = XrHandJoint._('wrist', 1);

  /// Base of the thumb at the wrist (the carpometacarpal joint), index 2.
  static const XrHandJoint thumbMetacarpal = XrHandJoint._(
    'thumbMetacarpal',
    2,
  );

  /// Thumb's knuckle (the metacarpophalangeal joint), index 3.
  static const XrHandJoint thumbProximal = XrHandJoint._('thumbProximal', 3);

  /// Thumb's last joint before the tip (interphalangeal), index 4.
  static const XrHandJoint thumbDistal = XrHandJoint._('thumbDistal', 4);

  /// End of the thumb, past the last joint, index 5.
  static const XrHandJoint thumbTip = XrHandJoint._('thumbTip', 5);

  /// Base of the index finger's metacarpal bone in the palm, index 6.
  static const XrHandJoint indexMetacarpal = XrHandJoint._(
    'indexMetacarpal',
    6,
  );

  /// Index finger's knuckle, where it meets the palm, index 7.
  static const XrHandJoint indexProximal = XrHandJoint._('indexProximal', 7);

  /// Index finger's middle joint, index 8.
  static const XrHandJoint indexIntermediate = XrHandJoint._(
    'indexIntermediate',
    8,
  );

  /// Index finger's joint nearest the tip, index 9.
  static const XrHandJoint indexDistal = XrHandJoint._('indexDistal', 9);

  /// End of the index finger, index 10.
  static const XrHandJoint indexTip = XrHandJoint._('indexTip', 10);

  /// Base of the middle finger's metacarpal bone in the palm, index 11.
  static const XrHandJoint middleMetacarpal = XrHandJoint._(
    'middleMetacarpal',
    11,
  );

  /// Middle finger's knuckle, where it meets the palm, index 12.
  static const XrHandJoint middleProximal = XrHandJoint._('middleProximal', 12);

  /// Middle finger's middle joint, index 13.
  static const XrHandJoint middleIntermediate = XrHandJoint._(
    'middleIntermediate',
    13,
  );

  /// Middle finger's joint nearest the tip, index 14.
  static const XrHandJoint middleDistal = XrHandJoint._('middleDistal', 14);

  /// End of the middle finger, index 15.
  static const XrHandJoint middleTip = XrHandJoint._('middleTip', 15);

  /// Base of the ring finger's metacarpal bone in the palm, index 16.
  static const XrHandJoint ringMetacarpal = XrHandJoint._('ringMetacarpal', 16);

  /// Ring finger's knuckle, where it meets the palm, index 17.
  static const XrHandJoint ringProximal = XrHandJoint._('ringProximal', 17);

  /// Ring finger's middle joint, index 18.
  static const XrHandJoint ringIntermediate = XrHandJoint._(
    'ringIntermediate',
    18,
  );

  /// Ring finger's joint nearest the tip, index 19.
  static const XrHandJoint ringDistal = XrHandJoint._('ringDistal', 19);

  /// End of the ring finger, index 20.
  static const XrHandJoint ringTip = XrHandJoint._('ringTip', 20);

  /// Base of the little finger's metacarpal bone in the palm, index 21.
  static const XrHandJoint littleMetacarpal = XrHandJoint._(
    'littleMetacarpal',
    21,
  );

  /// Little finger's knuckle, where it meets the palm, index 22.
  static const XrHandJoint littleProximal = XrHandJoint._('littleProximal', 22);

  /// Little finger's middle joint, index 23.
  static const XrHandJoint littleIntermediate = XrHandJoint._(
    'littleIntermediate',
    23,
  );

  /// Little finger's joint nearest the tip, index 24.
  static const XrHandJoint littleDistal = XrHandJoint._('littleDistal', 24);

  /// End of the little finger, index 25, the last OpenXR names.
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

/// A [RigidPose] as XR input: the seven numbers an [ExternalStateInput]
/// carries, and back.
///
/// The pose itself is the engine's one ([RigidPose], `flutter3d_foundation`);
/// what XR adds is how it goes on the tape.
extension XrPoseInput on RigidPose {
  /// This pose as input from [source] for the step it is fed to: seven
  /// numbers with no unit (meters and a unit quaternion), predicted for
  /// [displaySeconds] on the runtime's clock, which goes on the tape as the
  /// reading's source time.
  ///
  /// **A predicted reading.** A runtime states where the head will be when
  /// the frame is shown, not where it was measured, so the kind is
  /// [ReadingKind.predicted].
  ExternalStateInput toInput(
    String source, {
    double? displaySeconds,
    ReadingQuality? quality,
  }) => ExternalStateInput(
    source: source,
    value: components,
    sourceSeconds: displaySeconds,
    kind: ReadingKind.predicted,
    quality: quality,
  );

  /// The pose [input] carries. Throws a [DocumentFormatException] for one
  /// that is not seven numbers.
  static RigidPose fromInput(ExternalStateInput input) =>
      RigidPose.fromComponents(input.value);
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
/// feeds each frame's poses as [ExternalStateInput] (see [RigidPose.toInput]);
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

  final Map<String, RigidPose> _latest = <String, RigidPose>{};

  /// The name it is installed under.
  static const String systemName = 'xr.poses';

  /// Adds a table to [loop] as an assimilation under [systemName], and
  /// keeps it as the world's resource from the first step.
  static Registration install(LoopRegistry loop) =>
      loop.addAssimilation(systemName, XrPoses());

  /// The latest pose from [source], or null before the first.
  RigidPose? operator [](String source) => _latest[source];

  /// The head's latest pose, or null before the first.
  RigidPose? get head => _latest[XrPoseSources.head];

  /// Every source that has sent a pose, in the order they first arrived.
  Iterable<String> get sources => _latest.keys;

  @override
  void assimilate(AssimilationContext context) {
    for (final input in context.inputs) {
      if (!XrPoseSources.isPose(input.source) || input.value.length != 7) {
        continue;
      }
      _latest[input.source] = XrPoseInput.fromInput(input);
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

  /// Index-finger trigger: an analogue value from nought to one.
  static const XrControl trigger = XrControl._('trigger');

  /// Grip button under the middle finger, analogue on most controllers.
  static const XrControl squeeze = XrControl._('squeeze');

  /// Thumb stick: two axes and a click.
  static const XrControl thumbstick = XrControl._('thumbstick');

  /// Circular touch surface under the thumb: two axes, touch and click.
  static const XrControl touchpad = XrControl._('touchpad');

  /// Lower face button on the right controller, wire name `a`.
  static const XrControl buttonA = XrControl._('a');

  /// Upper face button on the right controller, wire name `b`.
  static const XrControl buttonB = XrControl._('b');

  /// Lower face button on the left controller, wire name `x`.
  static const XrControl buttonX = XrControl._('x');

  /// Upper face button on the left controller, wire name `y`.
  static const XrControl buttonY = XrControl._('y');

  /// Application menu button; the system button is the runtime's own.
  static const XrControl menu = XrControl._('menu');

  /// Touch-only rest for the thumb beside the face buttons.
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
