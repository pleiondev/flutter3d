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
    // Read once: the occlusion, the contact shadow and the display transform
    // each take a lane of it, and this runs for every pixel of the frame.
    final contactInfo = bindings.vec4(
      'CompositeInfo',
      'contact',
      Vector4.zero(),
    );
    // `R7`: the local exposure, in stops, before anything is added to the
    // scene — `composite.frag` multiplies the scene alone.
    if (contactInfo.w > 0.0) {
      final stops = bindings.textures['local_exposure_texture'];
      if (stops != null) {
        colour.scale(
          math.pow(2.0, stops.sample(v[0], v[1]).x * contactInfo.w).toDouble(),
        );
      }
    }
    var shade = 1.0;
    // `L5`: the light the indirect method left in rgb, added below.
    Vector3? bounced;
    if (ao != null && strength > 0.0) {
      final texel = bindings.vec4('CompositeInfo', 'ao_texel', Vector4.zero());
      final hx = texel.x * 0.5;
      final hy = texel.y * 0.5;
      final t0 = ao.sample(v[0] + hx, v[1] + hy);
      final t1 = ao.sample(v[0] - hx, v[1] + hy);
      final t2 = ao.sample(v[0] + hx, v[1] - hy);
      final t3 = ao.sample(v[0] - hx, v[1] - hy);
      // The share left open is in a; the occlusion methods write it into
      // every channel.
      final occlusion = 0.25 * (t0.w + t1.w + t2.w + t3.w);
      shade = 1.0 + (occlusion - 1.0) * strength;
      final indirect = contactInfo.z;
      if (indirect != 0.0) {
        final k = 0.25 * indirect * strength;
        bounced = Vector3(
          (t0.x + t1.x + t2.x + t3.x) * k,
          (t0.y + t1.y + t2.y + t3.y) * k,
          (t0.z + t1.z + t2.z + t3.z) * k,
        );
      }
    }

    // `gfx-76n`, into the same multiplier and with a strength of its own: the
    // occlusion says how enclosed a point is, this says whether the sun reaches
    // it, and a scene wants them at different amounts. One tap rather than the
    // 2×2 above, because the march runs at the frame's own resolution and there
    // is no rotated kernel to average away — see `composite.frag`, which this
    // mirrors operation for operation.
    final contactMap = bindings.textures['contact_shadow_texture'];
    final contactStrength = contactInfo.x.clamp(0.0, 1.0);
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
    if (bounced != null) colour += bounced;

    colour.scale(math.max(params.x, 0.0));
    final curve = (params.z + 0.5).floor();
    final display = bindings.textures['display_texture'];
    colour = curve == 6 && display != null
        ? _sampleDisplay(display, colour, math.max(contactInfo.y, 2.0))
        : tonemapBy(colour, curve);

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

  /// `SearchStep` from `fxaa.frag`, the first step (one texel) included:
  /// FXAA 3.11's quality preset 12.
  static const List<double> _searchSteps = <double>[1.0, 1.5, 2.0, 4.0, 12.0];

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

    // FXAA 3.11 Quality, step for step; see the GLSL.
    double weightAt(double x, double y) => _weight(source.sample(x, y));
    final northWest = weightAt(v[0] - params.x, v[1] - params.y);
    final southEast = weightAt(v[0] + params.x, v[1] + params.y);
    final northEast = weightAt(v[0] + params.x, v[1] - params.y);
    final southWest = weightAt(v[0] - params.x, v[1] + params.y);

    final edgeHorizontal =
        (northWest + southWest - 2.0 * west).abs() +
        2.0 * (north + south - 2.0 * mid).abs() +
        (northEast + southEast - 2.0 * east).abs();
    final edgeVertical =
        (northWest + northEast - 2.0 * north).abs() +
        2.0 * (west + east - 2.0 * mid).abs() +
        (southWest + southEast - 2.0 * south).abs();
    final horizontalSpan = edgeHorizontal >= edgeVertical;

    final lowPass =
        (2.0 * (north + south + west + east) +
            northWest +
            northEast +
            southWest +
            southEast) /
        12.0;
    final subpixC = ((lowPass - mid).abs() / contrast).clamp(0.0, 1.0);
    final subpixF = (3.0 - 2.0 * subpixC) * subpixC * subpixC;
    final subpixH = subpixF * subpixF * params.w;

    final lumaN = horizontalSpan ? north : west;
    final lumaS = horizontalSpan ? south : east;
    final gradientN = lumaN - mid;
    final gradientS = lumaS - mid;
    final pairN = gradientN.abs() >= gradientS.abs();
    final gradient = math.max(gradientN.abs(), gradientS.abs());
    final texelAcross = horizontalSpan ? params.y : params.x;
    final lengthSign = pairN ? -texelAcross : texelAcross;
    final pairAverage = 0.5 * (pairN ? lumaN + mid : lumaS + mid);

    // The edge search, along x for a horizontal span and y for a vertical.
    final alongX = horizontalSpan ? params.x : 0.0;
    final alongY = horizontalSpan ? 0.0 : params.y;
    final startX = v[0] + (horizontalSpan ? 0.0 : lengthSign * 0.5);
    final startY = v[1] + (horizontalSpan ? lengthSign * 0.5 : 0.0);
    final gradientScaled = gradient * 0.25;
    var posNX = startX - alongX;
    var posNY = startY - alongY;
    var posPX = startX + alongX;
    var posPY = startY + alongY;
    var endN = weightAt(posNX, posNY) - pairAverage;
    var endP = weightAt(posPX, posPY) - pairAverage;
    var doneN = endN.abs() >= gradientScaled;
    var doneP = endP.abs() >= gradientScaled;
    for (var i = 1; i < _searchSteps.length; i++) {
      if (doneN && doneP) break;
      final stride = _searchSteps[i];
      if (!doneN) {
        posNX -= alongX * stride;
        posNY -= alongY * stride;
        endN = weightAt(posNX, posNY) - pairAverage;
        doneN = endN.abs() >= gradientScaled;
      }
      if (!doneP) {
        posPX += alongX * stride;
        posPY += alongY * stride;
        endP = weightAt(posPX, posPY) - pairAverage;
        doneP = endP.abs() >= gradientScaled;
      }
    }

    final distanceN = horizontalSpan ? v[0] - posNX : v[1] - posNY;
    final distanceP = horizontalSpan ? posPX - v[0] : posPY - v[1];
    final middleBelow = mid - pairAverage < 0.0;
    final nearerN = distanceN < distanceP;
    final goodSpan = nearerN
        ? (endN < 0.0) != middleBelow
        : (endP < 0.0) != middleBelow;
    final nearest = math.min(distanceN, distanceP);
    final pixelOffset = 0.5 - nearest / (distanceN + distanceP);
    final offset = math.max(goodSpan ? pixelOffset : 0.0, subpixH);

    final out = horizontalSpan
        ? source.sample(v[0], v[1] + offset * lengthSign)
        : source.sample(v[0] + offset * lengthSign, v[1]);
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

