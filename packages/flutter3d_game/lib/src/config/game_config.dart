import '../input/bindings.dart';

/// Everything a player has changed about how the game behaves for them.
///
/// Data, and only data: it holds no file, no path and no platform. Where the
/// bytes go is an application's business — a sandboxed macOS app, an Android
/// app and a test with a temporary directory all answer that differently, and
/// none of those answers belongs in a package that also has to run in a unit
/// test with no disk at all.
///
/// **Volumes are a map of names, not an `AudioBus`.** `flutter3d_game` does not
/// depend on `flutter3d_audio` and should not learn to: a bus is a string here,
/// the audio package turns it back into a bus, and a game with a `dialogue`
/// slider needs no change on either side.
final class GameConfig {
  GameConfig({
    Bindings? bindings,
    Map<String, double>? volumes,
    Map<String, double>? settings,
  }) : bindings = bindings ?? Bindings(),
       volumes = <String, double>{...?volumes},
       settings = <String, double>{...?settings};

  /// Reads what [toJson] wrote, and survives what it did not write.
  ///
  /// Every field is optional. A config from an older build is missing keys, a
  /// config from a newer one has keys this build does not know, and the only
  /// acceptable answer to both is to keep going with what is understood — a
  /// settings file that throws is a settings file that bricks the game.
  factory GameConfig.fromJson(Map<String, Object?> json) {
    final bindings = json['bindings'];
    return GameConfig(
      bindings: bindings is Map<String, Object?>
          ? Bindings.fromJson(bindings)
          : Bindings(),
      volumes: _numbers(json['volumes']),
      settings: _numbers(json['settings']),
    );
  }

  /// Every number in a map, and nothing that is not a number.
  ///
  /// A settings file is edited by hand more often than anybody admits, and a
  /// string where a number was expected must cost that one key rather than the
  /// whole file.
  static Map<String, double> _numbers(Object? source) => <String, double>{
    if (source is Map<String, Object?>)
      for (final entry in source.entries)
        if (entry.value is num) entry.key: (entry.value! as num).toDouble(),
  };

  final Bindings bindings;

  /// How loud each bus is, by name, in `[0, 1]`.
  final Map<String, double> volumes;

  /// Everything else a player has turned, by name.
  ///
  /// **A second map rather than fields**, and the reason is the same one the
  /// class doc gives for volumes: a dead zone belongs to a gamepad package this
  /// one does not depend on, a look sensitivity belongs to a camera, and neither
  /// is a concept `flutter3d_game` should learn in order to write a number down.
  /// A name and a number is the whole of what it needs to know.
  ///
  /// The names in use, so they are in one place rather than spelled slightly
  /// differently in three:
  ///
  /// * `pad.deadzone.stick`, `pad.deadzone.trigger` — how much of a stick's or
  ///   trigger's travel is rest;
  /// * `pad.look` — how fast the right stick turns the view;
  /// * `mouse.look` — the same for the mouse, which until now had nowhere to
  ///   live and so could not be changed at all;
  /// * `a11y.cameraMotion` — how much of the camera's involuntary movement to
  ///   keep, from nought to one. See `CameraRig.motion`: the shakes and knocks
  ///   are what make people ill, and the following is the game;
  /// * `a11y.toggleSprint` — one when sprinting latches rather than being held.
  ///   Stored as a number like everything else here, because a map of doubles is
  ///   one thing to read, write and hand-edit rather than two.
  ///
  /// **The `a11y.` names are settings and not decoration.** Each is something a
  /// player cannot play without: a camera that flinches, a key that has to be
  /// held for a minute. They are spelled here so three games cannot spell them
  /// three ways, which is the same reason the pad's names are.
  ///
  /// Unlike [volumes] there is no universal default: a sensitivity of one means
  /// nothing without knowing whose. So [settingOf] takes the fallback from the
  /// caller, which is the only place that knows it.
  final Map<String, double> settings;

  double volumeOf(String bus) => volumes[bus] ?? 1.0;

  void setVolume(String bus, double volume) =>
      volumes[bus] = volume.clamp(0.0, 1.0);

  double settingOf(String name, double fallback) => settings[name] ?? fallback;

  /// Records a setting.
  ///
  /// Not clamped, because this map holds things that are not fractions: a look
  /// sensitivity above one is an ordinary request, and a class that knew which
  /// names were fractions would be a class that knew what a gamepad is.
  void setSetting(String name, double value) => settings[name] = value;

  Map<String, Object?> toJson() => <String, Object?>{
    'bindings': bindings.toJson(),
    // Sorted for the same reason the bindings are: a settings file whose
    // diff is noise is a settings file nobody can review, and this one is
    // meant to be readable by the person whose settings it holds.
    'volumes': <String, Object?>{
      for (final name in volumes.keys.toList()..sort()) name: volumes[name],
    },
    // Omitted when empty, so a config written by a build that had no
    // settings reads back byte for byte.
    if (settings.isNotEmpty)
      'settings': <String, Object?>{
        for (final name in settings.keys.toList()..sort()) name: settings[name],
      },
  };
}
