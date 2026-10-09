/// What a world is made of: its gravity, its air, its wind and the medium
/// things move through.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;
import 'package:vector_math/vector_math.dart';

import 'materials/material_catalog.dart';
import 'standard_world.dart';

/// The properties of one world, read by everything in it.
///
/// **One gravity per game** (decision 1 of `tasks/1.0-physics-audit.md`).
/// The engine's default is [standardGravity]; a game sets its own world
/// explicitly where it stages it — the platformer's at 24 m/s², the racing
/// game's at 20 — and a level may set its own on top (`Level.world`). Then a
/// rigid body, a runner, an AI's jump arc, a ragdoll, a spark, a cloth, a
/// tyre's grip and a swimmer's lift all read the same number, and a level
/// set on the Moon is the Moon for every one of them.
///
/// **The air's density is derived** from its [airTemperature] and
/// [airPressure] by the ideal gas law ([airDensityAt]) unless a world says
/// it explicitly ([airDensityOverride]), and the speed of sound from its
/// temperature ([speedOfSound]).
///
/// **The [medium] is a material's id** in the engine's `MaterialCatalog`:
/// `f3d.air` for a world on land, `f3d.seawater` for one under the sea, a
/// plugin's for one of its own. What a body moving through the world is
/// dragged and lifted by is [mediumDensity] — the world's own air where the
/// medium is air, the catalogue's entry otherwise.
///
/// **Not how often it is stepped.** A world's step rate is the loop's
/// (`WorldTiming` in `flutter3d_sim`); it was a field here until
/// 1.0.0-rc.1, which nothing read, and a document that still carries it
/// reads with the key passed over.
///
/// Immutable: a world that changes takes a new value ([copyWith]), and a
/// snapshot holds one ([toJson]). [gravity] and [wind] are `vector_math`
/// vectors, which are mutable, so the world keeps its own copies and hands
/// out fresh ones. See docs/CONTRACTS.md's "World properties" for who reads
/// each field.
final class WorldProperties {
  /// A world with these properties; anything left out is the standard
  /// world's (`standard_world.dart`). Throws an [ArgumentError] for a
  /// temperature, pressure or density that is not finite and positive, or a
  /// gravity or wind that is not finite.
  WorldProperties({
    Vector3? gravity,
    this.airTemperature = standardAirTemperature,
    this.airPressure = standardAtmosphere,
    double? airDensity,
    Vector3? wind,
    this.medium = 'f3d.air',
  }) : _gravity = gravity?.clone() ?? standardGravityVector,
       _wind = wind?.clone() ?? Vector3.zero(),
       airDensityOverride = airDensity {
    _positive(airTemperature, 'airTemperature');
    _positive(airPressure, 'airPressure');
    if (airDensity != null) _positive(airDensity, 'airDensity');
    if (!_finite(_gravity)) {
      throw ArgumentError.value(gravity, 'gravity', 'not finite');
    }
    if (!_finite(_wind)) throw ArgumentError.value(wind, 'wind', 'not finite');
    if (medium.isEmpty) throw ArgumentError.value(medium, 'medium', 'no id');
  }

  /// The standard world: [standardGravity] down, the air of a room at sea
  /// level, no wind, in air.
  static final WorldProperties standard = WorldProperties();

  final Vector3 _gravity;
  final Vector3 _wind;

  /// Metres per second squared; [standardGravity] down y by default. A fresh
  /// vector each call: a `Vector3` is mutable.
  Vector3 get gravity => _gravity.clone();

  /// How strong [gravity] is, m/s². **[standardGravity] to the bit** for the
  /// standard gravity, as `NativeWorld.gravityMagnitude` is.
  double get gravityMagnitude {
    final x = _gravity.x, y = _gravity.y, z = _gravity.z;
    if (x == 0.0 && z == 0.0 && y == -standardGravity) return standardGravity;
    return math.sqrt(x * x + y * y + z * z);
  }

  /// The air's temperature, K.
  final double airTemperature;

  /// The air's pressure at the world's datum — the surface of its sea, the
  /// floor of its valley — Pa.
  final double airPressure;

  /// The air's density a world set explicitly, kg/m³; null when it is
  /// derived ([airDensity]).
  final double? airDensityOverride;

  /// The air's density, kg/m³: [airDensityOverride], or the ideal gas's at
  /// [airTemperature] and [airPressure] ([airDensityAt]) —
  /// [standardAirDensity] for the standard air, to the bit.
  double get airDensity =>
      airDensityOverride ?? airDensityAt(airTemperature, airPressure);

  /// The wind everywhere, m/s: what a cloth flaps in, smoke and sparks
  /// drift on and the air drags a body by. A fresh vector each call.
  Vector3 get wind => _wind.clone();

  /// The id of the material the world is filled with, in its
  /// `MaterialCatalog`: `f3d.air` by default.
  final String medium;

  /// How fast sound travels in the world's air, m/s ([speedOfSoundAt] its
  /// temperature): what a listener's Doppler shift is reckoned against.
  double get speedOfSound => speedOfSoundAt(airTemperature);

