/// The sky, gradient, cube-mapped and physical: `sky.vert`, `sky_cube.vert`,
/// `sky.frag`, `sky_cube.frag` and `sky_physical.frag`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `sky.vert`: a full-screen triangle at the far plane, carrying its own data.
///
/// **Everything the fragment stage needs arrives on the vertices, and it is not
/// this backend that needed that.** The GLSL this transcribes used to take a
/// matrix and a preset as uniform blocks; on Impeller those never reached the
/// sky's pipeline — see the note at the top of `sky.vert` for what was measured
/// — and a vertex attribute did. This backend could have kept reading uniforms
/// and been right on its own, which is exactly the kind of divergence that
/// makes a transcription stop being one.
///
/// The two constants that have to match the GLSL are the output depth 0.999999
/// — the far plane less a hair, so the ordinary `less` test passes against a
/// buffer cleared to 1.0 — and the layout below. `sky_frame_test.dart` pins the
/// depth against the text of the shader itself, because a drift between the two
/// is a sky that is either invisible or in front of the world.
final class SkyVertexShader implements CpuVertexShader {
  const SkyVertexShader();

  /// The ray, then the six vec4s of preset.
  @override
  int get varyingCount => 3 + 6 * 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    // Attribute 0..1 is the clip-space corner; the rest is what the fragment
    // stage reads, passed straight through.
    for (var i = 0; i < varyingCount; i++) {
      out[i] = a[2 + i];
    }
    return Vector4(a[0], a[1], 0.999999, 1.0);
  }
}

/// `sky_cube.vert`: the same triangle, carrying a tint instead of a preset.
final class SkyCubeVertexShader implements CpuVertexShader {
  const SkyCubeVertexShader();

  @override
  int get varyingCount => 3 + 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    for (var i = 0; i < varyingCount; i++) {
      out[i] = a[2 + i];
    }
    return Vector4(a[0], a[1], 0.999999, 1.0);
  }
}

/// `sky.frag`: the gradient, the scattering lobe and the disc.
///
/// Transcribed rather than shared with the engine's own copy of this model, and
/// that is the standing arrangement here: `flutter3d` is a dev dependency of
/// this package and not a dependency, because a software backend that needs the
/// engine to draw a triangle is not a backend. `tonemapNeutral` is the same
/// bargain. What keeps the two honest is a test that evaluates both.
final class SkyShader implements CpuFragmentShader {
  const SkyShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    final scale = length > 0.0 ? 1.0 / length : 0.0;
    final dx = v[0] * scale;
    final dy = v[1] * scale;
    final dz = v[2] * scale;

    // The preset, off the varyings rather than out of a uniform block — see
    // [SkyVertexShader].
    final zenith = Vector4(v[3], v[4], v[5], v[6]);
    final horizon = Vector4(v[7], v[8], v[9], v[10]);
    final nadir = Vector4(v[11], v[12], v[13], v[14]);
    final sun = Vector4(v[15], v[16], v[17], v[18]);
    final glow = Vector4(v[19], v[20], v[21], v[22]);
    final disc = Vector4(v[23], v[24], v[25], v[26]);

    final height = dy.clamp(-1.0, 1.0);
    final far = height >= 0.0 ? zenith : nadir;
    final magnitude = height.abs();
    final t = magnitude * magnitude * (3.0 - 2.0 * magnitude);

    var r = horizon.x + (far.x - horizon.x) * t;
    var g = horizon.y + (far.y - horizon.y) * t;
    var bl = horizon.z + (far.z - horizon.z) * t;

    final towards = dx * sun.x + dy * sun.y + dz * sun.z;
    if (towards > 0.0) {
      final lobe = glow.w * math.pow(towards, sun.w).toDouble();
      r += glow.x * lobe;
      g += glow.y * lobe;
      bl += glow.z * lobe;
    }

