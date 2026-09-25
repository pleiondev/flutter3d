/// `post/temporal_resolve.frag`, on the software rasteriser — `R2`.
///
/// Line for line: the jittered read, the nearest-depth velocity, the
/// Catmull-Rom history, the YCoCg box or the k-DOP (`N4`), the depth test on
/// the history's alpha and the reactive mark in the velocity's blue (`R4`).
/// See the GLSL for why each is there.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

const String _block = 'TemporalInfo';

double _luma(Vector3 c) => c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722;

Vector3 _weigh(Vector3 c, double exposure) => c / (1.0 + _luma(c) * exposure);

Vector3 _unweigh(Vector3 c, double exposure) =>
    c / math.max(1.0 - _luma(c) * exposure, 1e-4);

Vector3 _toYCoCg(Vector3 c) => Vector3(
  0.25 * c.x + 0.5 * c.y + 0.25 * c.z,
  0.5 * c.x - 0.5 * c.z,
  -0.25 * c.x + 0.5 * c.y - 0.25 * c.z,
);

Vector3 _fromYCoCg(Vector3 c) =>
    Vector3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);

Vector3 _clipToBox(Vector3 lo, Vector3 hi, Vector3 q) {
  final centre = (hi + lo) * 0.5;
  final extent = (hi - lo) * 0.5 + Vector3.all(1e-5);
  final v = q - centre;
  final most = math.max(
    (v.x / extent.x).abs(),
    math.max((v.y / extent.y).abs(), (v.z / extent.z).abs()),
  );
  return most > 1.0 ? centre + v / most : q;
}

/// `ClipToDop`: [history] moved along the line to [current] until it is
/// inside every slab of [around] along the first [count] axes of [b], each
/// slab tightened to mean ± 1.25σ and widened to take in [current].
Vector3 _clipToDop(
  Vector3 current,
  Vector3 history,
  List<Vector3> around,
  ShaderBindings b,
  int count,
) {
  final toward = history - current;
  final reach = Iterable<int>.generate(math.min(count, 16)).fold(1.0, (
    double reach,
    int a,
  ) {
    final axis4 = b.vec4(_block, 'clip_axes', Vector4.zero(), at: a);
    final axis = Vector3(axis4.x, axis4.y, axis4.z);
    final at = current.dot(axis);
    final projected = [for (final c in around) c.dot(axis)];
    final lowest = projected.reduce(math.min);
    final highest = projected.reduce(math.max);
    final mean = projected.fold(0.0, (double s, p) => s + p) / 9.0;
    final sigma = math.sqrt(
      math.max(
        projected.fold(0.0, (double s, p) => s + p * p) / 9.0 - mean * mean,
        0.0,
      ),
    );
    final lo = math.min(math.max(lowest, mean - 1.25 * sigma), at);
    final hi = math.max(math.min(highest, mean + 1.25 * sigma), at);
    final along = toward.dot(axis);
    final leave = along > 1e-8
        ? (hi - at) / along
        : (along < -1e-8 ? (lo - at) / along : 1.0);
    return math.min(reach, leave);
  });
  return current + toward * math.max(reach, 0.0);
}

Vector3 _rgb(Vector4 v) => Vector3(v.x, v.y, v.z);

/// `temporal_accumulate.frag` — `R3`: a noisy effect blended into its own
/// history, clamped to this frame's neighbourhood.
final class TemporalAccumulateShader implements CpuFragmentShader {
  const TemporalAccumulateShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final current = b.textures['current_texture'];
    final history = b.textures['history_texture'];
    final velocity = b.textures['velocity_texture'];
    if (current == null || history == null || velocity == null) {
      return Vector4(1.0, 1.0, 1.0, 1.0);
    }
    final params = b.vec4('AccumulateInfo', 'params', Vector4.zero());
    final now = current.sample(v[0], v[1]);
    final motion = velocity.sample(v[0], v[1]);
    final thenU = v[0] - motion.x;
    final thenW = v[1] - motion.y;
    if (params.y < 0.5 ||
        thenU < 0.0 ||
        thenU > 1.0 ||
        thenW < 0.0 ||
        thenW > 1.0) {
      return now;
    }

