import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'bindings.dart';

/// How an analogue source is shaped on its way to an action: a dead zone, a
/// sensitivity, and which way is up.
///
/// **On the binding, not the action**, because each of the three is about a
/// device. A worn stick drifts and wants a dead zone the mouse has no use
/// for; a player inverts the pad's vertical look and not the mouse's, or the
/// other way round. The simulation never sees any of it — it reads the
/// action's value, and a tape records that value, shaped — so a replay plays
/// the same whatever the watching player has turned.
final class AxisSettings {
  const AxisSettings({
    this.deadZone = 0.0,
    this.sensitivity = 1.0,
    this.invertX = false,
    this.invertY = false,
  }) : assert(deadZone >= 0.0 && deadZone < 1.0, 'a dead zone is a fraction');

  factory AxisSettings.fromJson(Map<String, Object?> json) => AxisSettings(
    deadZone: ((json['deadZone'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 0.95),
    sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 1.0,
    invertX: json['invertX'] == true,
    invertY: json['invertY'] == true,
  );

  /// Leaves every value as it came.
  static const AxisSettings identity = AxisSettings();

  /// The fraction of travel, from rest, that reads as rest. The rest of the
  /// travel is stretched back over the whole range, so a stick just past the
  /// dead zone reads just past nought rather than jumping to it.
  final double deadZone;

  /// A factor on the value after the dead zone.
  final double sensitivity;

  /// Whether the first number's sign is turned over — the only number of a
  /// one-axis source.
  final bool invertX;

  /// Whether the second number's sign is turned over: inverted vertical look.
  final bool invertY;

  bool get isIdentity =>
      deadZone == 0.0 && sensitivity == 1.0 && !invertX && !invertY;

  /// One axis, clamped to `[-1, 1]`.
  double shape(double value) {
    if (isIdentity) return value;
    final magnitude = value.abs();
    final live = magnitude <= deadZone
        ? 0.0
        : (magnitude - deadZone) / (1.0 - deadZone);
    final shaped = (value < 0.0 ? -live : live) * sensitivity;
    return (invertX ? -shaped : shaped).clamp(-1.0, 1.0);
  }

  /// A stick: the dead zone is round, measured on the pair's length, so a
  /// diagonal is not cut where a single axis would not be.
  (double, double) shapePair(double x, double y) {
    if (isIdentity) return (x, y);
    final length = math.sqrt(x * x + y * y);
    if (length <= deadZone || length == 0.0) return (0.0, 0.0);
    final scale = (length - deadZone) / (1.0 - deadZone) / length * sensitivity;
    final sx = x * scale;
    final sy = y * scale;
    return (invertX ? -sx : sx, invertY ? -sy : sy);
  }

  /// Motion since the last step — a mouse's — which has no rest to cut and
  /// no range to clamp to: sensitivity and invert only.
  (double, double) shapeDelta(double dx, double dy) {
    if (isIdentity) return (dx, dy);
    final sx = dx * sensitivity;
    final sy = dy * sensitivity;
    return (invertX ? -sx : sx, invertY ? -sy : sy);
  }

  AxisSettings copyWith({
    double? deadZone,
    double? sensitivity,
    bool? invertX,
    bool? invertY,
  }) => AxisSettings(
    deadZone: deadZone ?? this.deadZone,
    sensitivity: sensitivity ?? this.sensitivity,
    invertX: invertX ?? this.invertX,
    invertY: invertY ?? this.invertY,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (deadZone != 0.0) 'deadZone': deadZone,
    if (sensitivity != 1.0) 'sensitivity': sensitivity,
    if (invertX) 'invertX': true,
    if (invertY) 'invertY': true,
  };

  @override
  bool operator ==(Object other) =>
      other is AxisSettings &&
      other.deadZone == deadZone &&
      other.sensitivity == sensitivity &&
      other.invertX == invertX &&
      other.invertY == invertY;

  @override
  int get hashCode => Object.hash(deadZone, sensitivity, invertX, invertY);
}

/// Which part of a composite binding a source drives.
enum CompositePart {
  /// The minus end of an [AxisComposite].
  negative,

  /// The plus end of an [AxisComposite].
  positive,

  /// The four directions of a [DualAxisComposite].
  up,
  down,
  left,
  right,
}

/// One way a device reaches an action.
///
/// **Sealed: five shapes, each one a thing a device can actually do.** The
/// devices and the rebinding screen answer every shape, and a shape one of
/// them did not read would be a control that silently does nothing; a sixth
/// shape waits for a major.
///
/// * [ButtonBinding] — a key, a mouse button, a pad button, held or not;
/// * [AxisBinding] — one analogue number, a trigger or a stick's one axis;
/// * [AxisComposite] — two buttons as one axis, `I`/`K` for a crane's neck;
/// * [DualAxisBinding] — a pair, a whole stick or the mouse's motion;
/// * [DualAxisComposite] — four buttons as a pair, `WASD`.
///
/// Dead zone, sensitivity and invert are on the two analogue shapes — see
/// [AxisSettings].
sealed class ActionBinding {
  const ActionBinding();

  /// Reads one binding written by [toJson], or null for a shape this build
  /// does not know — which the [ActionMap] keeps rather than drops.
  static ActionBinding? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final name = json['action'];
    if (name is! String) return null;
    InputSource at(String key) => switch (json[key]) {
      final String id => InputSource(id),
      _ => InputSource.none,
    };
    AxisSettings tuning() => switch (json['tuning']) {
      final Map<String, Object?> tuning => AxisSettings.fromJson(tuning),
      _ => AxisSettings.identity,
    };
    return switch (json['kind']) {
      'button' => ButtonBinding(GameAction(name), at('source')),
      'axis' => AxisBinding(AxisAction(name), at('source'), tuning: tuning()),
      'axisComposite' => AxisComposite(
        AxisAction(name),
        negative: at('negative'),
        positive: at('positive'),
      ),
      'dualAxis' => DualAxisBinding(
        DualAxisAction(name, isDelta: json['delta'] == true),
        at('source'),
        tuning: tuning(),
      ),
      'dualAxisComposite' => DualAxisComposite(
        DualAxisAction(name),
        up: at('up'),
        down: at('down'),
        left: at('left'),
        right: at('right'),
      ),
      _ => null,
    };
  }

  InputAction<Object> get action;

  /// Every source this binding listens to, [InputSource.none] left out.
  List<InputSource> get sources;

  /// The source on [part], for a composite; the one source otherwise.
  InputSource sourceAt(CompositePart? part);

  /// This binding with [source] on [part] (or as its one source).
  ActionBinding withSource(InputSource source, CompositePart? part);

  /// The part [source] drives, for a composite; null otherwise.
  CompositePart? partOf(InputSource source) => null;

  Map<String, Object?> toJson();
}

/// A button held or not: a key, a mouse button, a pad button.
///
/// An [ActionMap] keeps these in its [ActionMap.buttons] table, the one the
/// keyboard and the pad have always read.
final class ButtonBinding extends ActionBinding {
  const ButtonBinding(this.action, this.source);