    // `disc.y` is the width of the soft edge, not the outer cosine: see the
    // renderer, which writes it that way because a varying cannot carry two
    // cosines this close together.
    // A soft edge of nothing is a hard edge, not an absent sun — see the same
    // branch in `sky.frag`, which had the same hole.
    final edge =
        (disc.y > 0.0
            ? smoothstep(disc.x - disc.y, disc.x, towards)
            : (towards >= disc.x ? 1.0 : 0.0)) *
        disc.z;
    r += glow.x * edge;
    g += glow.y * edge;
    bl += glow.z * edge;

    // **The surface is left alone, and that is a transcription of a fix.** The
    // GLSL this mirrors used to declare a second output and write zero into it;
    // on Impeller, in the usual single-attachment pass, that killed the
    // process. Nothing is lost either way — the attachment is cleared to zero,
    // which is the value this was writing — and the two backends have to say
    // the same thing or the transcription stops being one.
    return Vector4(r, g, bl, 1.0);
  }
}

/// `sky_cube.frag`: the same ray, sampled out of a cube map.
///
/// The face table is `BoundTexture.sampleCube`'s, not this file's — written
/// once, where the conformance suite can check it against the other two
/// backends rather than against a reading of the code.
final class SkyCubeShader implements CpuFragmentShader {
  const SkyCubeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    // No surface written, for the reason [SkyShader] gives: the GLSL this
    // mirrors no longer declares a second output.
    final map = b.textures['sky_texture'];
    // A stage bound no cube: black rather than a crash, and black rather than a
    // plausible sky, which is what makes it reportable.
    if (map == null) return Vector4(0.0, 0.0, 0.0, 1.0);

    final texel = map.sampleCube(v[0], v[1], v[2]);
    // Off the varyings, as the preset is — see [SkyVertexShader].
    final tint = Vector4(v[3], v[4], v[5], v[6]);

    return Vector4(
      toLinear(texel.x) * tint.x,
      toLinear(texel.y) * tint.y,
      toLinear(texel.z) * tint.z,
      1.0,
    );
  }
}

/// `sky_physical.frag`: sunlight scattered once by molecules and by haze along
/// the view ray, the disc and the stars through what the air leaves, and the
/// ground below the horizon — `P5`.
///
/// Its vertex stage is [SkyVertexShader] under a second name: the GLSL has a
/// `sky_physical.vert` of its own because varyings are matched by name there,
/// but both pass the same twenty-seven floats straight through, and a copy of
/// a loop that copies would be a transcription of nothing.
///
/// Transcribed from the GLSL line for line, beside a third copy in
/// `PhysicalSky.look`, for the reason [SkyShader] gives. Doubles here and
/// single precision there; the march is smooth enough that the two agree to
/// well under a step of eight bits. The one place that is not smooth is the
/// stars' hash, where a `fract` decides whether a cell holds a star, and there
/// every product is rounded to single precision, as the GPU computes it.
final class SkyPhysicalShader implements CpuFragmentShader {
  const SkyPhysicalShader();

  static const int _viewSteps = 16;
  static const int _lightSteps = 8;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    final scale = length > 0.0 ? 1.0 / length : 0.0;
    final dx = v[0] * scale, dy = v[1] * scale, dz = v[2] * scale;

    final air = _Air(v);
    final sx = v[11], sy = v[12], sz = v[13];
    final eyeR = air.eye;

    final ground = _meet(eyeR, dy, air.planet);
    final grounded = ground > 0.0;
    final span = grounded ? ground : _leave(eyeR, dy, air.top);

