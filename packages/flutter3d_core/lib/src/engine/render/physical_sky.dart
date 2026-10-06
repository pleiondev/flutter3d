/// The sky as air rather than as colours somebody chose — `P5`.
///
/// `SkySettings` draws a gradient from three colours, which is right for a
/// level with a look and wrong for a day: dusk is a different three colours
/// that somebody has to pick, and the sun's disc stays the colour it was given
/// while the light it is meant to be goes orange. A [PhysicalSky] is the air
/// itself — how much it scatters, how thick it is and how fast it thins — and
/// the colours come out of where the sun is: blue overhead at noon, a white
/// band at the horizon, red at sunset towards the sun and dark away from it,
/// and stars once the sun is far enough down.
///
/// Set on `SkySettings.physical`, beside the gradient and the cube map rather
/// than instead of them. A sky switched on with none of the gradient's colours
/// given draws `const PhysicalSky()` without being asked; see
/// `SkySettings.resolvedPhysical`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The air of a planet, for `SkySettings.physical`.
///
/// **Single scattering by molecules and by haze, marched per pixel.** Light
/// from the sun is scattered once on its way to the eye: by molecules, after
/// Rayleigh, in proportion to the inverse fourth power of the wavelength, which
/// is why the sky is blue and the sun red through a long path; and by haze,
/// after Mie, white and mostly forwards, which is the glow round the sun.
/// Light scattered twice is not modelled, and that shows at the horizon, which
/// is a pale cyan at noon rather than white.
///
/// The defaults are the Earth's, from Bruneton's 2017 reference model: the
/// molecular coefficients for 680, 550 and 440 nm, a scale height of eight
/// kilometres for molecules and 1.2 for haze, and 60 km of air. Change them for
/// a thicker or hazier sky, or another planet.
///
/// **Lengths are in metres**, as everything else in the engine is; the
/// renderer hands the shader kilometres, for the precision its docstring gives.
/// The world the camera stands in is flat and small beside the planet, so the
/// camera's own position does not move the sky: the eye is always [altitude]
/// metres above the ground, wherever the level puts it.
///
/// **What the sky costs.** Sixteen samples along every view ray and eight
/// towards the sun from each, per pixel the sky covers — the sky is drawn
/// after the opaque geometry and only where nothing stands. On a desktop GPU
/// that is nothing to speak of; on a phone a frame that is mostly sky pays for
/// it. A precomputed table would make it a texture read, and is not done yet.
final class PhysicalSky {
  const PhysicalSky({
    this.rayleigh,
    this.rayleighScaleHeight = 8000.0,
    this.mie = 3.996e-6,
    this.mieAbsorption = 0.444e-6,
    this.mieScaleHeight = 1200.0,
    this.mieAnisotropy = 0.8,
    this.planetRadius = 6360000.0,
    this.atmosphereHeight = 60000.0,
    this.altitude = 200.0,
    this.sunIlluminance = 20.0,
    this.groundAlbedo = 0.3,
    this.starBrightness = 1.0,
    this.starDensity = 0.02,
    this.starCells = 160,
  });

  /// Molecular scattering at the ground, per metre, for red, green and blue.
  /// Null takes [resolvedRayleigh], the Earth's.
  final Vector3? rayleigh;

  Vector3 get resolvedRayleigh => rayleigh ?? _earthRayleigh;

  // A getter rather than a `static final`: a `Vector3` is mutable, and a shared
  // one is a global that looks like a constant — see `SkySettings`.
  static Vector3 get _earthRayleigh => Vector3(5.802e-6, 13.558e-6, 33.1e-6);

  /// The height over which the molecules thin by a factor of e, in metres.
  final double rayleighScaleHeight;

  /// Haze: how much it scatters at the ground and how much more it absorbs,
  /// per metre, the same in every channel. Raise [mie] for a hazy summer
  /// afternoon; its glow round the sun widens and the horizon whitens.
  final double mie;
  final double mieAbsorption;

  /// The height over which the haze thins by a factor of e, in metres.
  final double mieScaleHeight;

  /// Which way haze scatters: Henyey–Greenstein's g, held inside ±0.99. 0.8 is
  /// strongly forwards, the bright glow a sun has through haze.
  final double mieAnisotropy;

  final double planetRadius;

  /// How far above the ground the air ends, in metres.
  final double atmosphereHeight;

  /// How high the eye is above the ground, in metres; held inside the air.
  final double altitude;

  /// The sunlight entering the air, in the units the scene's light has. Twenty
  /// puts a noon zenith near 0.1, 0.2, 0.4 and the horizon near one, which
  /// sits beside a directional light of intensity two or three under the
  /// default exposure.
  final double sunIlluminance;

  /// How much of the sunlight that reaches the ground below the horizon it
  /// sends back. The ground is what fills the lower half of an environment
  /// map built from the sky; it is not a terrain, and it is lit by the sun
  /// alone.
  final double groundAlbedo;

  /// How bright the stars are, in the sky's own units; nought for none. They
  /// fade in as the sun goes from six degrees above the horizon to eleven
  /// below, and are dimmed by the air in front of them, so they thin towards
  /// the horizon.
  final double starBrightness;

