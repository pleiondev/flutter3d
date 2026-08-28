/// The air a circuit sits in: what the sky is, and what the distance is.
///
/// This is arithmetic, not drawing. Nothing here imports the renderer, and
/// `isolation_test.dart` keeps it that way — a preset is a handful of colours
/// and angles, and the two things it answers are "what colour is the sky in
/// this direction" and "what colour is the haze between here and that hill".
///
/// **Why the fog needs help, and still does.** The engine's fog is one constant
/// colour mixed in by distance (`color.glsl`: `mix(fog.rgb, colour, exp(-density
/// * d))`). It has no idea which way the camera is pointing, so a corner taken into the sun and
/// the same corner taken away from it fade into exactly the same grey. That is
/// the failure Hoffman and Preetham named in 2002, and it is what makes distance
/// look like a wash rather than like air. The fix does not need a shader: the
/// colour handed to `FogSettings` is recomputed each frame from where the camera
/// is looking, by [inScatterAlong]. The shader stays a mix; the thing being
/// mixed toward becomes directional.
///
/// **Two things this file used to say it could not have, and now has.** Both
/// arrived in the engine after this was written, and the paragraph stood
/// unchanged long enough to be worth naming as a hazard: a comment that
/// explains why something is impossible is exactly the comment nobody rereads.
///
/// - *An ambient colour.* It said the renderer wrote one number and the shader
///   read it as a scalar, so a colour would change nothing. The shader now
///   blends [ambient_sky] and [ambient_ground] by which way a surface faces,
///   and the renderer builds both from the sky's own gradient — so a preset
///   already tints the ambient, through [zenith], [horizon] and [belowHorizon],
///   and [ambientIntensity] is what it always was: the overall strength. A
///   separate ambient colour would now be a *second* answer to a question the
///   gradient already answers, which is a better reason to leave it out than
///   the old one.
/// - *A sun disc.* It said there was nowhere to put one without a dome. The
///   renderer draws the sky itself now, in the shader, so the disc costs no
///   geometry — and [sunDisc] is a real field that four of the five presets set.
///   The wide scattering lobe ([glowWide]) is still what reads at speed; the
///   disc is what makes a low sun something a driver squints at.
///
/// There is still no sky *dome*, and that reasoning has not aged: a sphere
/// around the camera is a shadow caster by default and, worse,
/// `Scene.computeBounds` counts it — the scene radius jumps by a kilometre and
/// a half, the last shadow cascade is fitted to that, and the texel snapping
/// that stops shadow edges crawling stops holding. What the engine draws is not
/// a dome; it is the background, evaluated per pixel.
///
/// [colourAt] is still the CPU's copy of that gradient, and still earns its
/// place twice over: the view's clear colour before the first circuit has
/// loaded, and the fog colour below — which is the one thing the engine's sky
/// does *not* do for us.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'sky_presets.dart';

/// A time of day: the sun, the gradient, the haze and the exposure that go with
/// it.
///
/// One object rather than a handful of constants spread across the application
/// because they are not independent. A morning sun with a noon fog colour is a
/// picture where the far side of the circuit is lit by a different star, and the
/// only way to be sure that never happens is for the fog colour never to be
/// authored at all — it is [horizonFogColour], derived from the same two
/// colours the sky is drawn from.
final class SkyPreset {
  const SkyPreset({
    required this.name,
    required this.sunElevationDeg,
    required this.sunAzimuthDeg,
    required this.sunColor,
    required this.sunIntensity,
    required this.zenith,
    required this.horizon,
    required this.belowHorizon,
    required this.glowWide,
    required this.glowStrength,
    required this.fogDensity,
    required this.fogBacklitExponent,
    required this.fogBacklitStrength,
    required this.ambientIntensity,
    required this.exposure,
    this.sunDisc = 0.0,
  });

  /// Which preset this is, for a debug readout and for a test that wants to say
  /// which one it is looking at.
  final String name;

  /// Degrees above the horizon. Zero is sunrise; ninety is directly overhead.
  final double sunElevationDeg;

  /// Degrees clockwise from north, in the same frame the track is laid out in.
  final double sunAzimuthDeg;

  /// The colour and strength of the directional light. The generator derives the
  /// level's one sun from these rather than repeating them.
  final Vector3 sunColor;
  final double sunIntensity;