  @override
  final GameAction action;
  final InputSource source;

  @override
  List<InputSource> get sources => source == InputSource.none
      ? const <InputSource>[]
      : <InputSource>[source];

  @override
  InputSource sourceAt(CompositePart? part) => source;

  @override
  ButtonBinding withSource(InputSource source, CompositePart? part) =>
      ButtonBinding(action, source);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'button',
    'action': action.name,
    'source': source.id,
  };
}

/// One analogue number on an [AxisAction]: a trigger, one axis of a stick,
/// a band under a thumb.
final class AxisBinding extends ActionBinding {
  const AxisBinding(
    this.action,
    this.source, {
    this.tuning = AxisSettings.identity,
  });

  @override
  final AxisAction action;
  final InputSource source;
  final AxisSettings tuning;

  @override
  List<InputSource> get sources => source == InputSource.none
      ? const <InputSource>[]
      : <InputSource>[source];

  @override
  InputSource sourceAt(CompositePart? part) => source;

  @override
  AxisBinding withSource(InputSource source, CompositePart? part) =>
      AxisBinding(action, source, tuning: tuning);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'axis',
    'action': action.name,
    'source': source.id,
    if (!tuning.isIdentity) 'tuning': tuning.toJson(),
  };
}

/// Two buttons as one [AxisAction]: the axis is one while [positive] is
/// held, minus one while [negative] is, and nought for both or neither.
final class AxisComposite extends ActionBinding {
  const AxisComposite(
    this.action, {
    required this.negative,
    required this.positive,
  });

  @override
  final AxisAction action;
  final InputSource negative;
  final InputSource positive;

  @override
  List<InputSource> get sources => <InputSource>[
    for (final source in <InputSource>[negative, positive])
      if (source != InputSource.none) source,
  ];

  @override
  InputSource sourceAt(CompositePart? part) =>
      part == CompositePart.negative ? negative : positive;