    var seenR = 0.0, seenM = 0.0;
    var molR = 0.0, molG = 0.0, molB = 0.0;
    var hazeR = 0.0, hazeG = 0.0, hazeB = 0.0;
    for (var i = 0; i < _viewSteps; i++) {
      final a0 = i / _viewSteps;
      final a1 = (i + 1) / _viewSteps;
      final t = span * 0.5 * (a0 * a0 + a1 * a1);
      final stride = span * (a1 * a1 - a0 * a0);
      final px = dx * t, py = eyeR + dy * t, pz = dz * t;
      final r = math.sqrt(px * px + py * py + pz * pz);
      final h = r - air.planet;
      final airR = math.exp(-h / air.rayleighHeight) * stride;
      final airM = math.exp(-h / air.mieHeight) * stride;
      seenR += airR;
      seenM += airM;
      if (_meet(r, (px * sx + py * sy + pz * sz) / r, air.planet) > 0.0) {
        continue;
      }
      final (sunR, sunM) = air.sunward(px, py, pz, sx, sy, sz);
      final mr = seenR - 0.5 * airR + sunR;
      final mm = seenM - 0.5 * airM + sunM;
      final tr = air.through(0, mr, mm);
      final tg = air.through(1, mr, mm);
      final tb = air.through(2, mr, mm);
      molR += airR * tr;
      molG += airR * tg;
      molB += airR * tb;
      hazeR += airM * tr;
      hazeG += airM * tg;
      hazeB += airM * tb;
    }

    final mu = dx * sx + dy * sy + dz * sz;
    final g = v[10];
    final gg = g * g;
    final rayleighPhase = 3.0 / (16.0 * math.pi) * (1.0 + mu * mu);
    final miePhase =
        3.0 /
        (8.0 * math.pi) *
        ((1.0 - gg) * (1.0 + mu * mu)) /
        ((2.0 + gg) * math.pow(1.0 + gg - 2.0 * g * mu, 1.5));

    final sun = v[14];
    var r = sun * (molR * v[3] * rayleighPhase + hazeR * v[7] * miePhase);
    var gr = sun * (molG * v[4] * rayleighPhase + hazeG * v[7] * miePhase);
    var bl = sun * (molB * v[5] * rayleighPhase + hazeB * v[7] * miePhase);
    final seen0 = air.through(0, seenR, seenM);
    final seen1 = air.through(1, seenR, seenM);
    final seen2 = air.through(2, seenR, seenM);

    if (grounded) {
      final px = dx * span, py = eyeR + dy * span, pz = dz * span;
      final pl = math.sqrt(px * px + py * py + pz * pz);
      final lit = (px * sx + py * sy + pz * sz) / pl;
      if (lit > 0.0) {
        final (sunR, sunM) = air.sunward(px, py, pz, sx, sy, sz);
        final k = v[18] / math.pi * lit * sun;
        r += seen0 * air.through(0, sunR, sunM) * k;
        gr += seen1 * air.through(1, sunR, sunM) * k;
        bl += seen2 * air.through(2, sunR, sunM) * k;
      }
    } else {
      // The disc, as `sky.frag` and [SkyShader] draw it, dimmed by the air.
      final disc =
          (v[24] > 0.0
              ? smoothstep(v[23] - v[24], v[23], mu)
              : (mu >= v[23] ? 1.0 : 0.0)) *
          v[25];
      r += seen0 * disc;
      gr += seen1 * disc;
      bl += seen2 * disc;

      final night = 1.0 - smoothstep(-0.2, 0.1, sy);
      if (v[19] > 0.0 && night > 0.0) {
        final star = v[19] * night * _starField(dx, dy, dz, v[20], v[21]);
        r += seen0 * star;
        gr += seen1 * star;
        bl += seen2 * star;
      }
    }