  /// The sky straight up, at the horizon, and below it.
  ///
  /// [belowHorizon] is what the sky reads as when the camera is looking down at
  /// nothing — over the edge of an elevated section, mostly. It is the ground's
  /// haze rather than the sky's, and it is darker for it.
  final Vector3 zenith;
  final Vector3 horizon;
  final Vector3 belowHorizon;

  /// The wide scattering lobe around the sun: how sharp it is, and how bright.
  ///
  /// Sharp enough to be a direction and blunt enough not to be a disc. Around
  /// six is a lobe some tens of degrees wide, which is the part of a sunlit sky
  /// a driver actually notices.
  final double glowWide;
  final double glowStrength;

  /// Haze per metre, in the units `FogSettings` wants.
  final double fogDensity;

  /// How much brighter the haze is when looking into the sun.
  ///
  /// This is the whole point of the file. Air scatters forward, so looking
  /// towards the sun through a kilometre of it is bright and looking away is
  /// not, and a game that misses this has one grey for every direction.
  final double fogBacklitExponent;
  final double fogBacklitStrength;

  /// What the renderer is told about the light that is not the sun, and how much
  /// light the camera is set for.
  final double ambientIntensity;
  final double exposure;

  /// How bright the sun's own disc is, or zero for none.
  ///
  /// The disc is the one thing a painted dome could not have: it is about half a
  /// degree across, and a dome fine enough to resolve one would need rings a
  /// fraction of a degree apart. Drawn per pixel it is an analytic shape and its
  /// size is a number. Far above one on purpose — the target is HDR, and a sun
  /// that cannot blow out is a sun bloom has nothing to find.
  ///
  /// Zero at dusk, because the sun has gone.
  final double sunDisc;

  /// Which way the light travels, pointing **from** the sun.
  ///
  /// The sign is the one a directional light wants: this is the direction
  /// photons move, so at dawn, with the sun low in the east, it points west and
  /// slightly down.
  Vector3 get sunDirection {
    final toSun = directionToSun;
    return Vector3(-toSun.x, -toSun.y, -toSun.z);
  }

  /// Which way the sun is, as seen from the track: a unit vector pointing up at
  /// it.
  Vector3 get directionToSun {
    final elevation = sunElevationDeg * _degrees;
    final azimuth = sunAzimuthDeg * _degrees;
    final flat = math.cos(elevation);
    return Vector3(
      flat * math.sin(azimuth),
      math.sin(elevation),
      flat * math.cos(azimuth),
    );
  }

  /// The colour of the sky in [direction], which need not be normalised.
  ///
  /// Two parts. The gradient is a smoothstep in height so the band near the
  /// horizon is wide and the zenith is flat, which is roughly what the sky does
  /// and is certainly what a linear ramp does not. On top of it sits the wide
  /// lobe around the sun, added rather than mixed, because scattered light is
  /// light arriving and not paint.
  Vector3 colourAt(Vector3 direction) {
    final length = direction.length;
    if (length <= 0.0) return Vector3.copy(horizon);
    final y = (direction.y / length).clamp(-1.0, 1.0);

    final Vector3 base;
    if (y >= 0.0) {
      // Squared rather than linear so the horizon band is wide: half the sky's
      // visible interest happens in the first fifteen degrees.
      final t = _smoothstep(y);
      base = Vector3(
        horizon.x + (zenith.x - horizon.x) * t,
        horizon.y + (zenith.y - horizon.y) * t,
        horizon.z + (zenith.z - horizon.z) * t,
      );
    } else {
      final t = _smoothstep(-y);
      base = Vector3(
        horizon.x + (belowHorizon.x - horizon.x) * t,
        horizon.y + (belowHorizon.y - horizon.y) * t,
        horizon.z + (belowHorizon.z - horizon.z) * t,
      );
    }

    final toSun = directionToSun;
    final towards =
        (direction.x * toSun.x +
            direction.y * toSun.y +
            direction.z * toSun.z) /
        length;
    if (towards <= 0.0) return base;
    final lobe = glowStrength * math.pow(towards, glowWide).toDouble();
    return Vector3(
      base.x + sunColor.x * lobe,
      base.y + sunColor.y * lobe,
      base.z + sunColor.z * lobe,
    );
  }