    final lowest = now.clone();
    final highest = now.clone();
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final around = current.sample(
          v[0] + dx * params.z,
          v[1] + dy * params.w,
        );
        Vector4.min(lowest, around, lowest);
        Vector4.max(highest, around, highest);
      }
    }
    final past = history.sample(thenU, thenW);
    final clamped = Vector4(
      past.x.clamp(lowest.x, highest.x),
      past.y.clamp(lowest.y, highest.y),
      past.z.clamp(lowest.z, highest.z),
      past.w.clamp(lowest.w, highest.w),
    );
    return now + (clamped - now) * params.x;
  }
}

/// `temporal_resolve.frag`: this frame blended into the ones before it.
final class TemporalResolveShader implements CpuFragmentShader {
  const TemporalResolveShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final scene = b.textures['scene_texture'];
    final history = b.textures['history_texture'];
    final velocity = b.textures['velocity_texture'];
    final surface = b.textures['surface_texture'];
    if (scene == null ||
        history == null ||
        velocity == null ||
        surface == null) {
      return Vector4(0.0, 0.0, 0.0, 0.0);
    }

    final sceneTexel = b.vec4(_block, 'scene_texel', Vector4.zero());
    final jitter = b.vec4(_block, 'jitter', Vector4.zero());
    final params = b.vec4(_block, 'params', Vector4.zero());
    final exposure = params.x;

    final u = v[0] + jitter.x;
    final w = v[1] + jitter.y;
    final cu = ((u * sceneTexel.z).floorToDouble() + 0.5) * sceneTexel.x;
    final cw = ((w * sceneTexel.w).floorToDouble() + 0.5) * sceneTexel.y;