  /// The share of the grid's cells that hold a star, from nought to one.
  final double starDensity;

  /// How many cells across each face of the cube the stars are scattered on.
  /// 160 puts about half a degree between neighbours.
  final int starCells;

  /// [mieAnisotropy], held where the phase function stays finite.
  double get resolvedAnisotropy => mieAnisotropy.clamp(-0.99, 0.99);

  /// The eye's distance from the planet's centre, in metres, held inside the
  /// air: an eye above it would have no air to march through towards the
  /// ground.
  double get eyeRadius =>
      planetRadius + altitude.clamp(0.0, atmosphereHeight * 0.999);

  /// The light the air sends towards the eye along [direction], with the sun
  /// along [toSun]: the scattered light, plus the ground where the ray meets
  /// it. No disc and no stars.
  ///
  /// The same arithmetic `sky_physical.frag` runs, in double precision; the
  /// lengths are kilometres here too, so that the two agree to the extent
  /// single precision lets them. [direction] and [toSun] need not be
  /// normalised.
  Vector3 radiance(Vector3 direction, Vector3 toSun) =>
      look(direction, toSun).radiance;

  /// [radiance], with what the air lets through along the same ray and
  /// whether the ray ends at the ground — what the disc and the stars are
  /// dimmed by, and what decides whether there is a disc at all.
  ({Vector3 radiance, Vector3 transmittance, bool ground}) look(
    Vector3 direction,
    Vector3 toSun,
  ) {
    final d = _unit(direction, Vector3(0.0, 0.0, 1.0));
    final s = _unit(toSun, Vector3(0.0, 1.0, 0.0));
    final k = PhysicalSkyKilometres(this);
    final eyeR = k.eye;

    final ground = _meet(eyeR, d.y, k.planet);
    final grounded = ground > 0.0;
    final span = grounded ? ground : _leave(eyeR, d.y, k.top);

    var seenR = 0.0, seenM = 0.0;
    final molecules = Vector3.zero();
    final haze = Vector3.zero();
    for (var i = 0; i < _viewSteps; i++) {
      final a0 = i / _viewSteps;
      final a1 = (i + 1) / _viewSteps;
      final t = span * 0.5 * (a0 * a0 + a1 * a1);
      final stride = span * (a1 * a1 - a0 * a0);
      final p = Vector3(d.x * t, eyeR + d.y * t, d.z * t);
      final r = p.length;
      final h = r - k.planet;
      final airR = math.exp(-h / k.rayleighHeight) * stride;
      final airM = math.exp(-h / k.mieHeight) * stride;
      seenR += airR;
      seenM += airM;
      if (_meet(r, p.dot(s) / r, k.planet) > 0.0) continue;
      final (sunR, sunM) = _sunwardAir(p, s, k);
      final through = k.through(
        seenR - 0.5 * airR + sunR,
        seenM - 0.5 * airM + sunM,
      );
      molecules.addScaled(through, airR);
      haze.addScaled(through, airM);
    }

    final mu = d.dot(s);
    final g = resolvedAnisotropy;
    final gg = g * g;
    final rayleighPhase = 3.0 / (16.0 * math.pi) * (1.0 + mu * mu);
    final miePhase =
        3.0 /
        (8.0 * math.pi) *
        ((1.0 - gg) * (1.0 + mu * mu)) /
        ((2.0 + gg) * math.pow(1.0 + gg - 2.0 * g * mu, 1.5));

    final colour = Vector3(
      molecules.x * k.rayleigh.x * rayleighPhase + haze.x * k.mie * miePhase,
      molecules.y * k.rayleigh.y * rayleighPhase + haze.y * k.mie * miePhase,
      molecules.z * k.rayleigh.z * rayleighPhase + haze.z * k.mie * miePhase,
    )..scale(sunIlluminance);
    final seen = k.through(seenR, seenM);

    if (grounded) {
      final p = Vector3(d.x * span, eyeR + d.y * span, d.z * span);
      final lit = p.normalized().dot(s);
      if (lit > 0.0) {
        final (sunR, sunM) = _sunwardAir(p, s, k);
        final sun = k.through(sunR, sunM);
        final scale = groundAlbedo / math.pi * lit * sunIlluminance;
        colour
          ..x += seen.x * sun.x * scale
          ..y += seen.y * sun.y * scale
          ..z += seen.z * sun.z * scale;
      }
    }

    return (radiance: colour, transmittance: seen, ground: grounded);
  }

  /// What the air leaves of white sunlight on its way down to the eye, from
  /// a sun along [toSun]: the colour a directional light standing for the sun
  /// should have, with [sunIlluminance] left out. Nought once the sun is
  /// below the horizon.
  Vector3 sunlight(Vector3 toSun) {
    final s = _unit(toSun, Vector3(0.0, 1.0, 0.0));
    final k = PhysicalSkyKilometres(this);
    final eye = Vector3(0.0, k.eye, 0.0);
    if (_meet(k.eye, s.y, k.planet) > 0.0) return Vector3.zero();
    final (r, m) = _sunwardAir(eye, s, k);
    return k.through(r, m);
  }

