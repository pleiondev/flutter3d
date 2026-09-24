/// The fullscreen-quad vertex stage and the passes that composite the frame:
/// `composite.frag`, which adds bloom and ambient occlusion and tone maps, and
/// `mrt_probe.frag`, which exists only to prove a backend writes a second
/// attachment.
///
/// Screen-space effects that *read* the surface buffer — `ssao.frag` and
/// `reflections.frag` — are `cpu_shaders_screenspace.dart`: a different
/// concern, marching rays rather than compositing layers.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `fullscreen.vert`.
///
/// The uv is an attribute, not something derived from the position. Deriving
/// it — which the first version did — puts the composite's sampling a flip
/// away from the engine's on any backend whose framebuffer disagrees, and
/// there is no way to see that in a fixture whose picture is roughly
/// symmetric.
final class FullscreenVertexShader implements CpuVertexShader {
  const FullscreenVertexShader();

  @override
  int get varyingCount => 2;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    out[0] = a[2];
    out[1] = a[3];
    return Vector4(a[0], a[1], 0.0, 1.0);
  }
}

/// `composite.frag`: add the bloom, expose, tone map, encode.
final class CompositeShader implements CpuFragmentShader {
  const CompositeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final scene = bindings.textures['scene_texture'];
    if (scene == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = bindings.vec4(
      'CompositeInfo',
      'params',
      Vector4(1.0, 0.0, 1.0, 0.0),
    );

    final look = bindings.vec4(
      'CompositeInfo',
      'look',
      Vector4(1.0, 1.0, 0.0, 0.0),
    );
    final lookMore = bindings.vec4(
      'CompositeInfo',
      'look_more',
      Vector4(0.0, 0.0, 0.0, 1.0),
    );

    // Dispersion at sampling, because that is where a lens does it — see the
    // note in `composite.frag`, which this mirrors operation for operation.
    final sampled = scene.sample(v[0], v[1]);
    var colour = Vector3(sampled.x, sampled.y, sampled.z);
    if (look.w > 0.0) {
      final ox = (v[0] - 0.5) * look.w;
      final oy = (v[1] - 0.5) * look.w;
      colour.x = scene.sample(v[0] + ox, v[1] + oy).x;
      colour.z = scene.sample(v[0] - ox, v[1] - oy).z;
    }

    // Occlusion first, then the glow — the order matters and it is the order
    // `composite.frag` uses. Four taps in a 2×2, sized to the artefact rather
    // than tuned against it: the occlusion pass rotates its kernel by the
    // parity of the pixel, and this averages exactly that pattern away.
    //
    // Applied to the scene and **not** to the glow, so a lit crack in a corner
    // keeps glowing. Adding the bloom first and scaling both — which is what
    // the first draft of this function did — dims the one thing in a dark
    // corner that should not dim.
    final ao = bindings.textures['ao_texture'];
    final strength = params.w.clamp(0.0, 1.0);
    var shade = 1.0;
    if (ao != null && strength > 0.0) {
      final texel = bindings.vec4('CompositeInfo', 'ao_texel', Vector4.zero());
      final hx = texel.x * 0.5;
      final hy = texel.y * 0.5;
      final occlusion =
          0.25 *
          (ao.sample(v[0] + hx, v[1] + hy).x +
              ao.sample(v[0] - hx, v[1] + hy).x +
              ao.sample(v[0] + hx, v[1] - hy).x +
              ao.sample(v[0] - hx, v[1] - hy).x);
      shade = 1.0 + (occlusion - 1.0) * strength;
    }

    // `gfx-76n`, into the same multiplier and with a strength of its own: the
    // occlusion says how enclosed a point is, this says whether the sun reaches
    // it, and a scene wants them at different amounts. One tap rather than the
    // 2×2 above, because the march runs at the frame's own resolution and there
    // is no rotated kernel to average away — see `composite.frag`, which this
    // mirrors operation for operation.
    final contactMap = bindings.textures['contact_shadow_texture'];
    final contactStrength = bindings
        .vec4('CompositeInfo', 'contact', Vector4.zero())
        .x
        .clamp(0.0, 1.0);
    if (contactMap != null && contactStrength > 0.0) {
      final contact = contactMap.sample(v[0], v[1]).x;
      shade *= 1.0 + (contact - 1.0) * contactStrength;
    }

    // Skipped at exactly one, which is what both settings off comes to: a
    // multiply by one is exact, so this is a shortcut rather than a difference,
    // and it keeps the frames forty-four goldens hold untouched by arithmetic
    // they never used to go through.
    if (shade != 1.0) colour.scale(shade);

    // Additive, and unconditional: the engine binds a black texture when bloom
    // is off rather than leaving the sampler unbound, so there is no branch to
    // make here either.
    final bloom = bindings.textures['bloom_texture'];
    if (bloom != null) {
      final b = bloom.sample(v[0], v[1]);
      colour += Vector3(b.x, b.y, b.z) * params.y;
    }

    colour.scale(math.max(params.x, 0.0));
    colour = tonemapBy(colour, (params.z + 0.5).floor());

    // Grading after the tone map, then the barrel, then the film. The order is
    // the one a camera imposes and it is the order `composite.frag` uses; the
    // two are compared by thirty golden images and have to agree.
    // A power about mid grey (0.18 in linear light), as `composite.frag`.
    if (look.x != 1.0) {
      double pivot(double x) =>
          0.18 * math.pow(math.max(x, 0.0) / 0.18, look.x).toDouble();
      colour = Vector3(pivot(colour.x), pivot(colour.y), pivot(colour.z));
    }
    final luma = 0.2126 * colour.x + 0.7152 * colour.y + 0.0722 * colour.z;
    colour = Vector3(
      luma + (colour.x - luma) * look.y,
      luma + (colour.y - luma) * look.y,
      luma + (colour.z - luma) * look.y,
    );
    colour.x *= 1.0 + look.z * 0.1;
    colour.z *= 1.0 - look.z * 0.1;

    // `gfx-27n`: lift, then gamma, then gain — the order `composite.frag`
    // applies them and the order a grading panel names them.
    final lift = bindings.vec4('CompositeInfo', 'lift', Vector4.zero());
    final gammaCurve = bindings.vec4(
      'CompositeInfo',
      'gamma',
      Vector4(1.0, 1.0, 1.0, 0.0),
    );
    final gain = bindings.vec4(
      'CompositeInfo',
      'gain',
      Vector4(1.0, 1.0, 1.0, 0.0),
    );
    // `c * (1 - lift) + lift`: black rises, white stays.
    colour = Vector3(
      math.max(colour.x * (1.0 - lift.x) + lift.x, 0.0),
      math.max(colour.y * (1.0 - lift.y) + lift.y, 0.0),
      math.max(colour.z * (1.0 - lift.z) + lift.z, 0.0),
    );
    if (gammaCurve.x != 1.0 || gammaCurve.y != 1.0 || gammaCurve.z != 1.0) {
      colour = Vector3(
        math.pow(colour.x, 1.0 / gammaCurve.x).toDouble(),
        math.pow(colour.y, 1.0 / gammaCurve.y).toDouble(),
        math.pow(colour.z, 1.0 / gammaCurve.z).toDouble(),
      );
    }
    colour = Vector3(colour.x * gain.x, colour.y * gain.y, colour.z * gain.z);

    // White balance and tint, which are the correction rather than the look
    // `look.z` above is — see `LookSettings.whiteBalance`.
    final encode = bindings.vec4(
      'CompositeInfo',
      'output_encode',
      Vector4.zero(),
    );
    if (encode.y != 0.0 || encode.z != 0.0) {
      colour = Vector3(
        colour.x * (1.0 + encode.y * 0.20) - encode.z * 0.075,
        colour.y * (1.0 + encode.z * 0.15),
        colour.z * (1.0 - encode.y * 0.20) - encode.z * 0.075,
      );
    }

    // The colour table, after the grade and before the barrel — the order
    // `composite.frag` uses and the order a grading suite does.
    final aoTexel = bindings.vec4('CompositeInfo', 'ao_texel', Vector4.zero());
    final lut = bindings.textures['lut_texture'];
    if (lut != null && aoTexel.z > 0.0) {
      // Indexed and answered in sRGB, the space a `.cube` is written in.
      final encodedIn = Vector3(
        toSrgb(colour.x.clamp(0.0, 1.0)),
        toSrgb(colour.y.clamp(0.0, 1.0)),
        toSrgb(colour.z.clamp(0.0, 1.0)),
      );
      final gradedEncoded = _sampleLut(
        lut,
        encodedIn,
        math.max(aoTexel.w, 2.0),
      );
      final graded = Vector3(
        toLinear(gradedEncoded.x),
        toLinear(gradedEncoded.y),
        toLinear(gradedEncoded.z),
      );
      final amount = aoTexel.z.clamp(0.0, 1.0);
      colour = Vector3(
        colour.x + (graded.x - colour.x) * amount,
        colour.y + (graded.y - colour.y) * amount,
        colour.z + (graded.z - colour.z) * amount,
      );
    }

    if (lookMore.x > 0.0) {
      final aspect = math.max(lookMore.w, 1e-4);
      final fx = (v[0] - 0.5) * (1.0 + (aspect - 1.0) * lookMore.y);
      final fy = v[1] - 0.5;
      final radius = (math.sqrt(fx * fx + fy * fy) * 1.41421356).clamp(
        0.0,
        1.0,
      );
      colour.scale(1.0 - lookMore.x * radius);
    }

    // `gfx-24n`, and the grain below it: both are applied after the encode,
    // because banding is an artefact of the 8-bit target and one output step
    // is a fixed distance in display space and a wildly varying one in linear
    // space.
    final outputEncode = bindings.vec4(
      'CompositeInfo',
      'output_encode',
      Vector4.zero(),
    );
    var encoded = Vector3(
      toSrgb(math.max(colour.x, 0.0)),
      toSrgb(math.max(colour.y, 0.0)),
      toSrgb(math.max(colour.z, 0.0)),
    );

    if (lookMore.z > 0.0) {
      // **Moved out of linear light, where its own comment was wrong.** The
      // noise is symmetric either way, but in linear the clamp took the
      // negative half and the encode stretched the rest, so black rose. See
      // `composite.frag`, which carries the measurement.
      //
      // **Not bit-identical to the GPU's, and it cannot be.** The hash is a
      // sine of a large product, so single and double precision diverge in
      // the fraction this keeps. The two golden sets are independent for
      // exactly this class of difference; what has to match is the shape of
      // the noise, not the bits.
      final amount = (_hash(c.coord.x, c.coord.y) - 0.5) * lookMore.z;
      encoded = Vector3(
        encoded.x + amount,
        encoded.y + amount,
        encoded.z + amount,
      );
    }
    if (outputEncode.x > 0.0) {
      // **Bit-identical to the GPU's, unlike the grain above.** The Bayer cell
      // is an integer table and a divide, so there is no precision to lose —
      // which is the argument for an ordered matrix over a hash said in
      // arithmetic rather than in taste.
      // Centred: the cells' mean is -1/32, and the thirty-second undoes it.
      final offset =
          (_bayerCell(c.coord.x, c.coord.y) + 0.03125) * outputEncode.x;
      encoded = Vector3(
        encoded.x + offset,
        encoded.y + offset,
        encoded.z + offset,
      );
    }

    return Vector4(encoded.x, encoded.y, encoded.z, sampled.w);
  }
}

