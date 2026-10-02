#version 460 core

// SMAA 1x, second of three passes — `P1`: how far each pixel along an edge
// moves.
//
// From every pixel on an edge, a walk to both ends of the run it belongs
// to: the run ends where the edge stops or where an edge crosses it. Which
// side of each end a crossing stands on says what shape the staircase is —
// a step down, a step up, a U — and the line behind that shape, and this
// pixel's place along it, say how much of the pixel the line covers. That
// area is precomputed: the engine's `smaaArea` table, 16×16 texels for each
// pair of end codes, indexed by the square roots of the two distances.
//
// Red and green: the top edge's two shares, this pixel's and the one
// above's. Blue and alpha: the left edge's, this pixel's and the one to the
// left's. Orthogonal edges only; no diagonal search, no corner rounding.
//
// `flutter3d_cpu`'s `SmaaWeightsShader` is this, line for line.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The first pass's edges: red across the left side, green across the top.
uniform sampler2D edges_texture;

/// The engine's `smaaArea` table, 80×80, filtered.
uniform sampler2D area_texture;

uniform SmaaInfo {
  /// x, y: one texel. z, w: the first pass's, unread here.
  vec4 params;
}
smaa_info;

/// The most pixels a search walks from the one it starts at, either way.
const int kSmaaMaxSearch = 32;

vec4 Edges(vec2 offset) {
  return textureLod(edges_texture, v_uv + offset * smaa_info.params.xy, 0.0);
}

/// The table's texel for the two ends' codes and the square roots of the
/// two distances, filtered between square roots.
vec2 Area(float first, float last, float codeFirst, float codeLast) {
  vec2 at = (16.0 * vec2(codeFirst, codeLast) + sqrt(vec2(first, last)) + 0.5) /
            80.0;
  return textureLod(area_texture, at, 0.0).rg;
}

void main() {
  vec4 here = Edges(vec2(0.0));
  vec4 weights = vec4(0.0);

  if (here.g > 0.5) {
    // Along a top edge, to the left: an end where this pixel's own left
    // side is crossed, or where the next one has no top edge.
    int first = kSmaaMaxSearch;
    for (int i = 0; i < kSmaaMaxSearch; i++) {
      if (Edges(vec2(-float(i), 0.0)).r > 0.5 ||
          Edges(vec2(-float(i) - 1.0, 0.0)).g < 0.5) {
        first = i;
        break;
      }
    }
    int last = kSmaaMaxSearch;
    for (int i = 0; i < kSmaaMaxSearch; i++) {
      vec4 next = Edges(vec2(float(i) + 1.0, 0.0));
      if (next.r > 0.5 || next.g < 0.5) {
        last = i;
        break;
      }
    }
    // A crossing on the near side of the edge counts three, on the far
    // side one: the codes the bilinear fetch of the reference gives.
    float f = float(first);
    float l = float(last);
    float codeFirst = first == kSmaaMaxSearch
                          ? 0.0
                          : 3.0 * Edges(vec2(-f, 0.0)).r +
                                Edges(vec2(-f, -1.0)).r;
    float codeLast = last == kSmaaMaxSearch
                         ? 0.0
                         : 3.0 * Edges(vec2(l + 1.0, 0.0)).r +
                               Edges(vec2(l + 1.0, -1.0)).r;
    weights.rg = Area(f, l, codeFirst, codeLast);
  }

  if (here.r > 0.5) {
    // Along a left edge, upwards and then down.
    int first = kSmaaMaxSearch;
    for (int i = 0; i < kSmaaMaxSearch; i++) {
      if (Edges(vec2(0.0, -float(i))).g > 0.5 ||
          Edges(vec2(0.0, -float(i) - 1.0)).r < 0.5) {
        first = i;
        break;
      }
    }
    int last = kSmaaMaxSearch;
    for (int i = 0; i < kSmaaMaxSearch; i++) {
      vec4 next = Edges(vec2(0.0, float(i) + 1.0));
      if (next.g > 0.5 || next.r < 0.5) {
        last = i;
        break;
      }
    }
    float f = float(first);
    float l = float(last);
    float codeFirst = first == kSmaaMaxSearch
                          ? 0.0
                          : 3.0 * Edges(vec2(0.0, -f)).g +
                                Edges(vec2(-1.0, -f)).g;
    float codeLast = last == kSmaaMaxSearch
                         ? 0.0
                         : 3.0 * Edges(vec2(0.0, l + 1.0)).g +
                               Edges(vec2(-1.0, l + 1.0)).g;
    weights.ba = Area(f, l, codeFirst, codeLast);
  }

  frag_color = weights;
}
