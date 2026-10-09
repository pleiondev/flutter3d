import 'package:flutter3d_audio_core/flutter3d_audio_core.dart' show AudioBus;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ActionSet;

import '../input/action_map.dart';

/// One thing a player can change, typed, under a namespaced id.
///
/// **The id is `<namespace>.<name>`**: the engine's own keys are under
/// `flutter3d.` ([GameSettingKeys]), and a game's are under its own name —
/// `crypt.torchFlicker` — so two games, or a game and the engine, cannot
/// write the same word for two different things into one file.
///
/// [T] is one of `double`, `int`, `bool` or `String`: what a settings file
/// can hold and a person can edit by hand. A value of another type in the
/// file, or none, reads as [fallback].
final class SettingKey<T extends Object> {
  const SettingKey(this.id, {required this.fallback})
    : assert(
        T == double || T == int || T == bool || T == String,
        'a setting is a double, an int, a bool or a String',
      );

  /// Where the value is written, `<namespace>.<name>`.
  final String id;

  /// What the setting is when the player has not chosen.
  final T fallback;

  /// What comes before the first dot of [id]: whose setting this is.
  String get namespace {
    final dot = id.indexOf('.');
    return dot < 0 ? id : id.substring(0, dot);
  }

  /// [json] as a [T], or null when it is not one.
  ///
  /// A number where a `bool` is asked for reads as true from one half up,
  /// which is how a settings file from before typed keys wrote a switch.
  T? decode(Object? json) {
    final Object? value = switch (fallback) {
      double() => json is num ? json.toDouble() : null,
      int() => json is num ? json.round() : null,
      bool() => switch (json) {
        final bool on => on,
        final num n => n >= 0.5,
        _ => null,
      },
      String() => json is String ? json : null,
      _ => null,
    };
    return value is T ? value : null;
  }

  @override
  bool operator ==(Object other) => other is SettingKey && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SettingKey<$T>($id)';
}

/// The settings the engine's own screens and devices read.
abstract final class GameSettingKeys {
  /// How much of a stick's travel is rest, as a fraction of it.
  static const SettingKey<double> stickDeadZone = SettingKey<double>(
    'flutter3d.pad.deadZone.stick',
    fallback: 0.15,
  );

  /// How much of a trigger's travel is rest, as a fraction of it.
  static const SettingKey<double> triggerDeadZone = SettingKey<double>(
    'flutter3d.pad.deadZone.trigger',
    fallback: 0.06,
  );

  /// How fast the right stick turns the view, in the pad's look units per
  /// second at full deflection.
  static const SettingKey<double> padLook = SettingKey<double>(
    'flutter3d.pad.look',
    fallback: 1100.0,
  );

  /// A factor on the mouse's look speed: 1 is the game's own, no unit.
  static const SettingKey<double> mouseLook = SettingKey<double>(
    'flutter3d.mouse.look',
    fallback: 1.0,
  );

  /// Whether moving the mouse forward looks down.
  static const SettingKey<bool> mouseInvertY = SettingKey<bool>(
    'flutter3d.mouse.invertY',
    fallback: false,
  );

  /// How much of the camera's involuntary movement to keep, a fraction from
  /// nought to one. See `CameraRig.motion`: the shakes and knocks are what
  /// make people ill, and the following is the game.
  static const SettingKey<double> cameraMotion = SettingKey<double>(
    'flutter3d.a11y.cameraMotion',
    fallback: 1.0,
  );

  /// Whether sprinting latches rather than being held.
  static const SettingKey<bool> toggleSprint = SettingKey<bool>(
    'flutter3d.a11y.toggleSprint',
    fallback: false,
  );

  /// Whether the high-contrast look is on; absent for whatever the system
  /// asks. See `highContrastOf`.
  static const SettingKey<bool> highContrast = SettingKey<bool>(
    'flutter3d.a11y.highContrast',
    fallback: false,
  );

  /// The player's colour vision: nought for none, then one each for
  /// `ColorVisionDeficiency.values`, in their order. See `colorVisionOf`.
  static const SettingKey<int> colorVision = SettingKey<int>(
    'flutter3d.a11y.colorVision',
    fallback: 0,
  );

  /// The key a colour role's choice is kept under: an index into
  /// `ColorRoles.choices`, nought for the role's own colour.
  static SettingKey<int> colorRole(String name) =>
      SettingKey<int>('flutter3d.color.$name', fallback: 0);
}