  /// The colour distance settles to, level with the horizon and ninety degrees
  /// from the sun.
  ///
  /// It is [colourAt] of exactly that direction, and that is the point: the far
  /// side of the circuit fades into the same colour the sky is, so there is no
  /// band where the ground ends and no way for the two to be authored apart.
  /// The generator writes this into the level's `fogColor` by computing it the
  /// same way, which is why `fogColor` is not a field anybody types.
  Vector3 get horizonFogColour {
    final toSun = directionToSun;
    // Perpendicular to the sun in the ground plane, so the neutral haze is not
    // the sun's own glow. A sun straight overhead has no azimuth worth speaking
    // of, and any horizontal direction will do — hence the fallback.
    var across = Vector3(toSun.z, 0.0, -toSun.x);
    if (across.length2 < 1e-9) across = Vector3(1.0, 0.0, 0.0);
    return colourAt(across.normalized());
  }

  /// The haze colour for a camera looking along [viewDir].
  ///
  /// The neutral haze, brightened towards the sun. What this buys, in one
  /// sentence: the same corner is a different picture depending on which way it
  /// is taken, and a car ahead in the distance is a silhouette into the sun and
  /// a shape away from it.
  Vector3 inScatterAlong(Vector3 viewDir) {
    final base = horizonFogColour;
    final length = viewDir.length;
    if (length <= 0.0) return base;
    final toSun = directionToSun;
    final towards =
        (viewDir.x * toSun.x + viewDir.y * toSun.y + viewDir.z * toSun.z) /
        length;
    if (towards <= 0.0) return base;
    final boost =
        1.0 +
        fogBacklitStrength * math.pow(towards, fogBacklitExponent).toDouble();
    return Vector3(base.x * boost, base.y * boost, base.z * boost);
  }

  /// Reads a preset out of a track file's `"sky"` block, falling back field by
  /// field to [SkyPresets.morning].
  ///
  /// Field by field rather than all or nothing, so a generator that grows a new
  /// key does not have to rewrite every fixture that predates it, and so a
  /// fixture that only cares about the sun's angle can say only that.
  factory SkyPreset.fromJson(Map<String, Object?> json) {
    final SkyPreset fallback = SkyPresets.morning;
    double number(String key, double fallbackValue) {
      final value = json[key];
      return value is num ? value.toDouble() : fallbackValue;
    }

    // **A colour with a word in it used to come out partly black**, because
    // each component that was not a number became nought on its own. The
    // shared reader takes all three or none, which for a preset means the time
    // of day it was falling back to anyway.
    Vector3 colour(String key, Vector3 fallbackValue) {
      final out = Vector3.zero();
      return readVector(json[key], out) ? out : fallbackValue;
    }

    final name = json['name'];
    return SkyPreset(
      name: name is String ? name : fallback.name,
      sunElevationDeg: number('sunElevationDeg', fallback.sunElevationDeg),
      sunAzimuthDeg: number('sunAzimuthDeg', fallback.sunAzimuthDeg),
      sunColor: colour('sunColor', fallback.sunColor),
      sunIntensity: number('sunIntensity', fallback.sunIntensity),
      zenith: colour('zenith', fallback.zenith),
      horizon: colour('horizon', fallback.horizon),
      belowHorizon: colour('belowHorizon', fallback.belowHorizon),
      glowWide: number('glowWide', fallback.glowWide),
      glowStrength: number('glowStrength', fallback.glowStrength),
      fogDensity: number('fogDensity', fallback.fogDensity),
      fogBacklitExponent: number(
        'fogBacklitExponent',
        fallback.fogBacklitExponent,
      ),
      fogBacklitStrength: number(
        'fogBacklitStrength',
        fallback.fogBacklitStrength,
      ),
      ambientIntensity: number('ambientIntensity', fallback.ambientIntensity),
      exposure: number('exposure', fallback.exposure),
      sunDisc: number('sunDisc', fallback.sunDisc),
    );
  }
}

/// The usual 3t² − 2t³ on a value already known to be in range.
double _smoothstep(double t) => t * t * (3.0 - 2.0 * t);

const double _degrees = math.pi / 180.0;
