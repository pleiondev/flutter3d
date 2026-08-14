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
  GameConfig({Bindings? bindings, Map<String, double>? volumes})
      : bindings = bindings ?? Bindings(),
        volumes = <String, double>{...?volumes};

  /// Reads what [toJson] wrote, and survives what it did not write.
  ///
  /// Every field is optional. A config from an older build is missing keys, a
  /// config from a newer one has keys this build does not know, and the only
  /// acceptable answer to both is to keep going with what is understood — a
  /// settings file that throws is a settings file that bricks the game.
  factory GameConfig.fromJson(Map<String, Object?> json) {
    final bindings = json['bindings'];
    final volumes = json['volumes'];
    return GameConfig(
      bindings: bindings is Map<String, Object?>
          ? Bindings.fromJson(bindings)
          : Bindings(),
      volumes: <String, double>{
        if (volumes is Map<String, Object?>)
          for (final entry in volumes.entries)
            if (entry.value is num) entry.key: (entry.value! as num).toDouble(),
      },
    );
  }

  final Bindings bindings;

  /// How loud each bus is, by name, in `[0, 1]`.
  final Map<String, double> volumes;

  double volumeOf(String bus) => volumes[bus] ?? 1.0;

  void setVolume(String bus, double volume) =>
      volumes[bus] = volume.clamp(0.0, 1.0);

  Map<String, Object?> toJson() => <String, Object?>{
        'bindings': bindings.toJson(),
        // Sorted for the same reason the bindings are: a settings file whose
        // diff is noise is a settings file nobody can review, and this one is
        // meant to be readable by the person whose settings it holds.
        'volumes': <String, Object?>{
          for (final name in volumes.keys.toList()..sort()) name: volumes[name],
        },
      };
}
