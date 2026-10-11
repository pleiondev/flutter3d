/// Part of a world: what a level, a preset or a scenario changes of the
/// world it is played in.
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:vector_math/vector_math.dart';

import 'geo_origin.dart';
import 'world_properties.dart';

/// The fields of a [WorldProperties] something sets, and nothing it does not.
///
/// **A patch rather than a whole world**, because a world's defaults are the
/// game's to choose: a platformer's run falls at 24 m/s², a laboratory at
/// standard gravity, and a level set on the Moon says its gravity once and
/// must not overrule the rest. [over] lays it on the world the game stages
/// every level in.
///
/// **Its document is a world's own JSON with keys left out** — `gravity` (a
/// vector, or m/s² down y), `airTemperature`, `airPressure`, `airDensity`,
/// `wind`, `medium`, `profile`, `geoOrigin` — kept as it was written: a key this build does not know
/// (a `stepRate` from before 1.0, say) is kept and written back, and a value
/// is never sent through float32 on the way, so a patch read and written is
/// the same document.
///
/// Immutable. Every getter answers null for a field the patch leaves alone.
final class WorldPropertiesPatch {
  /// A patch setting the fields given. Throws an [ArgumentError] for a value
  /// a world would refuse.
  factory WorldPropertiesPatch({
    Vector3? gravity,
    double? airTemperature,
    double? airPressure,
    double? airDensity,
    Vector3? wind,
    String? medium,
    SimulationProfile? profile,
    GeoOrigin? geoOrigin,
  }) {
    try {
      return WorldPropertiesPatch.fromJson(<String, Object?>{
        if (gravity != null)
          'gravity': <double>[gravity.x, gravity.y, gravity.z],
        'airTemperature': ?airTemperature,
        'airPressure': ?airPressure,
        'airDensity': ?airDensity,
        if (wind != null) 'wind': <double>[wind.x, wind.y, wind.z],
        'medium': ?medium,
        if (profile != null) 'profile': profile.toJson(),
        if (geoOrigin != null) 'geoOrigin': geoOrigin.toJson(),
      });
    } on WorldPropertiesFormatException catch (error) {
      throw ArgumentError(error.message);
    }
  }

  const WorldPropertiesPatch._(this._json);

  /// The patch that changes nothing.
  static const WorldPropertiesPatch empty = WorldPropertiesPatch._(
    <String, Object?>{},
  );

  /// The patch [json] writes. Throws a [WorldPropertiesFormatException] for
  /// a field a world would refuse, naming it.
  factory WorldPropertiesPatch.fromJson(Map<String, Object?> json) {
    if (json.isEmpty) return empty;
    final copy = Map<String, Object?>.unmodifiable(<String, Object?>{...json});
    // Checked once, here, so a patch that exists is one [over] can lay.
    WorldProperties.fromJson(copy);
    return WorldPropertiesPatch._(copy);
  }

  final Map<String, Object?> _json;

  /// Whether this patch changes nothing.
  bool get isEmpty => _json.isEmpty;

  /// The keys this patch writes, known to this build or not.
  Iterable<String> get keys => _json.keys;

  WorldProperties? get _alone =>
      isEmpty ? null : WorldProperties.fromJson(_json);

  /// The gravity this patch sets, m/s², or null. A fresh vector each call.
  Vector3? get gravity => _json.containsKey('gravity') ? _alone!.gravity : null;

  /// The air's temperature it sets, K, or null.
  double? get airTemperature =>
      _json.containsKey('airTemperature') ? _alone!.airTemperature : null;

  /// The air's pressure it sets, Pa, or null.
  double? get airPressure =>
      _json.containsKey('airPressure') ? _alone!.airPressure : null;

  /// The air's density it sets explicitly, kg/m³, or null.
  double? get airDensity =>
      _json.containsKey('airDensity') ? _alone!.airDensityOverride : null;

  /// The wind it sets, m/s, or null. A fresh vector each call.
  Vector3? get wind => _json.containsKey('wind') ? _alone!.wind : null;

  /// The medium it sets, a material's id, or null.
  String? get medium => _json.containsKey('medium') ? _alone!.medium : null;

  /// The profile it asks the world to run under, or null.
  SimulationProfile? get profile =>
      _json.containsKey('profile') ? _alone!.profile : null;

  /// Where on the Earth it puts the world's origin, or null.
  GeoOrigin? get geoOrigin =>
      _json.containsKey('geoOrigin') ? _alone!.geoOrigin : null;

  /// [base] with what this patch sets laid over it.
  WorldProperties over(WorldProperties base) =>
      isEmpty ? base : WorldProperties.fromJson(_json, base: base);

  /// The document: the keys as they were written.
  Map<String, Object?> toJson() => <String, Object?>{..._json};

  @override
  bool operator ==(Object other) =>
      other is WorldPropertiesPatch &&
      jsonEncode(other._json) == jsonEncode(_json);

  @override
  int get hashCode => jsonEncode(_json).hashCode;

  @override
  String toString() => 'WorldPropertiesPatch(${jsonEncode(_json)})';
}
