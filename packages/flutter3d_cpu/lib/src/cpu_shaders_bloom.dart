/// The three bloom stages — `bloom_threshold.frag`, `bloom_downsample.frag`
/// and `bloom_upsample.frag` — that build the mip chain the composite adds
/// back in.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// What the three bloom stages share: the source texture and its texel size.
({BoundTexture source, double tx, double ty, Vector4 params})? bloomSource(
  ShaderBindings b,
) {
  final source = b.textures['source_texture'];
  if (source == null) return null;
  final params = b.vec4('BloomInfo', 'params', Vector4.zero());
  return (source: source, tx: params.x, ty: params.y, params: params);
}

/// `bloom_threshold.frag`: what is bright enough to glow.
final class BloomThresholdShader implements CpuFragmentShader {
  const BloomThresholdShader();

  static double _luminance(Vector3 c) =>
      c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722;

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final u = v[0];
    final w = v[1];

    // A four-tap box at the corners of the source quad. A single tap aliases a
    // one-pixel highlight in and out of existence as the camera moves, which
    // reads as flickering rather than as bloom.
    var sum = Vector3.zero();
    for (final d in const <List<double>>[
      <double>[-0.5, -0.5],
      <double>[0.5, -0.5],
      <double>[-0.5, 0.5],
      <double>[0.5, 0.5],
    ]) {
      final t = src.source.sample(u + src.tx * d[0], w + src.ty * d[1]);
      sum += Vector3(t.x, t.y, t.z);
    }
    final colour = sum..scale(0.25);

    final threshold = src.params.z;
    final knee = math.max(src.params.w, 1e-4);
    // A soft knee rather than a hard step: a hard cut makes the bloom appear
    // along a visible contour as a highlight brightens through the threshold.
    final brightness = _luminance(colour);
    var soft = (brightness - threshold + knee).clamp(0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    final contribution =
        math.max(soft, brightness - threshold) / math.max(brightness, 1e-4);

    colour.scale(contribution);
    return Vector4(colour.x, colour.y, colour.z, 1.0);
  }
}

/// `bloom_downsample.frag`: the thirteen-tap filter, four boxes plus five.
final class BloomDownsampleShader implements CpuFragmentShader {
  const BloomDownsampleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final u = v[0];
    final w = v[1];

    Vector3 at(double dx, double dy) {
      final t = src.source.sample(u + dx * src.tx, w + dy * src.ty);
      return Vector3(t.x, t.y, t.z);
    }

    final a = at(-2, 2), bb = at(0, 2), cc = at(2, 2);
    final d = at(-2, 0), e = at(0, 0), f = at(2, 0);
    final g = at(-2, -2), h = at(0, -2), i = at(2, -2);
    final j = at(-1, 1), k = at(1, 1), l = at(-1, -1), m = at(1, -1);

    // The inner four boxes carry half the weight between them; the five outer
    // ones share the rest.
    final result = (j + k + l + m) * (0.5 * 0.25);
    result.add((a + bb + d + e) * (0.125 * 0.25));
    result.add((bb + cc + e + f) * (0.125 * 0.25));
    result.add((d + e + g + h) * (0.125 * 0.25));
    result.add((e + f + h + i) * (0.125 * 0.25));
    return Vector4(result.x, result.y, result.z, 1.0);
  }
}

/// `bloom_upsample.frag`: a 1-2-1 tent over sixteen.
final class BloomUpsampleShader implements CpuFragmentShader {
  const BloomUpsampleShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final src = bloomSource(b);
    if (src == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    // The radius is in source texels, and is what makes the chain a filter
    // rather than four copies of the same blur.
    final radius = math.max(src.params.z, 0.0);
    final tx = src.tx * radius;
    final ty = src.ty * radius;
    final u = v[0];
    final w = v[1];

    Vector3 at(double dx, double dy) {
      final t = src.source.sample(u + dx * tx, w + dy * ty);
      return Vector3(t.x, t.y, t.z);
    }

    final a = at(-1, 1), bb = at(0, 1), cc = at(1, 1);
    final d = at(-1, 0), e = at(0, 0), f = at(1, 0);
    final g = at(-1, -1), h = at(0, -1), i = at(1, -1);

    final result = e * 4.0 + (bb + d + f + h) * 2.0 + (a + cc + g + i);
    result.scale(1.0 / 16.0);
    return Vector4(result.x, result.y, result.z, 1.0);
  }
}