  @override
  AxisComposite withSource(InputSource source, CompositePart? part) =>
      AxisComposite(
        action,
        negative: part == CompositePart.negative ? source : negative,
        positive: part == CompositePart.negative ? positive : source,
      );

  @override
  CompositePart? partOf(InputSource source) => source == negative
      ? CompositePart.negative
      : source == positive
      ? CompositePart.positive
      : null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'axisComposite',
    'action': action.name,
    'negative': negative.id,
    'positive': positive.id,
  };
}

/// A pair of analogue numbers on a [DualAxisAction]: a whole stick, or the
/// mouse's motion for a delta action such as [DualAxisAction.look].
final class DualAxisBinding extends ActionBinding {
  const DualAxisBinding(
    this.action,
    this.source, {
    this.tuning = AxisSettings.identity,
  });

  @override
  final DualAxisAction action;
  final InputSource source;
  final AxisSettings tuning;

  @override
  List<InputSource> get sources => source == InputSource.none
      ? const <InputSource>[]
      : <InputSource>[source];

  @override
  InputSource sourceAt(CompositePart? part) => source;

  @override
  DualAxisBinding withSource(InputSource source, CompositePart? part) =>
      DualAxisBinding(action, source, tuning: tuning);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'dualAxis',
    'action': action.name,
    if (action.isDelta) 'delta': true,
    'source': source.id,
    if (!tuning.isIdentity) 'tuning': tuning.toJson(),
  };
}

/// Four buttons as one [DualAxisAction] — `WASD` as a direction, never
/// longer than one, so a diagonal is no faster than straight ahead.
final class DualAxisComposite extends ActionBinding {
  const DualAxisComposite(
    this.action, {
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  @override
  final DualAxisAction action;
  final InputSource up;
  final InputSource down;
  final InputSource left;
  final InputSource right;

  @override
  List<InputSource> get sources => <InputSource>[
    for (final source in <InputSource>[up, down, left, right])
      if (source != InputSource.none) source,
  ];

  @override
  InputSource sourceAt(CompositePart? part) => switch (part) {
    CompositePart.down => down,
    CompositePart.left => left,
    CompositePart.right => right,
    _ => up,
  };

  @override
  DualAxisComposite withSource(InputSource source, CompositePart? part) =>
      DualAxisComposite(
        action,
        up: part == CompositePart.up || part == null ? source : up,
        down: part == CompositePart.down ? source : down,
        left: part == CompositePart.left ? source : left,
        right: part == CompositePart.right ? source : right,
      );

  @override
  CompositePart? partOf(InputSource source) => source == up
      ? CompositePart.up
      : source == down
      ? CompositePart.down
      : source == left
      ? CompositePart.left
      : source == right
      ? CompositePart.right
      : null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'dualAxisComposite',
    'action': action.name,
    'up': up.id,
    'down': down.id,
    'left': left.id,
    'right': right.id,
  };
}

/// A source that something else already uses, found by a rebind.
final class BindingConflict {
  const BindingConflict({
    required this.source,
    required this.action,
    this.part,
  });

  final InputSource source;

  /// What [source] was on before.
  final InputAction<Object> action;

  /// Which part of a composite on [action] it drove, if it was one.
  final CompositePart? part;

  @override
  bool operator ==(Object other) =>
      other is BindingConflict &&
      other.source == source &&
      other.action == action &&
      other.part == part;

  @override
  int get hashCode => Object.hash(source, action, part);

  @override
  String toString() =>
      'BindingConflict(${source.id} on ${action.name}'
      '${part == null ? '' : ' ${part!.name}'})';
}

/// What to do when a rebind meets a source already in use.
enum ConflictPolicy {
  /// Take it: the other action loses the source. What a rebinding screen
  /// has always done, and the default.
  steal,

  /// Trade: the other action gets the source the rebound one gave up, so
  /// nothing is left unbound. Takes it, as [steal], when there was nothing
  /// to give.
  swap,

  /// Change nothing, and say which actions are in the way.
  refuse,
}

/// What [ActionMap.rebind] did.
final class RebindOutcome {
  const RebindOutcome({required this.applied, required this.conflicts});

  /// Whether the map changed. False only under [ConflictPolicy.refuse].
  final bool applied;

