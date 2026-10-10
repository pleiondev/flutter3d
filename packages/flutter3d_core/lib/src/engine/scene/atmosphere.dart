/// The air of a scene at one moment, a day of them, and lights that are
/// dimmed together.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import '../render/render_settings.dart';
import 'light_node.dart';
import 'scene.dart';

/// What the air looks like at one moment: the sky behind everything, the
/// fog, the sun and the ambient light.
///
/// **One value to blend, rather than six to keep in step.** Enduro's day
/// turns to dusk, to night, to snow and fog; a game that eased the sky, the
/// fog, the sun and the ambient separately eased them at different rates by
/// accident, and dusk had a noon sun under a night sky for a moment. An
/// [Atmosphere] is all of them at once, [lerp] blends all of them by one
/// amount, and [applyTo] puts them on a scene.
final class Atmosphere {
  /// An atmosphere with a [sky] and a [sunColor], everything else at its
  /// default. Colours are linear light (`LinearColor` since 1.0).
  const Atmosphere({
    required this.sky,
    LinearColor? fogColor,
    this.fogDensity = 0.0,
    this.fogHeightFalloff = 0.0,
    this.fogBaseHeight = 0.0,
    required this.sunColor,
    this.sunIntensity = 2.0 * Photometric.legacyUnit,
    this.ambientColor = LinearColor.white,
    this.ambientIntensity = 0.3 * Photometric.legacyUnit,
    // A named parameter may not be private, and the field stays private so
    // [fogColor] can fall back to the sky.
    // ignore: prefer_initializing_formals
  }) : _fogColor = fogColor;

  /// The colour behind everything drawn: the clear colour.
  final LinearColor sky;

  /// What the fog fades to; the sky's own colour unless given, so the far
  /// end of the world meets the sky without a seam.
  LinearColor get fogColor => _fogColor ?? sky;
  final LinearColor? _fogColor;

  /// How thick the fog is, per metre, at [fogBaseHeight].
  final double fogDensity;

  /// How fast the fog thins upwards, per metre, and the height at which it is
  /// [fogDensity] thick — `FogSettings.heightFalloff` and `baseHeight`. Nought
  /// is fog at every height alike, which every atmosphere was before `P5`; a
  /// morning that burns off is a falloff blended up through the day.
  final double fogHeightFalloff;

  /// In metres.
  final double fogBaseHeight;

  /// The sun's colour.
  final LinearColor sunColor;

  /// The sun's illuminance, in lux (since 1.0) — what [applyTo] sets a
  /// directional light's `intensity` to.
  final double sunIntensity;

  /// The ambient light's colour.
  final LinearColor ambientColor;

  /// How strong the ambient light is, in lux (since 1.0), what [applyTo]
  /// sets `Scene.ambientIntensity` to. About 1 737 lux by default, the 0.3 it
  /// was in the engine's own unit.
  final double ambientIntensity;

  /// [a] blended towards [b] by [t], each part by the same amount.
  static Atmosphere lerp(Atmosphere a, Atmosphere b, double t) {
    final k = t.clamp(0.0, 1.0);
    LinearColor mix(LinearColor x, LinearColor y) => LinearColor.lerp(x, y, k);
    double blend(double x, double y) => x + (y - x) * k;
    return Atmosphere(
      sky: mix(a.sky, b.sky),
      fogColor: mix(a.fogColor, b.fogColor),
      fogDensity: blend(a.fogDensity, b.fogDensity),
      fogHeightFalloff: blend(a.fogHeightFalloff, b.fogHeightFalloff),
      fogBaseHeight: blend(a.fogBaseHeight, b.fogBaseHeight),
      sunColor: mix(a.sunColor, b.sunColor),
      sunIntensity: blend(a.sunIntensity, b.sunIntensity),
      ambientColor: mix(a.ambientColor, b.ambientColor),
      ambientIntensity: blend(a.ambientIntensity, b.ambientIntensity),
    );
  }

  /// The fog this atmosphere draws with, for `RenderSettings.fog`.
  FogSettings get fog => FogSettings(
    color: fogColor,
    density: fogDensity,
    heightFalloff: fogHeightFalloff,
    baseHeight: fogBaseHeight,
  );

  /// Puts this atmosphere on [scene]'s ambient light and on [sun], and
  /// writes the sky into [clearColorSrgb] if given (a view's
  /// `RenderView.clearColorSrgb` is read every frame, so writing into it is
  /// enough). The sky is linear and the clear colour is sRGB, so it is
  /// encoded on the way.
  void applyTo(Scene scene, {LightNode? sun, Vector4? clearColorSrgb}) {
    scene
      ..ambientColor = ambientColor
      ..ambientIntensity = ambientIntensity;
    if (sun != null) {
      sun
        ..color = sunColor
        ..intensity = sunIntensity;
    }
    final (:r, :g, :b, a: _) = sky.toSrgb();
    clearColorSrgb?.setValues(r, g, b, 1.0);
  }
}

final class AtmosphereCycle {
  AtmosphereCycle(List<(double, Atmosphere)> keys, {required this.period})
    : keys = List<(double, Atmosphere)>.unmodifiable(
        List<(double, Atmosphere)>.of(keys)
          ..sort((a, b) => a.$1.compareTo(b.$1)),
      ) {
    if (keys.isEmpty) throw ArgumentError('A cycle with no atmosphere.');
    if (!(period > 0.0)) throw ArgumentError('A cycle of $period.');
  }

  final List<(double, Atmosphere)> keys;

  /// How long one cycle is, in the unit the keys' times and [at]'s time are
  /// counted in: seconds, for a clock that adds its `dt`.
  final double period;

  /// The air at [time], wrapped into the cycle.
  Atmosphere at(double time) {
    if (keys.length == 1) return keys.single.$2;
    final t = time % period;
    for (var i = 0; i < keys.length; i++) {
      final (start, from) = keys[i];
      final (nextAt, to) = keys[(i + 1) % keys.length];
      final end = i + 1 < keys.length ? nextAt : nextAt + period;
      final here = t < keys.first.$1 ? t + period : t;
      if (here >= start && here < end) {
        return Atmosphere.lerp(from, to, (here - start) / (end - start));
      }
    }
    return keys.last.$2;
  }
}

/// Lights turned up and down together: a car's headlamps, a street's
/// lamps, a room's.
///
/// **Their own brightness, kept.** Dimming a group by writing each light's
/// intensity lost what each was meant to be, and a group dimmed to nothing
/// and brought back came back all alike. Each light's intensity when it
/// joins the group is its full brightness, and [level] is the share of it
/// every light shows.
final class LightGroup {
  LightGroup(Iterable<LightNode> lights)
    : _lights = <(LightNode, double)>[
        for (final light in lights) (light, light.intensity),
      ];

  final List<(LightNode, double)> _lights;
  double _level = 1.0;

  /// The lights in the group.
  Iterable<LightNode> get lights => _lights.map((entry) => entry.$1);

  /// How bright the group is, from 0 (off) up; 1 is each light as it was
  /// when it joined.
  /// A unitless multiplier on each light's intensity.
  double get level => _level;
  set level(double value) {
    _level = value < 0.0 ? 0.0 : value;
    for (final (light, full) in _lights) {
      light.intensity = full * _level;
    }
  }
}