/// Everything a player has changed about how the game behaves for them.
///
/// Data, and only data: it holds no file, no path and no platform. Where the
/// bytes go is an application's business — see `SettingsFile`.
///
/// **A value.** Every change is a [copyWith] (or one of the `with…` forms
/// over it), and `GameSettingsController` holds the current one; nothing
/// edits a [GameSettings] in place, so the copy a widget was built from is
/// the one it shows.
///
/// [actions] is the player's [ActionMap] as it was saved, or null for the
/// game's own. A game makes the map its devices read from it once (see
/// [actionsOr]) and the controller saves a copy of that map back on every
/// rebind, so the map held here is never the one being edited.
final class GameSettings {
  const GameSettings({
    this.volumes = const <AudioBus, double>{},
    this.values = const <String, Object>{},
    this.actions,
    this.unknown = const <String, Object?>{},
  });

  /// Reads what [toJson] wrote, at any version up to [formatVersion], and the
  /// settings files from before the envelope.
  ///
  /// [defaultActions] is the game's own action map: what a file's saved map
  /// is read against, so an action it declares that the file does not name
  /// keeps its default bindings. Without it a saved map is read over
  /// `ActionSet.common`.
  ///
  /// **Never throws for a file this build can read part of.** A missing key
  /// is a default, a value of the wrong type is a default for that key
  /// alone, and a key this build does not know is kept and written back. A
  /// file from a newer build is refused with a [GameSettingsFormatException],
  /// which `SettingsFile.read` turns into the defaults and an issue.
  factory GameSettings.fromJson(
    Map<String, Object?> json, {
    ActionMap Function()? defaultActions,
  }) {
    final lifted = format.open(json, refuse: GameSettingsFormatException.new);
    final actions = lifted['actions'];
    return GameSettings(
      volumes: <AudioBus, double>{
        if (lifted['volumes'] case final Map<String, Object?> volumes)
          for (final MapEntry(:key, :value) in volumes.entries)
            if (value is num) AudioBus(key): value.toDouble().clamp(0.0, 1.0),
      },
      values: <String, Object>{
        if (lifted['values'] case final Map<String, Object?> values)
          for (final MapEntry(:key, :value) in values.entries)
            if (value is num || value is bool || value is String) key: value!,
      },
      actions: actions is Map<String, Object?>
          ? _readActions(actions, defaultActions)
          : null,
      unknown: FormatDocument.unknownIn(lifted, known: _known),
    );
  }

  static ActionMap? _readActions(
    Map<String, Object?> json,
    ActionMap Function()? defaults,
  ) {
    try {
      return ActionMap.fromJson(
        json,
        defaults: defaults ?? () => ActionMap(actions: ActionSet.common),
      );
    } on ActionMapFormatException {
      // A newer build's map: the game's defaults, rather than the whole file.
      return null;
    }
  }

  /// The newest settings file this build reads and writes.
  ///
  /// Version 1 is every file from before the envelope: `bindings`, `volumes`,
  /// `settings` with names that had no namespace, and `actions` without its
  /// buttons. Version 2 is the envelope, typed values under namespaced ids,
  /// and the whole action map under `actions`.
  static const int formatVersion = 2;