  /// The density of what a body moving through the world is dragged and
  /// lifted by, kg/m³: [airDensity] when the [medium] is `f3d.air`, else
  /// the [medium]'s in [catalog]. Throws an `UnknownMaterialException`
  /// naming the plugin it needs when [catalog] has no such material, and a
  /// [StateError] for a medium with no density.
  double mediumDensity(MaterialCatalog catalog) {
    if (medium == 'f3d.air') return airDensity;
    return catalog.require(medium).density ??
        (throw StateError('the medium "$medium" says no density'));
  }

  /// A copy with the fields given changed. [clearAirDensity] goes back to
  /// deriving the air's density from its temperature and pressure.
  WorldProperties copyWith({
    Vector3? gravity,
    double? airTemperature,
    double? airPressure,
    double? airDensity,
    bool clearAirDensity = false,
    Vector3? wind,
    String? medium,
  }) => WorldProperties(
    gravity: gravity ?? _gravity,
    airTemperature: airTemperature ?? this.airTemperature,
    airPressure: airPressure ?? this.airPressure,
    airDensity: clearAirDensity ? null : (airDensity ?? airDensityOverride),
    wind: wind ?? _wind,
    medium: medium ?? this.medium,
  );

  /// The world as JSON, every field: what a snapshot and a level hold.
  /// `airDensity` only when [airDensityOverride] says it.
  Map<String, Object?> toJson() => <String, Object?>{
    'gravity': <double>[_gravity.x, _gravity.y, _gravity.z],
    'airTemperature': airTemperature,
    'airPressure': airPressure,
    'airDensity': ?airDensityOverride,
    'wind': <double>[_wind.x, _wind.y, _wind.z],
    'medium': medium,
  };

  /// The world [json] describes, each field absent taken from [base] — the
  /// standard world by default, a game's own world when a level overrides
  /// only some of it.
  ///
  /// `gravity` is a vector `[x, y, z]`, or a single number of m/s² pointing
  /// down y — how a level wrote it before it was a vector. A `stepRate` key,
  /// which a world carried before 1.0.0-rc.1, is passed over: the rate is the
  /// loop's. Throws a [WorldPropertiesFormatException] for a field that is
  /// not what it says.
  factory WorldProperties.fromJson(
    Map<String, Object?> json, {
    WorldProperties? base,
  }) {
    final from = base ?? standard;
    Vector3? vector(
      String key, {
      bool scalarDown = false,
    }) => switch (json[key]) {
      null => null,
      final num down when scalarDown && down.isFinite && down >= 0 => Vector3(
        0.0,
        -down.toDouble(),
        0.0,
      ),
      final List<Object?> v
          when v.length == 3 &&
              v.every((Object? e) => e is num && e.isFinite) =>
        Vector3(
          (v[0]! as num).toDouble(),
          (v[1]! as num).toDouble(),
          (v[2]! as num).toDouble(),
        ),
      final other => throw WorldPropertiesFormatException(
        '"$key" must be ${scalarDown ? 'm/s² down, nought or more, or ' : ''}'
        'three finite numbers, not $other',
      ),
    };
    double? positive(String key) => switch (json[key]) {
      null => null,
      final num value when value.isFinite && value > 0 => value.toDouble(),
      final other => throw WorldPropertiesFormatException(
        '"$key" must be a positive number, not $other',
      ),
    };
    final medium = switch (json['medium']) {
      null => null,
      final String id when id.isNotEmpty => id,
      final other => throw WorldPropertiesFormatException(
        '"medium" must be a material\'s id, not $other',
      ),
    };
    final airTemperature = positive('airTemperature');
    final airPressure = positive('airPressure');
    final explicitDensity = positive('airDensity');
    // A level that sets the air's temperature or pressure and not its
    // density means the density that air has, not the base's override.
    final keepsBaseDensity = airTemperature == null && airPressure == null;
    return WorldProperties(
      gravity: vector('gravity', scalarDown: true) ?? from._gravity,
      airTemperature: airTemperature ?? from.airTemperature,
      airPressure: airPressure ?? from.airPressure,
      airDensity:
          explicitDensity ??
          (keepsBaseDensity ? from.airDensityOverride : null),
      wind: vector('wind') ?? from._wind,
      medium: medium ?? from.medium,
    );
  }

  static void _positive(double value, String name) {
    if (!(value.isFinite && value > 0.0)) {
      throw ArgumentError.value(value, name, 'not finite and positive');
    }
  }

  static bool _finite(Vector3 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite;

  @override
  bool operator ==(Object other) =>
      other is WorldProperties &&
      other._gravity == _gravity &&
      other.airTemperature == airTemperature &&
      other.airPressure == airPressure &&
      other.airDensityOverride == airDensityOverride &&
      other._wind == _wind &&
      other.medium == medium;

  @override
  int get hashCode => Object.hash(
    _gravity.x,
    _gravity.y,
    _gravity.z,
    airTemperature,
    airPressure,
    airDensityOverride,
    _wind.x,
    _wind.y,
    _wind.z,
    medium,
  );

  @override
  String toString() =>
      'WorldProperties(g ${_gravity.storage.toList()}, air $airTemperature K '
      '$airPressure Pa, wind ${_wind.storage.toList()}, $medium)';
}

/// A world's properties in a document — a level's `world`, a snapshot —
/// that cannot be read.
final class WorldPropertiesFormatException extends Flutter3dFormatException {
  const WorldPropertiesFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'WorldPropertiesFormatException: $message';
}