    return Vector4(r, gr, bl, 1.0);
  }

  /// `StarField`: a grid of cells on each face of a cube, a share [density]
  /// of them holding a star.
  static double _starField(
    double dx,
    double dy,
    double dz,
    double density,
    double cells,
  ) {
    final ax = dx.abs(), ay = dy.abs(), az = dz.abs();
    final double face, u, w;
    if (ax >= ay && ax >= az) {
      face = dx > 0.0 ? 0.0 : 1.0;
      u = dz / ax;
      w = dy / ax;
    } else if (ay >= az) {
      face = dy > 0.0 ? 2.0 : 3.0;
      u = dx / ay;
      w = dz / ay;
    } else {
      face = dz > 0.0 ? 4.0 : 5.0;
      u = dx / az;
      w = dy / az;
    }
    final gu = (u * 0.5 + 0.5) * cells;
    final gw = (w * 0.5 + 0.5) * cells;
    final cu = gu.floorToDouble(), cw = gw.floorToDouble();
    if (_hash(cu, cw, face) >= density) return 0.0;
    final centreU = _hash(cu + 17.0, cw, face) * 0.6 + 0.2;
    final centreW = _hash(cu, cw + 29.0, face) * 0.6 + 0.2;
    final ou = gu - cu - centreU, ow = gw - cw - centreW;
    final off = math.sqrt(ou * ou + ow * ow);
    final magnitude = _hash(cu, cw, face + 13.0);
    return (1.0 - smoothstep(0.0, 0.35, off)) *
        (0.15 + 0.85 * magnitude * magnitude * magnitude);
  }

  /// `Hash`, with every step rounded to single precision as the GPU takes it:
  /// a `fract` of a product in the thousands keeps three decimals, and those
  /// are the ones that decide whether a cell has a star.
  static double _hash(double x, double y, double z) {
    final c = _f32(0.1031);
    var px = _fract(_f32(x * c));
    var py = _fract(_f32(y * c));
    var pz = _fract(_f32(z * c));
    final k = _f32(31.32);
    final dot = _f32(
      _f32(_f32(px * _f32(pz + k)) + _f32(py * _f32(py + k))) +
          _f32(pz * _f32(px + k)),
    );
    px = _f32(px + dot);
    py = _f32(py + dot);
    pz = _f32(pz + dot);
    return _fract(_f32(_f32(px + py) * pz));
  }

  static double _fract(double x) => _f32(x - x.floorToDouble());

  static final Float32List _round = Float32List(1);

  static double _f32(double x) {
    _round[0] = x;
    return _round[0];
  }

  static double _leave(double r, double mu, double radius) {
    final b = r * mu;
    final d = b * b - (r - radius) * (r + radius);
    return d < 0.0 ? -1.0 : -b + math.sqrt(d);
  }

  static double _meet(double r, double mu, double radius) {
    final b = r * mu;
    final d = b * b - (r - radius) * (r + radius);
    return d < 0.0 ? -1.0 : -b - math.sqrt(d);
  }
}

/// The air off the varyings: `v_rayleigh`, `v_mie` and `v_planet`.
final class _Air {
  _Air(this.v)
    : rayleighHeight = v[6],
      mieExtinction = v[8],
      mieHeight = v[9],
      planet = v[15],
      top = v[16],
      eye = v[17];

  final Float32List v;
  final double rayleighHeight;
  final double mieExtinction;
  final double mieHeight;
  final double planet;
  final double top;
  final double eye;

  /// `Through`, one channel at a time.
  double through(int channel, double molecules, double haze) =>
      math.exp(-(v[3 + channel] * molecules + mieExtinction * haze));

  /// `SunwardAir`.
  (double, double) sunward(
    double px,
    double py,
    double pz,
    double sx,
    double sy,
    double sz,
  ) {
    final r = math.sqrt(px * px + py * py + pz * pz);
    final span = SkyPhysicalShader._leave(
      r,
      (px * sx + py * sy + pz * sz) / r,
      top,
    );
    final stride = span / SkyPhysicalShader._lightSteps;
    var airR = 0.0, airM = 0.0;
    for (var j = 0; j < SkyPhysicalShader._lightSteps; j++) {
      final u = (j + 0.5) * stride;
      final qx = px + sx * u, qy = py + sy * u, qz = pz + sz * u;
      final h = math.sqrt(qx * qx + qy * qy + qz * qz) - planet;
      airR += math.exp(-h / rayleighHeight) * stride;
      airM += math.exp(-h / mieHeight) * stride;
    }
    return (airR, airM);
  }
}