/// `SampleDisplay` from `composite.frag` — `L2`: the log2 shaper of −10…+10
/// stops about 0.18, then [_sampleLut]'s lookup.
Vector3 _sampleDisplay(BoundTexture table, Vector3 colour, double size) {
  double shaped(double x) =>
      ((math.log(math.max(x, 1e-10) / 0.18) / math.ln2 + 10.0) / 20.0).clamp(
        0.0,
        1.0,
      );
  return _sampleLut(
    table,
    Vector3(shaped(colour.x), shaped(colour.y), shaped(colour.z)),
    size,
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

/// `depth_pyramid.frag`: the farthest view depth under each texel's block of
/// the surface buffer, as 24 bits of the far plane, and whether the whole
/// block was drawn — `C3`. `HiZOcclusion.accept` is the other end.
final class DepthPyramidShader implements CpuFragmentShader {
  const DepthPyramidShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final surface = bindings.textures['surface_texture'];
    if (surface == null) return Vector4.zero();
    final block = bindings.vec4('DepthPyramidInfo', 'block', Vector4.zero());
    final range = bindings.vec4('DepthPyramidInfo', 'range', Vector4.zero());
    final tapsX = (block.z - 1e-3).ceilToDouble().clamp(1.0, 32.0).toInt();
    final tapsY = (block.w - 1e-3).ceilToDouble().clamp(1.0, 32.0).toInt();
    final cornerU = v[0] - 0.5 * block.x;
    final cornerV = v[1] - 0.5 * block.y;
    final stepU = block.x / tapsX;
    final stepV = block.y / tapsY;

    var farthest = 0.0;
    var empty = false;
    for (var j = 0; j < tapsY; j++) {
      for (var i = 0; i < tapsX; i++) {
        final depth = surface
            .sample(cornerU + (i + 0.5) * stepU, cornerV + (j + 0.5) * stepV)
            .w;
        if (!(depth > 0.0)) empty = true;
        if (depth > farthest) farthest = depth;
      }
    }

    const steps = 16777215.0;
    final scaled = ((farthest * range.x).clamp(0.0, 1.0) * steps)
        .ceilToDouble();
    final high = (scaled / 65536.0).floorToDouble();
    final rest = scaled - high * 65536.0;
    final middle = (rest / 256.0).floorToDouble();
    final low = rest - middle * 256.0;
    return Vector4(
      high / 255.0,
      middle / 255.0,
      low / 255.0,
      empty ? 0.0 : 1.0,
    );
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

/// `easu.frag`: the edge-adaptive upscale — `R5`. Mirrors the GLSL tap for
/// tap: twelve taps, the edge's direction and length from the four nearest,
/// an approximated Lanczos-2 stretched along the edge, and the result held
/// between the four nearest.
final class EasuShader implements CpuFragmentShader {
  const EasuShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final map = b.textures['source_texture'];
    if (map == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final source = b.vec4('EasuInfo', 'source', Vector4.zero());
    final params = b.vec4('EasuInfo', 'params', Vector4.zero());

    final ppx0 = v[0] * source.x - 0.5;
    final ppy0 = v[1] * source.y - 0.5;
    final fx = ppx0.floorToDouble();
    final fy = ppy0.floorToDouble();
    final px = ppx0 - fx;
    final py = ppy0 - fy;

    Vector3 tap(double dx, double dy) {
      final t = map.sample(
        (fx + dx + 0.5) * source.z,
        (fy + dy + 0.5) * source.w,
      );
      return Vector3(t.x, t.y, t.z);
    }

    double luma(Vector3 c) => c.y + 0.5 * (c.x + c.z);

    final tb = tap(0, -1), tc = tap(1, -1), te = tap(-1, 0), tf = tap(0, 0);
    final tg = tap(1, 0), th = tap(2, 0), ti = tap(-1, 1), tj = tap(0, 1);
    final tk = tap(1, 1), tl = tap(2, 1), tn = tap(0, 2), to = tap(1, 2);
    final bL = luma(tb), cL = luma(tc), eL = luma(te), fL = luma(tf);
    final gL = luma(tg), hL = luma(th), iL = luma(ti), jL = luma(tj);
    final kL = luma(tk), lL = luma(tl), nL = luma(tn), oL = luma(to);

    var dirX = 0.0;
    var dirY = 0.0;
    var len = 0.0;
    void edgeAt(double w, double a, double bb, double cc, double d, double e) {
      final lenX = math.max((d - cc).abs(), (cc - bb).abs());
      final dx = d - bb;
      final sx = (dx.abs() / math.max(lenX, 1e-6)).clamp(0.0, 1.0);
      final lenY = math.max((e - cc).abs(), (cc - a).abs());
      final dy = e - a;
      final sy = (dy.abs() / math.max(lenY, 1e-6)).clamp(0.0, 1.0);
      dirX += dx * w;
      dirY += dy * w;
      len += (sx * sx + sy * sy) * w;
    }

    edgeAt((1 - px) * (1 - py), bL, eL, fL, gL, jL);
    edgeAt(px * (1 - py), cL, fL, gL, hL, kL);
    edgeAt((1 - px) * py, fL, iL, jL, kL, nL);
    edgeAt(px * py, gL, jL, kL, lL, oL);

    final dirR = dirX * dirX + dirY * dirY;
    final featureless = dirR < 1.0 / 32768.0;
    final inv = featureless ? 1.0 : 1.0 / math.sqrt(math.max(dirR, 1e-12));
    final ux = featureless ? 1.0 : dirX * inv;
    final uy = featureless ? 0.0 : dirY * inv;

    len *= 0.5;
    len *= len;
    final stretch = (ux * ux + uy * uy) / math.max(ux.abs(), uy.abs());
    final len2x = 1.0 + (stretch - 1.0) * len;
    final len2y = 1.0 - 0.5 * len;
    final lob = 0.5 - 0.29 * len;
    final clp = 1.0 / lob;

    double weight(double ox, double oy) {
      final vx = (ox * ux + oy * uy) * len2x;
      final vy = (ox * -uy + oy * ux) * len2y;
      final d2 = math.min(vx * vx + vy * vy, clp);
      var wB = 0.4 * d2 - 1.0;
      var wA = lob * d2 - 1.0;
      wB *= wB;
      wA *= wA;
      wB = 1.5625 * wB - 0.5625;
      return wB * wA;
    }

    final sum = Vector3.zero();
    var total = 0.0;
    void add(Vector3 colour, double ox, double oy) {
      final w = weight(ox - px, oy - py);
      sum.addScaled(colour, w);
      total += w;
    }

    add(tb, 0, -1);
    add(tc, 1, -1);
    add(ti, -1, 1);
    add(tj, 0, 1);
    add(tf, 0, 0);
    add(te, -1, 0);
    add(tk, 1, 1);
    add(tl, 2, 1);
    add(th, 2, 0);
    add(tg, 1, 0);
    add(to, 1, 2);
    add(tn, 0, 2);

    final lo = Vector3(
      math.min(math.min(tf.x, tg.x), math.min(tj.x, tk.x)),
      math.min(math.min(tf.y, tg.y), math.min(tj.y, tk.y)),
      math.min(math.min(tf.z, tg.z), math.min(tj.z, tk.z)),
    );
    final hi = Vector3(
      math.max(math.max(tf.x, tg.x), math.max(tj.x, tk.x)),
      math.max(math.max(tf.y, tg.y), math.max(tj.y, tk.y)),
      math.max(math.max(tf.z, tg.z), math.max(tj.z, tk.z)),
    );
    final scale = 1.0 / math.max(total, 1e-6);
    final grain = (_hash(c.coord.x, c.coord.y) - 0.5) * params.x;
    return Vector4(
      (sum.x * scale).clamp(lo.x, hi.x) + grain,
      (sum.y * scale).clamp(lo.y, hi.y) + grain,
      (sum.z * scale).clamp(lo.z, hi.z) + grain,
      1.0,
    );
  }
}

/// `local_exposure.frag`: how well exposed each place would be at three
/// exposures — `R7`.
final class LocalExposureShader implements CpuFragmentShader {
  const LocalExposureShader();

  static double _luma(Vector4 c) => 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;

  static double _wellExposed(double y) {
    final display = math.pow(y / (1.0 + y), 1.0 / 2.2).toDouble();
    final off = display - 0.5;
    return math.exp(-off * off / 0.08);
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final scene = b.textures['scene_texture'];
    if (scene == null) return Vector4(1.0, 1.0, 1.0, 1.0);
    final stops = b.vec4('LocalExposureInfo', 'stops', Vector4.zero());
    final tx = stops.z * 2.0;
    final ty = stops.w * 2.0;
    final camera = b.vec4('LocalExposureInfo', 'camera', Vector4.zero());
    // At the frame's own exposure, which the composite applies after the
    // local stops: see the GLSL.
    final y =
        math.max(
          0.25 *
              (_luma(scene.sample(v[0] - tx, v[1] - ty)) +
                  _luma(scene.sample(v[0] + tx, v[1] - ty)) +
                  _luma(scene.sample(v[0] - tx, v[1] + ty)) +
                  _luma(scene.sample(v[0] + tx, v[1] + ty))),
          0.0,
        ) *
        math.max(camera.x, 0.0);
    final shadow = math.pow(2.0, stops.x).toDouble();
    final highlight = math.pow(2.0, -stops.y).toDouble();
    return Vector4(
      _wellExposed(y * shadow) + 1e-4,
      _wellExposed(y) + 1e-4,
      _wellExposed(y * highlight) + 1e-4,
      1.0,
    );
  }
}

/// `local_exposure_blur.frag`: the weights blurred along one axis, and on
/// the second run the exposure in stops — `R7`.
final class LocalExposureBlurShader implements CpuFragmentShader {
  const LocalExposureBlurShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final weights = b.textures['weight_texture'];
    if (weights == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final step = b.vec4('LocalExposureBlurInfo', 'step', Vector4.zero());
    final stops = b.vec4('LocalExposureBlurInfo', 'stops', Vector4.zero());
    final sum = Vector3.zero();
    var total = 0.0;
    for (var i = -6; i <= 6; i++) {
      final w = math.exp(-(i * i) / 18.0);
      final t = weights.sample(v[0] + step.x * i, v[1] + step.y * i);
      sum.addScaled(Vector3(t.x, t.y, t.z), w);
      total += w;
    }
    sum.scale(1.0 / total);
    if (step.z > 0.5) {
      final shift =
          (sum.x * stops.x - sum.z * stops.y) /
          math.max(sum.x + sum.y + sum.z, 1e-6);
      return Vector4(shift, shift, shift, 1.0);
    }
    return Vector4(sum.x, sum.y, sum.z, 1.0);
  }
}

/// `scene_colour_copy.frag` — `M3`: one level of the copy of the scene the
/// transmissive draws read, the mean of the block of the scene under each
/// texel, taken as the stage takes it — bilinear taps on the corners inside
/// the block, rows outside and columns inside, in the stage's order.
final class SceneColourCopyShader implements CpuFragmentShader {
  const SceneColourCopyShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final source = b.textures['source_texture'];
    if (source == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = b.vec4('SceneCopyInfo', 'params', Vector4.zero());
    final taps = params.x;
    final first = 1.0 - taps;
    final sum = Vector3.zero();
    for (var j = 0; j < 16 && j < taps; j++) {
      for (var i = 0; i < 16 && i < taps; i++) {
        final texel = source.sample(
          v[0] + (first + 2.0 * i) * params.y,
          v[1] + (first + 2.0 * j) * params.z,
        );
        sum.add(texel.xyz);
      }
    }
    final count = taps * taps;
    return Vector4(sum.x / count, sum.y / count, sum.z / count, 1.0);
  }
}

/// `wboit_resolve.frag` — `R8`: the weighted average of the transparent
/// layers, covering as much of the pixel as they do together, premultiplied
/// for the source-over it is drawn with.
final class WboitResolveShader implements CpuFragmentShader {
  const WboitResolveShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final accumulation = b.textures['accumulation_texture'];
    final revealage = b.textures['revealage_texture'];
    // Nothing bound covers nothing, which source-over leaves alone.
    if (accumulation == null || revealage == null) return Vector4.zero();
    final sum = accumulation.sample(v[0], v[1]);
    final coverage = 1.0 - revealage.sample(v[0], v[1]).x;
    final weight = sum.w.clamp(1e-5, 65504.0);
    return Vector4(
      math.min(sum.x, 65504.0) / weight * coverage,
      math.min(sum.y, 65504.0) / weight * coverage,
      math.min(sum.z, 65504.0) / weight * coverage,
      coverage,
    );
  }
}