/// `BayerCell` from `composite.frag`, in [-0.5, 0.5).
///
/// The standard recursive 4x4 matrix written out, exactly as the shader
/// writes it. Fixed to screen position and independent of time, so a golden
/// recorded with dither on stays recorded.
double _bayerCell(double x, double y) {
  const table = <int>[0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  final cx = x.floor() % 4;
  final cy = y.floor() % 4;
  final index = ((cy < 0 ? cy + 4 : cy) * 4) + (cx < 0 ? cx + 4 : cx);
  return table[index] / 16.0 - 0.5;
}

/// `fxaa.frag`: edges smoothed on the composited picture — `gfx-04n`.
///
/// Mirrors the GLSL operation for operation, the same contract every shader in
/// this file keeps: the two are compared by golden images and a shortcut here
/// would read as a backend disagreeing about the picture.
final class FxaaShader implements CpuFragmentShader {
  const FxaaShader();

  /// `Weight` from `fxaa.frag`: green-weighted, on the encoded image.
  static double _weight(Vector4 c) => 0.299 * c.x + 0.587 * c.y + 0.114 * c.z;

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final source = bindings.textures['source_texture'];
    if (source == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = bindings.vec4(
      'FxaaInfo',
      'params',
      Vector4(0.0, 0.0, 0.125, 0.75),
    );

    final middle = source.sample(v[0], v[1]);
    final mid = _weight(middle);

    // Colours kept rather than only their weights: `Sharpen` below needs the
    // neighbourhood, and these are the same four taps either way.
    final northRgb = source.sample(v[0], v[1] - params.y);
    final southRgb = source.sample(v[0], v[1] + params.y);
    final westRgb = source.sample(v[0] - params.x, v[1]);
    final eastRgb = source.sample(v[0] + params.x, v[1]);
    final north = _weight(northRgb);
    final south = _weight(southRgb);
    final west = _weight(westRgb);
    final east = _weight(eastRgb);
    final sharpening = bindings.vec4('FxaaInfo', 'sharpen', Vector4.zero());
    final sharpen = sharpening.x;
    final robust = sharpening.y > 0.5;

    final lowest = math.min(
      mid,
      math.min(math.min(north, south), math.min(west, east)),
    );
    final highest = math.max(
      mid,
      math.max(math.max(north, south), math.max(west, east)),
    );
    final contrast = highest - lowest;
    if (contrast < math.max(0.0312, highest * params.z)) {
      return _sharpen(
        middle,
        northRgb,
        southRgb,
        westRgb,
        eastRgb,
        sharpen,
        robust: robust,
      );
    }

    final vertical = (north + south - 2.0 * mid).abs();
    final horizontal = (west + east - 2.0 * mid).abs();
    final horizontalEdge = vertical >= horizontal;

    final towards = horizontalEdge ? south - mid : east - mid;
    final away = horizontalEdge ? north - mid : west - mid;
    var stepLength = horizontalEdge ? params.y : params.x;
    if (away.abs() > towards.abs()) stepLength = -stepLength;

    final average = (north + south + west + east) * 0.25;
    final distance = ((average - mid).abs() / math.max(contrast, 1e-5)).clamp(
      0.0,
      1.0,
    );
    final blend = distance * distance * params.w;

    final out = horizontalEdge
        ? source.sample(v[0], v[1] + stepLength * blend)
        : source.sample(v[0] + stepLength * blend, v[1]);
    return _sharpen(
      out,
      northRgb,
      southRgb,
      westRgb,
      eastRgb,
      sharpen,
      robust: robust,
    );
  }
}

/// `SharpenRobust` from `fxaa.frag` — `R2`: the lobe that keeps every
/// channel inside the neighbourhood's range, limited to three sixteenths.
Vector4 _sharpenRobust(
  Vector4 centre,
  Vector4 n,
  Vector4 s,
  Vector4 w,
  Vector4 e,
  double amount,
) {
  var lobe = -1e30;
  for (var c = 0; c < 3; c++) {
    final lowest = math.min(math.min(n[c], s[c]), math.min(w[c], e[c]));
    final highest = math.max(math.max(n[c], s[c]), math.max(w[c], e[c]));
    final hitMin = lowest / math.max(4.0 * highest, 1e-5);
    final hitMax = (1.0 - highest) / math.min(4.0 * lowest - 4.0, -1e-5);
    lobe = math.max(lobe, math.max(-hitMin, hitMax));
  }
  lobe = math.max(-0.1875, math.min(lobe, 0.0)) * amount;
  double mix(int c) =>
      (lobe * (n[c] + s[c] + w[c] + e[c]) + centre[c]) / (4.0 * lobe + 1.0);
  return Vector4(mix(0), mix(1), mix(2), 1.0);
}

/// `Sharpen` from `fxaa.frag`, operation for operation — `gfx-29n`.
///
/// The centre pushed away from its neighbourhood average — no denominator, so
/// a flat neighbourhood returns the centre untouched by construction. See the
/// shader for the normalised form this replaced and the flat grey frame that
/// came back white.
Vector4 _sharpen(
  Vector4 centre,
  Vector4 n,
  Vector4 s,
  Vector4 w,
  Vector4 e,
  double strength, {
  bool robust = false,
}) {
  if (strength <= 0.0) return Vector4(centre.x, centre.y, centre.z, 1.0);
  if (robust) return _sharpenRobust(centre, n, s, w, e, strength);

  double lowestOf(double a, double b, double cc, double d, double f) =>
      math.min(a, math.min(math.min(b, cc), math.min(d, f)));
  double highestOf(double a, double b, double cc, double d, double f) =>
      math.max(a, math.max(math.max(b, cc), math.max(d, f)));

  double roomOf(double lo, double hi) =>
      math.min(lo, 1.0 - hi) / math.max(hi, 1e-5);

  final roomR = roomOf(
    lowestOf(centre.x, n.x, s.x, w.x, e.x),
    highestOf(centre.x, n.x, s.x, w.x, e.x),
  );
  final roomG = roomOf(
    lowestOf(centre.y, n.y, s.y, w.y, e.y),
    highestOf(centre.y, n.y, s.y, w.y, e.y),
  );
  final roomB = roomOf(
    lowestOf(centre.z, n.z, s.z, w.z, e.z),
    highestOf(centre.z, n.z, s.z, w.z, e.z),
  );
  final room = math.min(roomR, math.min(roomG, roomB)).clamp(0.0, 1.0);
  final amount = math.sqrt(room).clamp(0.0, 1.0);

  double blend(double cc, double a, double b, double d, double f) =>
      cc + (cc - (a + b + d + f) * 0.25) * amount * strength;

  return Vector4(
    blend(centre.x, n.x, s.x, w.x, e.x),
    blend(centre.y, n.y, s.y, w.y, e.y),
    blend(centre.z, n.z, s.z, w.z, e.z),
    1.0,
  );
}

/// `SampleLut` from `composite.frag`, operation for operation.
///
/// The half-texel inset on red and the `(size - 1) / size` span on green are
/// what make the ends of the ramp reachable; without them an identity table
/// darkens white, which is the one thing a neutral table must not do.
Vector3 _sampleLut(BoundTexture table, Vector3 colour, double size) {
  final r = colour.x.clamp(0.0, 1.0);
  final g = colour.y.clamp(0.0, 1.0);
  final b = colour.z.clamp(0.0, 1.0);

  final sliceWidth = 1.0 / size;
  final texel = 1.0 / (size * size);
  final innerWidth = texel * (size - 1.0);

  final u = texel * 0.5 + r * innerWidth;
  final v = (0.5 / size) + g * ((size - 1.0) / size);

  final slice = b * (size - 1.0);
  final lower = slice.floorToDouble();
  final upper = math.min(lower + 1.0, size - 1.0);

  final a = table.sample(lower * sliceWidth + u, v);
  final c = table.sample(upper * sliceWidth + u, v);
  final f = slice - lower;
  return Vector3(
    a.x + (c.x - a.x) * f,
    a.y + (c.y - a.y) * f,
    a.z + (c.z - a.z) * f,
  );
}

/// `Hash` from `composite.frag`: a value in [0, 1) from a screen position.
///
/// Static by construction — no frame counter, so a golden is the same on every
/// run. `LookSettings.grain` says the same thing from the other side.
double _hash(double x, double y) {
  final t = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return t - t.floorToDouble();
}

/// `luminance.frag`: the scene's log luminance, sixteen taps per texel, in
/// eight bits.
///
/// The encoding is the shader's and the decoding is `ExposureMeter`'s, and the
/// two are held together by the exposure test rather than by this file: a
/// floor or a range that drifted here would meter a scene as a different
/// brightness and read as a tuning problem.
final class LuminanceShader implements CpuFragmentShader {
  const LuminanceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final scene = bindings.textures['scene_texture'];
    if (scene == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = bindings.vec4(
      'LuminanceInfo',
      'params',
      Vector4(0.0, 0.0, -10.0, 1.0 / 16.0),
    );
    var sum = 0.0;
    for (var j = 0; j < 4; j++) {
      for (var i = 0; i < 4; i++) {
        final ox = ((i + 0.5) / 4.0 - 0.5) * params.x;
        final oy = ((j + 0.5) / 4.0 - 0.5) * params.y;
        final s = scene.sample(v[0] + ox, v[1] + oy);
        sum += 0.2126 * s.x + 0.7152 * s.y + 0.0722 * s.z;
      }
    }
    final mean = sum / 16.0;
    final stops = math.log(math.max(mean, 1e-6)) / math.ln2;
    final encoded = ((stops - params.z) * params.w).clamp(0.0, 1.0);
    return Vector4(encoded, encoded, encoded, 1.0);
  }
}

/// `field_decay.frag`: every texel times a factor plus a constant — `H5`.
final class FieldDecayShader implements CpuFragmentShader {
  const FieldDecayShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final field = bindings.textures['field_texture'];
    if (field == null) return Vector4.zero();
    final params = bindings.vec4('FieldDecayInfo', 'params', Vector4.zero());
    final s = field.sample(v[0], v[1]);
    return Vector4(
      s.x * params.x + params.y,
      s.y * params.x + params.y,
      s.z * params.x + params.y,
      s.w * params.x + params.y,
    );
  }
}

/// `mrt_probe.frag`: two constants into two attachments.
///
/// It exists to answer whether a backend writes the second target at all, so
/// there is nothing to get right here except writing both.
final class MrtProbeShader implements CpuFragmentShader {
  const MrtProbeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    c.surface = Vector4(0.75, 0.5, 0.25, 1.0);
    return Vector4(0.25, 0.5, 0.75, 1.0);
  }
}
