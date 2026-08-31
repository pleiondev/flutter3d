import 'package:vector_math/vector_math.dart';

import 'sky.dart';

/// The times of day the generator can write, and the one an application falls
/// back to.
///
/// Kept here rather than only in the Python so that a test, a fixture and an
/// application that loads a track with no `"sky"` block all agree about what
/// morning looks like. The generator holds the same five and is where the choice
/// is made.
abstract final class SkyPresets {
  /// First light: a low red sun, a cold sky, and haze thick enough to hide the
  /// far side of the circuit.
  static final SkyPreset dawn = SkyPreset(
    name: 'dawn',
    sunElevationDeg: 4.0,
    sunAzimuthDeg: 95.0,
    sunColor: Vector3(1.0, 0.62, 0.38),
    sunIntensity: 2.1,
    zenith: Vector3(0.16, 0.24, 0.42),
    horizon: Vector3(0.72, 0.52, 0.44),
    belowHorizon: Vector3(0.16, 0.15, 0.17),
    glowWide: 5.0,
    glowStrength: 0.55,
    fogDensity: 0.0060,
    fogBacklitExponent: 5.0,
    fogBacklitStrength: 0.45,
    ambientIntensity: 0.08,
    exposure: 1.85,
    sunDisc: 26.0,
  );

  /// The default: a clear morning, sun a third of the way up, air you can see
  /// the whole lap through.
  static final SkyPreset morning = SkyPreset(
    name: 'morning',
    sunElevationDeg: 34.0,
    sunAzimuthDeg: 112.0,
    sunColor: Vector3(1.0, 0.95, 0.86),
    sunIntensity: 3.1,
    zenith: Vector3(0.26, 0.42, 0.72),
    horizon: Vector3(0.66, 0.75, 0.85),
    belowHorizon: Vector3(0.20, 0.21, 0.22),
    glowWide: 6.0,
    glowStrength: 0.30,
    fogDensity: 0.0042,
    fogBacklitExponent: 6.0,
    fogBacklitStrength: 0.35,
    ambientIntensity: 0.10,
    exposure: 1.6,
    sunDisc: 14.0,
  );

  /// Overhead and flat: the least interesting light there is, and the one that
  /// shows whether the track reads without any help from the sky.
  static final SkyPreset noon = SkyPreset(
    name: 'noon',
    sunElevationDeg: 78.0,
    sunAzimuthDeg: 150.0,
    sunColor: Vector3(1.0, 0.99, 0.96),
    sunIntensity: 3.6,
    zenith: Vector3(0.20, 0.38, 0.76),
    horizon: Vector3(0.62, 0.72, 0.86),
    belowHorizon: Vector3(0.22, 0.23, 0.24),
    glowWide: 8.0,
    glowStrength: 0.18,
    fogDensity: 0.0030,
    fogBacklitExponent: 8.0,
    fogBacklitStrength: 0.22,
    ambientIntensity: 0.12,
    exposure: 1.45,
    sunDisc: 9.0,
  );

  /// Late, low and warm — the hour every racing game photographs itself in, and
  /// the one where looking into the sun and away from it are most obviously
  /// different places.
  static final SkyPreset golden = SkyPreset(
    name: 'golden',
    sunElevationDeg: 11.0,
    sunAzimuthDeg: 285.0,
    sunColor: Vector3(1.0, 0.78, 0.52),
    sunIntensity: 2.6,
    zenith: Vector3(0.22, 0.34, 0.60),
    horizon: Vector3(0.86, 0.62, 0.40),
    belowHorizon: Vector3(0.20, 0.17, 0.15),
    glowWide: 4.5,
    glowStrength: 0.70,
    fogDensity: 0.0050,
    fogBacklitExponent: 4.5,
    fogBacklitStrength: 0.60,
    ambientIntensity: 0.09,
    exposure: 1.75,
    sunDisc: 34.0,
  );

  /// After the sun has gone: no direction left in the light, and the haze goes
  /// blue instead of warm.
  static final SkyPreset dusk = SkyPreset(
    name: 'dusk',
    sunElevationDeg: -2.0,
    sunAzimuthDeg: 292.0,
    sunColor: Vector3(0.72, 0.60, 0.66),
    sunIntensity: 1.2,
    zenith: Vector3(0.10, 0.14, 0.30),
    horizon: Vector3(0.44, 0.38, 0.48),
    belowHorizon: Vector3(0.09, 0.09, 0.12),
    glowWide: 4.0,
    glowStrength: 0.40,
    fogDensity: 0.0075,
    fogBacklitExponent: 4.0,
    fogBacklitStrength: 0.30,
    ambientIntensity: 0.14,
    exposure: 2.05,
    sunDisc: 0.0,
  );

  static final List<SkyPreset> all = <SkyPreset>[
    dawn,
    morning,
    noon,
    golden,
    dusk,
  ];

  /// The preset of that name, or null. Used by a debug key and by tests; an
  /// application reads its sky from the track file, not from a name.
  static SkyPreset? byName(String name) {
    for (final preset in all) {
      if (preset.name == name) return preset;
    }
    return null;
  }
}