  /// Who else had the source, before the rebind — so a screen can say "`J`
  /// was jump's; jump is now on nothing".
  final List<BindingConflict> conflicts;
}

/// The actions a game declares and every device's way to each: a game's
/// controls, as one object a player edits and a file keeps.
///
/// ## What it holds
///
/// * [actions] — the declared [ActionSet], which says what kinds exist and
///   what a rebinding screen lists;
/// * [buttons] — the button table, the same [Bindings] the keyboard and the
///   pad have always read. **Shared, not copied**: a game hands this object to
///   `DesktopInput` and `PadInput`, and a rebind here takes effect on the next
///   key press;
/// * [axisBindings] — everything that is not a button: composites, analogue
///   axes and sticks, each with its [AxisSettings]. `DesktopInput` and `PadInput`
///   read these through an `ActionInput` when they are given the map.
///
/// ## Saved as versioned JSON
///
/// [toJson] writes the format envelope (`format`, `version`, `requires`,
/// `generator`), then `set`, `buttons` and `axes`, then any key a later
/// build wrote that this one did not read. [ActionMap.fromJson]
/// reads every version up to [formatVersion], and also the table a build
/// before action maps saved — a bare [Bindings.toJson] — as the buttons, with
/// the defaults' axes beside it. A binding of a shape this build does not
/// know is kept and written back, for the reason [Bindings] keeps an action
/// it does not know.
final class ActionMap extends FormatDocument {
  ActionMap({
    required this.actions,
    Bindings? buttons,
    Iterable<ActionBinding> axes = const <ActionBinding>[],
    super.unknown,
  }) : buttons = buttons ?? Bindings() {
    for (final binding in axes) {
      bind(binding);
    }
  }

  /// Reads what [toJson] wrote, at any version up to [formatVersion], or a
  /// bare button table from before there were action maps.
  ///
  /// [defaults] supplies what the document does not say: the axes of an old
  /// table that had none, and everything of a document that is not a map's
  /// at all. Throws an [ActionMapFormatException] only for a document from
  /// a newer build, or another format's, which must not be read as this.
  factory ActionMap.fromJson(
    Map<String, Object?> json, {
    required ActionMap Function() defaults,
  }) {
    final fresh = defaults();
    final version = json['version'];
    if (version == null) {
      // A build before action maps saved the button table and nothing else.
      return ActionMap(
        actions: fresh.actions,
        buttons: Bindings.fromJson(json),
        axes: fresh._axes,
      );
    }
    if (version is! num || version < 1) {
      throw ActionMapFormatException('the action map names version $version');
    }
    // A newer version, another format or a `requires` this build does not
    // know is refused by the spec, naming both versions.
    final lifted = format.open(json, refuse: ActionMapFormatException.new);
    final map = ActionMap(
      actions: fresh.actions,
      unknown: FormatDocument.unknownIn(lifted, known: _known),
      buttons: switch (json['buttons']) {
        final Map<String, Object?> table => Bindings.fromJson(table),
        _ => fresh.buttons,
      },
    );
    switch (json['axes']) {
      case final List<Object?> axes:
        map.readAxes(axes);
      default:
        map._axes.addAll(fresh._axes);
    }
    return map;
  }

  /// The newest action map this build reads and writes.
  static const int formatVersion = 1;

  /// The action map in the registry: `f3d.actions`. The envelope is
  /// additive at version 1 — a build from before it ignores the keys.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.actions',
    version: formatVersion,
    suffixes: <String>['.actions.json'],
    fixture: 'test/fixtures/v<N>/controls.actions.json',
  );

  @override
  FormatSpec get spec => format;

  static const Set<String> _known = <String>{'set', 'buttons', 'axes'};

  /// What the game declares.
  final ActionSet actions;

  /// The button table — see the class doc on why it is shared.
  final Bindings buttons;

  final List<ActionBinding> _axes = <ActionBinding>[];

  /// Axis bindings read from a file in a shape this build does not know,
  /// written back as they came.
  final List<Object?> _unknown = <Object?>[];

  /// Every binding that is not a button, in the order bound.
  List<ActionBinding> get axisBindings =>
      List<ActionBinding>.unmodifiable(_axes);

  /// Every binding, the buttons first.
  List<ActionBinding> get bindings => <ActionBinding>[
    for (final source in buttons.sources)
      ButtonBinding(buttons[source]!, source),
    ..._axes,
  ];

  /// Every binding on [action].
  List<ActionBinding> bindingsFor(InputAction<Object> action) =>
      <ActionBinding>[
        for (final binding in bindings)
          if (binding.action == action) binding,
      ];

  /// Every source that reaches [action], in whatever shape.
  List<InputSource> sourcesFor(InputAction<Object> action) => <InputSource>[
    for (final binding in bindingsFor(action)) ...binding.sources,
  ];