  /// The settings file in the registry: `f3d.settings`.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.settings',
    version: formatVersion,
    suffixes: <String>['.settings.json'],
    fixture: 'test/fixtures/v<N>/settings.json',
    migrations: <FormatMigration>[_liftFrom1],
  );

  static const Set<String> _known = <String>{'volumes', 'values', 'actions'};

  /// How loud each bus is, a fraction in `[0, 1]`; a bus not here is at 1.
  final Map<AudioBus, double> volumes;

  /// Every other value the player chose, by [SettingKey.id], as it is
  /// written: a `double`, an `int`, a `bool` or a `String`. Read through
  /// [valueOf] rather than here, which gives the key's type.
  final Map<String, Object> values;

  /// The player's action map, or null for the game's own.
  final ActionMap? actions;

  /// The keys a later build wrote that this one does not read, written back
  /// as they came.
  final Map<String, Object?> unknown;

  /// How loud [bus] is: the player's choice, or 1.
  double volumeOf(AudioBus bus) => volumes[bus] ?? 1.0;

  /// What [key] is: the player's choice, or its fallback.
  T valueOf<T extends Object>(SettingKey<T> key) =>
      key.decode(values[key.id]) ?? key.fallback;

  /// What the player chose for [key], or null if they have not — for a
  /// setting whose default is somebody else's answer, as the system's
  /// reduce-motion is the camera's.
  T? chosenValueOf<T extends Object>(SettingKey<T> key) =>
      key.decode(values[key.id]);

  /// A copy with [bus] at [volume], clamped to `[0, 1]`.
  GameSettings withVolume(AudioBus bus, double volume) => copyWith(
    volumes: <AudioBus, double>{...volumes, bus: volume.clamp(0.0, 1.0)},
  );

  /// A copy with [key] set to [value].
  GameSettings withValue<T extends Object>(SettingKey<T> key, T value) =>
      copyWith(values: <String, Object>{...values, key.id: value});

  /// A copy in which the player has not chosen [key]: it reads as its
  /// fallback again, or the system's answer.
  GameSettings withoutValue(SettingKey<Object> key) =>
      copyWith(values: <String, Object>{...values}..remove(key.id));

  /// A copy with the fields given changed. [clearActions] goes back to the
  /// game's own action map, which `actions: null` cannot say.
  GameSettings copyWith({
    Map<AudioBus, double>? volumes,
    Map<String, Object>? values,
    ActionMap? actions,
    bool clearActions = false,
    Map<String, Object?>? unknown,
  }) => GameSettings(
    volumes: volumes ?? this.volumes,
    values: values ?? this.values,
    actions: clearActions ? null : (actions ?? this.actions),
    unknown: unknown ?? this.unknown,
  );

  /// The map a game's devices read: a copy of the player's [actions], or
  /// [defaults] when they have none.
  ActionMap actionsOr(ActionMap Function() defaults) =>
      actions?.copy() ?? defaults();

  /// The file, in the envelope.
  ///
  /// Sorted, because a settings file whose diff is noise is a settings file
  /// nobody can review, and this one is meant to be readable by the person
  /// whose settings it holds.
  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(),
    'volumes': <String, Object?>{
      for (final bus
          in volumes.keys.toList()
            ..sort((AudioBus a, AudioBus b) => a.name.compareTo(b.name)))
        bus.name: volumes[bus],
    },
    if (values.isNotEmpty)
      'values': <String, Object?>{
        for (final id in values.keys.toList()..sort()) id: values[id],
      },
    if (actions case final ActionMap map) 'actions': map.toJson(),
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_known.contains(key)) key: value,
  };
}

/// The names version 1 of the settings file wrote, and the ids they are now.
///
/// A colour role was `colour.<name>`; it is `flutter3d.color.<name>`. A name
/// not here and with no namespace of the engine's is a game's own, and is
/// carried over as it was.
const Map<String, String> _renamedIn2 = <String, String>{
  'pad.deadzone.stick': 'flutter3d.pad.deadZone.stick',
  'pad.deadzone.trigger': 'flutter3d.pad.deadZone.trigger',
  'pad.look': 'flutter3d.pad.look',
  'mouse.look': 'flutter3d.mouse.look',
  'mouse.invertY': 'flutter3d.mouse.invertY',
  'a11y.cameraMotion': 'flutter3d.a11y.cameraMotion',
  'a11y.toggleSprint': 'flutter3d.a11y.toggleSprint',
  'a11y.highContrast': 'flutter3d.a11y.highContrast',
  'a11y.colorVision': 'flutter3d.a11y.colorVision',
};

/// The ids version 1's switches become, written as `bool` from version 2.
const Set<String> _switchesIn2 = <String>{
  'flutter3d.mouse.invertY',
  'flutter3d.a11y.toggleSprint',
  'flutter3d.a11y.highContrast',
};

/// Version 1 as version 2 writes it: `settings` renamed into `values`, and
/// `bindings` folded into the action map, whose own reader takes a bare
/// button table from before it had a version.
Map<String, Object?> _liftFrom1(Map<String, Object?> document) {
  final settings = document.remove('settings');
  final bindings = document.remove('bindings');
  final actions = document.remove('actions');
  return <String, Object?>{
    ...document,
    if (settings is Map<String, Object?>)
      'values': <String, Object?>{
        for (final MapEntry(:key, :value) in settings.entries)
          if (value is num)
            if (_renamedIn2[key] ??
                    (key.startsWith('colour.')
                        ? 'flutter3d.color.${key.substring(7)}'
                        : key)
                case final id)
              id: _switchesIn2.contains(id) ? value >= 0.5 : value,
      },
    if ((actions, bindings) case (
      final Map<String, Object?> rest,
      final Map<String, Object?> buttons,
    ))
      'actions': <String, Object?>{...rest, 'buttons': buttons}
    else if (bindings case final Map<String, Object?> table
        when table.isNotEmpty)
      'actions': table,
  };
}

/// Thrown when a settings file cannot be read at all: a newer build's, or
/// another format's.
final class GameSettingsFormatException extends Flutter3dFormatException {
  const GameSettingsFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'GameSettingsFormatException: $message';
}