  PhysicalSky copyWith({
    Vector3? rayleigh,
    double? rayleighScaleHeight,
    double? mie,
    double? mieAbsorption,
    double? mieScaleHeight,
    double? mieAnisotropy,
    double? planetRadius,
    double? atmosphereHeight,
    double? altitude,
    double? sunIlluminance,
    double? groundAlbedo,
    double? starBrightness,
    double? starDensity,
    int? starCells,
  }) => PhysicalSky(
    rayleigh: rayleigh ?? this.rayleigh,
    rayleighScaleHeight: rayleighScaleHeight ?? this.rayleighScaleHeight,
    mie: mie ?? this.mie,
    mieAbsorption: mieAbsorption ?? this.mieAbsorption,
    mieScaleHeight: mieScaleHeight ?? this.mieScaleHeight,
    mieAnisotropy: mieAnisotropy ?? this.mieAnisotropy,
    planetRadius: planetRadius ?? this.planetRadius,
    atmosphereHeight: atmosphereHeight ?? this.atmosphereHeight,
    altitude: altitude ?? this.altitude,
    sunIlluminance: sunIlluminance ?? this.sunIlluminance,
    groundAlbedo: groundAlbedo ?? this.groundAlbedo,
    starBrightness: starBrightness ?? this.starBrightness,
    starDensity: starDensity ?? this.starDensity,
    starCells: starCells ?? this.starCells,
  );

  // The march's lengths, which the shader has as constants too.
  static const int _viewSteps = 16;
  static const int _lightSteps = 8;

  /// `SunwardAir` from `sky_physical.frag`: the air between [p] and space
  /// towards [s], as lengths at ground density, molecules then haze.
  static (double, double) _sunwardAir(
    Vector3 p,
    Vector3 s,
    PhysicalSkyKilometres k,
  ) {
    final r = p.length;
    final span = _leave(r, p.dot(s) / r, k.top);
    final stride = span / _lightSteps;
    var airR = 0.0, airM = 0.0;
    for (var j = 0; j < _lightSteps; j++) {
      final u = (j + 0.5) * stride;
      final qx = p.x + s.x * u;
      final qy = p.y + s.y * u;
      final qz = p.z + s.z * u;
      final h = math.sqrt(qx * qx + qy * qy + qz * qz) - k.planet;
      airR += math.exp(-h / k.rayleighHeight) * stride;
      airM += math.exp(-h / k.mieHeight) * stride;
    }
    return (airR, airM);
  }

  /// `Leave`: how far a ray from radius [r] at cosine [mu] runs before it
  /// leaves a sphere of [radius], negative when it misses.
  static double _leave(double r, double mu, double radius) {
    final b = r * mu;
    final d = b * b - (r - radius) * (r + radius);
    return d < 0.0 ? -1.0 : -b + math.sqrt(d);
  }

  /// `Meet`: how far the same ray runs before it meets the sphere from
  /// outside, negative when it does not.
  static double _meet(double r, double mu, double radius) {
    final b = r * mu;
    final d = b * b - (r - radius) * (r + radius);
    return d < 0.0 ? -1.0 : -b - math.sqrt(d);
  }

  static Vector3 _unit(Vector3 v, Vector3 otherwise) {
    final length = v.length;
    return length > 0.0 ? v / length : otherwise;
  }
}

/// A [PhysicalSky]'s numbers in the units the shader takes them in:
/// kilometres for lengths, per kilometre for coefficients.
///
/// One conversion for both readers, so that the renderer, which writes these
/// onto the sky's vertices, and [PhysicalSky.look], which marches with them,
/// cannot convert differently. Not exported: it is the shader's view of the
/// settings, not a thing to set.
final class PhysicalSkyKilometres {
  PhysicalSkyKilometres(PhysicalSky sky)
    : rayleigh = sky.resolvedRayleigh * 1000.0,
      rayleighHeight = sky.rayleighScaleHeight / 1000.0,
      mie = sky.mie * 1000.0,
      mieExtinction = (sky.mie + sky.mieAbsorption) * 1000.0,
      mieHeight = sky.mieScaleHeight / 1000.0,
      planet = sky.planetRadius / 1000.0,
      top = (sky.planetRadius + sky.atmosphereHeight) / 1000.0,
      eye = sky.eyeRadius / 1000.0;

  /// Molecular scattering per km, and its scale height in km.
  final Vector3 rayleigh;
  final double rayleighHeight;

  /// Haze scattering and extinction per km, and its scale height in km.
  final double mie;
  final double mieExtinction;
  final double mieHeight;

  /// The radii of the ground, the top of the air and the eye, in km.
  final double planet;
  final double top;
  final double eye;

  /// `Through`: what a length of air lets through, per channel.
  Vector3 through(double molecules, double haze) => Vector3(
    math.exp(-(rayleigh.x * molecules + mieExtinction * haze)),
    math.exp(-(rayleigh.y * molecules + mieExtinction * haze)),
    math.exp(-(rayleigh.z * molecules + mieExtinction * haze)),
  );
}