  /// Whether a non-button binding listens to [source] — what a device asks
  /// before handing an event to an `ActionInput`.
  bool routes(InputSource source) =>
      _axes.any((binding) => binding.sources.contains(source));

  /// Adds [binding]. A [ButtonBinding] goes into [buttons], replacing what
  /// its source did before, as [Bindings.bind] always has.
  void bind(ActionBinding binding) {
    switch (binding) {
      case ButtonBinding(:final action, :final source):
        buttons.bind(source, action);
      default:
        _axes.add(binding);
    }
  }

  /// Removes [binding], if it is here.
  void unbind(ActionBinding binding) {
    switch (binding) {
      case ButtonBinding(:final action, :final source):
        if (buttons[source] == action) buttons.unbind(source);
      default:
        _axes.remove(binding);
    }
  }

  /// Every binding that uses [source], other than [ignoring]'s on
  /// [ignoringPart].
  ///
  /// **The question a rebinding screen asks before it binds**, and the one
  /// the old table could not answer for anything but buttons: a key on a
  /// crane's lift composite and on jump at once is two things happening for
  /// one press.
  List<BindingConflict> conflictsFor(
    InputSource source, {
    InputAction<Object>? ignoring,
    CompositePart? ignoringPart,
  }) => <BindingConflict>[
    for (final binding in bindings)
      if (binding.sources.contains(source))
        if (binding.partOf(source) case final part
            when !(binding.action == ignoring && part == ignoringPart))
          BindingConflict(source: source, action: binding.action, part: part),
  ];

  /// Moves [action] (or its composite [part]) onto [source].
  ///
  /// **Replaces within the source's device**: rebinding jump to `J` takes
  /// jump off `Space` and leaves it on the pad's south button, where a
  /// player who rebinds the keyboard did not ask for a change. For an axis
  /// or a dual axis, the first binding of that action from the same device
  /// has its [part] moved; if there is none, a button action gains the
  /// binding and an analogue one is bound fresh.
  ///
  /// What else used [source] is resolved by [onConflict] — see
  /// [ConflictPolicy] — and listed in the outcome either way.
  RebindOutcome rebind(
    InputAction<Object> action,
    InputSource source, {
    CompositePart? part,
    ConflictPolicy onConflict = ConflictPolicy.steal,
  }) {
    final conflicts = conflictsFor(
      source,
      ignoring: action,
      ignoringPart: part,
    );
    if (conflicts.isNotEmpty && onConflict == ConflictPolicy.refuse) {
      return RebindOutcome(applied: false, conflicts: conflicts);
    }

    // What the rebound slot gives up, for a swap.
    final ActionBinding? mine = _sameDevice(action, source.device, part);
    final given = mine?.sourceAt(part);

    for (final conflict in conflicts) {
      final replacement =
          onConflict == ConflictPolicy.swap &&
              given != null &&
              given != InputSource.none
          ? given
          : InputSource.none;
      _replaceSource(conflict, replacement);
    }

    switch (action) {
      case final GameAction button:
        // Within the device: the other devices' sources for it stay.
        for (final old in buttons.sourcesFor(button).toList()) {
          if (old.device == source.device) buttons.unbind(old);
        }
        buttons.bind(source, button);
      case AxisAction() || DualAxisAction():
        final current = _sameDevice(action, source.device, part);
        if (current != null) {
          _axes[_axes.indexOf(current)] = current.withSource(source, part);
        } else {
          // Nothing of this device yet: a part asked for starts a composite
          // with only that part bound, and no part an analogue binding.
          const none = InputSource.none;
          _axes.add(switch ((action, part)) {
            (final AxisAction axis, null) => AxisBinding(axis, source),
            (final DualAxisAction pair, null) => DualAxisBinding(pair, source),
            (final AxisAction axis, final CompositePart part) => AxisComposite(
              axis,
              negative: none,
              positive: none,
            ).withSource(source, part),
            (final DualAxisAction pair, final CompositePart part) =>
              DualAxisComposite(
                pair,
                up: none,
                down: none,
                left: none,
                right: none,
              ).withSource(source, part),
            (final GameAction button, _) => ButtonBinding(button, source),
          });
        }
    }
    return RebindOutcome(applied: true, conflicts: conflicts);
  }

