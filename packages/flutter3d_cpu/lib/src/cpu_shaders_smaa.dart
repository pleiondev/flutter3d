/// `smaa_edges.frag`, `smaa_weights.frag` and `smaa_blend.frag`: SMAA 1x —
/// `P1` — line for line, so the software backend smooths the same edges by
/// the same amounts as the GPUs.
///
/// Three passes over the finished picture. The first marks where the luma
/// steps: red for a step across a pixel's left side, green across its top.
/// The second walks along each marked edge to both of its ends, reads which
/// sides of each end a crossing edge stands on, and looks up in the engine's
/// area table how much of this pixel the line behind the staircase covers.
/// The third moves each pixel that far towards its neighbour across the
/// edge.
///
/// Orthogonal edges only. The diagonal search and the corner rounding of
/// the paper are not here, on either side of the backend boundary.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// `kSmaaMaxSearch` in the GLSL: the most pixels a search walks from the one
/// it starts at, either way.
const int kSmaaMaxSearch = 32;

/// `Luma` in `smaa_edges.frag`: Rec. 709 weights on the encoded picture.
double _luma(Vector4 c) => 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;

/// GLSL's `step(edge, x)`.
double _step(double edge, double x) => x < edge ? 0.0 : 1.0;

/// `smaa_edges.frag`.
final class SmaaEdgesShader implements CpuFragmentShader {
  const SmaaEdgesShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final source = b.textures['source_texture'];
    if (source == null) return Vector4.zero();
    final params = b.vec4('SmaaInfo', 'params', Vector4(0.0, 0.0, 0.1, 2.0));
    double at(double dx, double dy) =>
        _luma(source.sample(v[0] + dx * params.x, v[1] + dy * params.y));

    final middle = at(0.0, 0.0);
    final left = at(-1.0, 0.0);
    final top = at(0.0, -1.0);
    final deltaLeft = (middle - left).abs();
    final deltaTop = (middle - top).abs();
    var edgeLeft = _step(params.z, deltaLeft);
    var edgeTop = _step(params.z, deltaTop);
    if (edgeLeft + edgeTop == 0.0) return Vector4.zero();

    // Local contrast adaptation: a step is not an edge when a much larger
    // one sits right beside it, which is what keeps the inside of a
    // high-contrast texture from being smoothed as a staircase.
    final right = (middle - at(1.0, 0.0)).abs();
    final bottom = (middle - at(0.0, 1.0)).abs();
    final leftLeft = (left - at(-2.0, 0.0)).abs();
    final topTop = (top - at(0.0, -2.0)).abs();
    final largest = math.max(
      math.max(math.max(deltaLeft, deltaTop), math.max(right, bottom)),
      math.max(leftLeft, topTop),
    );
    edgeLeft *= _step(largest, params.w * deltaLeft);
    edgeTop *= _step(largest, params.w * deltaTop);
    return Vector4(edgeLeft, edgeTop, 0.0, 0.0);
  }
}

/// `smaa_weights.frag`.
final class SmaaWeightsShader implements CpuFragmentShader {
  const SmaaWeightsShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final edges = b.textures['edges_texture'];
    final area = b.textures['area_texture'];
    if (edges == null || area == null) return Vector4.zero();
    final params = b.vec4('SmaaInfo', 'params', Vector4.zero());
    // Red: an edge across the left side. Green: across the top.
    Vector4 e(int dx, int dy) =>
        edges.sample(v[0] + dx * params.x, v[1] + dy * params.y);

    final here = e(0, 0);
    final weights = Vector4.zero();