    final sum = Vector3.zero();
    final sumSquares = Vector3.zero();
    final lowest = Vector3.all(1e30);
    final highest = Vector3.all(-1e30);
    var nearest = 1e30;
    var nearestU = cu;
    var nearestW = cw;
    final around = <Vector3>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final au = cu + dx * sceneTexel.x;
        final aw = cw + dy * sceneTexel.y;
        final col = _toYCoCg(_weigh(_rgb(scene.sample(au, aw)), exposure));
        around.add(col);
        sum.add(col);
        sumSquares.add(Vector3(col.x * col.x, col.y * col.y, col.z * col.z));
        Vector3.min(lowest, col, lowest);
        Vector3.max(highest, col, highest);
        final depth = surface.sample(au, aw).w;
        if (depth > 0.0 && depth < nearest) {
          nearest = depth;
          nearestU = au;
          nearestW = aw;
        }
      }
    }

    final current = _rgb(scene.sample(u, w));
    // The nearest depth around the pixel, as the GLSL says why.
    final depth = nearest < 1e30 ? nearest : 0.0;
    final motion = velocity.sample(nearestU, nearestW);
    final thenU = v[0] - motion.x;
    final thenW = v[1] - motion.y;

    if (jitter.w < 0.5 ||
        thenU < 0.0 ||
        thenU > 1.0 ||
        thenW < 0.0 ||
        thenW > 1.0) {
      return Vector4(current.x, current.y, current.z, depth);
    }

    final trust = _depthTrust(history, depth, thenU, thenW, params);

    final mean = sum / 9.0;
    final variance =
        sumSquares / 9.0 -
        Vector3(mean.x * mean.x, mean.y * mean.y, mean.z * mean.z);
    final sigma = Vector3(
      math.sqrt(math.max(variance.x, 0.0)),
      math.sqrt(math.max(variance.y, 0.0)),
      math.sqrt(math.max(variance.z, 0.0)),
    );
    final lo = Vector3.zero();
    final hi = Vector3.zero();
    Vector3.max(lowest, mean - sigma * 1.25, lo);
    Vector3.min(highest, mean + sigma * 1.25, hi);
    final remembered = _toYCoCg(
      _weigh(_historyAt(history, thenU, thenW, params), exposure),
    );
    final axes = b.vec4(_block, 'clip', Vector4.zero()).x;
    final clipped = axes > 0.5
        ? _clipToDop(
            _toYCoCg(_weigh(current, exposure)),
            remembered,
            around,
            b,
            axes.round(),
          )
        : _clipToBox(lo, hi, remembered);
    final past = _unweigh(_fromYCoCg(clipped), exposure);

    // `R4`: the reactive mark, at the pixel itself.
    final reactive = velocity.sample(cu, cw).z.clamp(0.0, 1.0);
    final keep = jitter.z * trust * (1.0 - reactive);
    final wCurrent = (1.0 - keep) / (1.0 + _luma(current) * exposure);
    final wHistory = keep / (1.0 + _luma(past) * exposure);
    final resolved =
        (current * wCurrent + past * wHistory) /
        math.max(wCurrent + wHistory, 1e-6);
    return Vector4(resolved.x, resolved.y, resolved.z, depth);
  }

  /// `SameSurface`: one when [then] is the surface at [depth], nought when
  /// not.
  static double _sameSurface(double depth, double then, double tolerance) {
    final sky = depth <= 0.0;
    final bothSky = sky && then <= 0.0;
    final close =
        !sky &&
        then > 0.0 &&
        (then - depth).abs() <= tolerance * math.min(depth, then);
    return (bothSky || close) ? 1.0 : 0.0;
  }

  /// `DepthTrust`: the four texels a bilinear read at ([u], [w]) would blend,
  /// each tested against [depth] on its own and counted by its weight.
  static double _depthTrust(
    BoundTexture history,
    double depth,
    double u,
    double w,
    Vector4 params,
  ) {
    final sizeX = params.z;
    final sizeY = params.w;
    final px = u * sizeX - 0.5;
    final py = w * sizeY - 0.5;
    final cx = px.floorToDouble();
    final cy = py.floorToDouble();
    final fx = px - cx;
    final fy = py - cy;
    final u0 = (cx + 0.5) / sizeX;
    final u1 = (cx + 1.5) / sizeX;
    final w0 = (cy + 0.5) / sizeY;
    final w1 = (cy + 1.5) / sizeY;
    double same(double tu, double tw) =>
        _sameSurface(depth, history.sample(tu, tw).w, params.y);
    return same(u0, w0) * (1.0 - fx) * (1.0 - fy) +
        same(u1, w0) * fx * (1.0 - fy) +
        same(u0, w1) * (1.0 - fx) * fy +
        same(u1, w1) * fx * fy;
  }

  /// `HistoryAt`: Catmull-Rom in nine bilinear taps.
  static Vector3 _historyAt(
    BoundTexture history,
    double u,
    double w,
    Vector4 params,
  ) {
    final sizeX = params.z;
    final sizeY = params.w;
    double c1(double p) => (p - 0.5).floorToDouble() + 0.5;
    final px = u * sizeX;
    final py = w * sizeY;
    final cx = c1(px);
    final cy = c1(py);
    final fx = px - cx;
    final fy = py - cy;
    (double, double, double, double) weights(double f) => (
      f * (-0.5 + f * (1.0 - 0.5 * f)),
      1.0 + f * f * (-2.5 + 1.5 * f),
      f * (0.5 + f * (2.0 - 1.5 * f)),
      f * f * (-0.5 + 0.5 * f),
    );
    final (x0, x1, x2, x3) = weights(fx);
    final (y0, y1, y2, y3) = weights(fy);
    final x12 = x1 + x2;
    final y12 = y1 + y2;
    final us = <(double, double)>[
      ((cx - 1.0) / sizeX, x0),
      ((cx + x2 / x12) / sizeX, x12),
      ((cx + 2.0) / sizeX, x3),
    ];
    final ws = <(double, double)>[
      ((cy - 1.0) / sizeY, y0),
      ((cy + y2 / y12) / sizeY, y12),
      ((cy + 2.0) / sizeY, y3),
    ];
    final sum = Vector3.zero();
    for (final (tw, wy) in ws) {
      for (final (tu, wx) in us) {
        sum.add(_rgb(history.sample(tu, tw)) * (wx * wy));
      }
    }
    return Vector3(
      math.max(sum.x, 0.0),
      math.max(sum.y, 0.0),
      math.max(sum.z, 0.0),
    );
  }
}