  /// The first binding on [action] whose [part] is on [device], or whose
  /// part is unbound: a composite when [part] is given, a button or an
  /// analogue binding when it is not.
  ActionBinding? _sameDevice(
    InputAction<Object> action,
    String device,
    CompositePart? part,
  ) {
    for (final binding in bindingsFor(action)) {
      // A part is a composite's; no part is a button's or an analogue one's.
      final composite =
          binding is AxisComposite || binding is DualAxisComposite;
      if (composite != (part != null)) continue;
      final at = binding.sourceAt(part);
      if (at.device == device || at == InputSource.none) return binding;
    }
    return null;
  }

  /// Takes [conflict]'s source off the binding it was on, putting
  /// [replacement] there instead ([InputSource.none] to leave it unbound).
  void _replaceSource(BindingConflict conflict, InputSource replacement) {
    final action = conflict.action;
    if (action is GameAction && buttons[conflict.source] == action) {
      buttons.unbind(conflict.source);
      if (replacement != InputSource.none) buttons.bind(replacement, action);
      return;
    }
    for (var i = 0; i < _axes.length; i++) {
      final binding = _axes[i];
      if (binding.action != action ||
          !binding.sources.contains(conflict.source)) {
        continue;
      }
      if (binding is AxisComposite || binding is DualAxisComposite) {
        _axes[i] = binding.withSource(replacement, conflict.part);
      } else if (replacement == InputSource.none) {
        _axes.removeAt(i);
      } else {
        _axes[i] = binding.withSource(replacement, null);
      }
      return;
    }
  }

  /// The shaping on [action]'s first analogue binding from [device] (any
  /// device when null), or [AxisSettings.identity].
  ///
  /// For a game's own settings screen that shows one sensitivity per device
  /// rather than one row per binding, and for tests of [setTuning].
  AxisSettings tuningOf(InputAction<Object> action, {String? device}) {
    for (final binding in _axes) {
      if (binding.action != action) continue;
      switch (binding) {
        case AxisBinding(:final source, :final tuning) ||
                DualAxisBinding(:final source, :final tuning)
            when device == null || source.device == device:
          return tuning;
        default:
      }
    }
    return AxisSettings.identity;
  }

  /// Puts [tuning] on every analogue binding of [action] from [device] (from
  /// every device when null). Returns how many it changed — nought tells a
  /// settings screen there was nothing to tune.
  int setTuning(
    InputAction<Object> action,
    AxisSettings tuning, {
    String? device,
  }) {
    var changed = 0;
    for (var i = 0; i < _axes.length; i++) {
      final binding = _axes[i];
      if (binding.action != action) continue;
      switch (binding) {
        case AxisBinding(:final source)
            when device == null || source.device == device:
          _axes[i] = AxisBinding(binding.action, source, tuning: tuning);
          changed++;
        case DualAxisBinding(:final source)
            when device == null || source.device == device:
          _axes[i] = DualAxisBinding(binding.action, source, tuning: tuning);
          changed++;
        default:
      }
    }
    return changed;
  }

  /// Replaces the axis bindings with those in [axes], as [toJson] wrote
  /// them; shapes this build does not know are kept for the next write.
  void readAxes(List<Object?> axes) {
    _axes.clear();
    _unknown.clear();
    for (final json in axes) {
      final binding = ActionBinding.fromJson(json);
      if (binding == null) {
        _unknown.add(json);
      } else {
        bind(binding);
      }
    }
  }

  /// Becomes a copy of [other], in place — [buttons] included, since that
  /// object is shared with the devices. See [Bindings.copyFrom].
  void copyFrom(ActionMap other) {
    buttons.copyFrom(other.buttons);
    _axes
      ..clear()
      ..addAll(other._axes);
    _unknown
      ..clear()
      ..addAll(other._unknown);
  }

  ActionMap copy() => ActionMap(
    actions: actions,
    buttons: buttons.copy(),
    axes: _axes,
    unknown: unknown,
  ).._unknown.addAll(_unknown);

  /// The axis bindings, as [toJson] writes them.
  List<Object?> axesToJson() => <Object?>[
    for (final binding in _axes) binding.toJson(),
    ..._unknown,
  ];

  /// The whole map. [includeButtons] false leaves the button table out, for
  /// a document that saves it under its own key already — `GameSettings`.
  Map<String, Object?> toJson({bool includeButtons = true}) =>
      write(<String, Object?>{
        'set': actions.name,
        if (includeButtons) 'buttons': buttons.toJson(),
        'axes': axesToJson(),
      });
}

/// Thrown when a saved action map cannot be read: a newer build's, or a
/// document that is not one.
final class ActionMapFormatException extends Flutter3dFormatException {
  const ActionMapFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ActionMapFormatException: $message';
}