    if (here.y > 0.5) {
      // Along a top edge, to the left: an end where this pixel's own left
      // side is crossed, or where the next one has no top edge.
      var first = kSmaaMaxSearch;
      for (var i = 0; i < kSmaaMaxSearch; i++) {
        if (e(-i, 0).x > 0.5 || e(-i - 1, 0).y < 0.5) {
          first = i;
          break;
        }
      }
      var last = kSmaaMaxSearch;
      for (var i = 0; i < kSmaaMaxSearch; i++) {
        final next = e(i + 1, 0);
        if (next.x > 0.5 || next.y < 0.5) {
          last = i;
          break;
        }
      }
      // A crossing on the near side of the edge counts three, on the far
      // side one: the codes the bilinear fetch of the reference gives.
      final codeFirst = first == kSmaaMaxSearch
          ? 0.0
          : 3.0 * e(-first, 0).x + e(-first, -1).x;
      final codeLast = last == kSmaaMaxSearch
          ? 0.0
          : 3.0 * e(last + 1, 0).x + e(last + 1, -1).x;
      final share = _area(area, first, last, codeFirst, codeLast);
      weights
        ..x = share.x
        ..y = share.y;
    }

    if (here.x > 0.5) {
      // Along a left edge, upwards and then down.
      var first = kSmaaMaxSearch;
      for (var i = 0; i < kSmaaMaxSearch; i++) {
        if (e(0, -i).y > 0.5 || e(0, -i - 1).x < 0.5) {
          first = i;
          break;
        }
      }
      var last = kSmaaMaxSearch;
      for (var i = 0; i < kSmaaMaxSearch; i++) {
        final next = e(0, i + 1);
        if (next.y > 0.5 || next.x < 0.5) {
          last = i;
          break;
        }
      }
      final codeFirst = first == kSmaaMaxSearch
          ? 0.0
          : 3.0 * e(0, -first).y + e(-1, -first).y;
      final codeLast = last == kSmaaMaxSearch
          ? 0.0
          : 3.0 * e(0, last + 1).y + e(-1, last + 1).y;
      final share = _area(area, first, last, codeFirst, codeLast);
      weights
        ..z = share.x
        ..w = share.y;
    }
    return weights;
  }

  /// `Area` in the GLSL: the table's texel for the two ends' codes and the
  /// square roots of the two distances, filtered between square roots.
  static Vector2 _area(
    BoundTexture area,
    int first,
    int last,
    double codeFirst,
    double codeLast,
  ) {
    const cell = 16.0;
    const size = 80.0;
    final u = (cell * codeFirst + math.sqrt(first) + 0.5) / size;
    final w = (cell * codeLast + math.sqrt(last) + 0.5) / size;
    final texel = area.sample(u, w);
    return Vector2(texel.x, texel.y);
  }
}

/// `smaa_blend.frag`.
final class SmaaBlendShader implements CpuFragmentShader {
  const SmaaBlendShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final source = b.textures['source_texture'];
    final blend = b.textures['blend_texture'];
    if (source == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    if (blend == null) return source.sample(v[0], v[1]);
    final params = b.vec4('SmaaInfo', 'params', Vector4.zero());

    // What the four sides of this pixel ask of it: right and bottom are the
    // neighbours' far shares, top and left this pixel's own near ones.
    final right = blend.sample(v[0] + params.x, v[1]).w;
    final bottom = blend.sample(v[0], v[1] + params.y).y;
    final mine = blend.sample(v[0], v[1]);
    final top = mine.x;
    final left = mine.z;
    if (right + bottom + top + left < 1e-5) return source.sample(v[0], v[1]);

    final across = math.max(right, left) > math.max(bottom, top);
    final double toward;
    final double away;
    final Vector4 first;
    final Vector4 second;
    if (across) {
      toward = right;
      away = left;
      first = source.sample(v[0] + right * params.x, v[1]);
      second = source.sample(v[0] - left * params.x, v[1]);
    } else {
      toward = bottom;
      away = top;
      first = source.sample(v[0], v[1] + bottom * params.y);
      second = source.sample(v[0], v[1] - top * params.y);
    }
    final total = toward + away;
    return first * (toward / total) + second * (away / total);
  }
}
