#version 460 core

// SMAA 1x, first of three passes — `P1`: where the luma steps.
//
// Red marks a step across a pixel's left side, green across its top. The
// other two passes read nothing else, so this is where the method decides
// what an edge is: a step of at least `params.z` in luma, and not much
// smaller than the largest step beside it. That second test is what keeps
// SMAA off the inside of a high-contrast texture, which FXAA would smooth as
// though it were a staircase.
//
// `flutter3d_cpu`'s `SmaaEdgesShader` is this, line for line.
//
// SMAA is the method of Jimenez, Echevarria, Sousa and Gutierrez, "SMAA:
// Enhanced Subpixel Morphological Antialiasing", Eurographics 2012. These
// three passes were written for this engine from the paper and follow the
// conventions of its reference implementation (https://github.com/iryoku/smaa),
// which carries this notice:
//
// Copyright (C) 2013 Jorge Jimenez (jorge@iryoku.com)
// Copyright (C) 2013 Jose I. Echevarria (joseignacioechevarria@gmail.com)
// Copyright (C) 2013 Belen Masia (bmasia@unizar.es)
// Copyright (C) 2013 Fernando Navarro (fernandn@microsoft.com)
// Copyright (C) 2013 Diego Gutierrez (diegog@unizar.es)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions: The above copyright
// notice and this permission notice shall be included in all copies or
// substantial portions of the Software. As clarification, there is no
// requirement that the copyright notice and permission be included in binary
// distributions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The finished picture, tone mapped and encoded.
uniform sampler2D source_texture;

uniform SmaaInfo {
  /// x, y: one texel. z: the smallest luma step that is an edge. w: how
  /// many times smaller than the largest step beside it a step may be and
  /// still count.
  vec4 params;
}
smaa_info;

/// Rec. 709 weights on the encoded picture.
float Luma(vec2 at) {
  vec3 c = textureLod(source_texture, at, 0.0).rgb;
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 texel = smaa_info.params.xy;
  float middle = Luma(v_uv);
  float left = Luma(v_uv + vec2(-texel.x, 0.0));
  float top = Luma(v_uv + vec2(0.0, -texel.y));
  vec2 delta = abs(vec2(middle - left, middle - top));
  vec2 edges = step(vec2(smaa_info.params.z), delta);
  if (edges.x + edges.y == 0.0) {
    frag_color = vec4(0.0);
    return;
  }

  float right = abs(middle - Luma(v_uv + vec2(texel.x, 0.0)));
  float bottom = abs(middle - Luma(v_uv + vec2(0.0, texel.y)));
  float leftLeft = abs(left - Luma(v_uv + vec2(-2.0 * texel.x, 0.0)));
  float topTop = abs(top - Luma(v_uv + vec2(0.0, -2.0 * texel.y)));
  float largest = max(max(max(delta.x, delta.y), max(right, bottom)),
                      max(leftLeft, topTop));
  edges *= step(vec2(largest), smaa_info.params.w * delta);
  frag_color = vec4(edges, 0.0, 0.0);
}
