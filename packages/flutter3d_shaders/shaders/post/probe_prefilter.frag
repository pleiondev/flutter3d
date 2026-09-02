#version 460 core

// One face of one level of a reflection probe: the captured cube, convolved
// by roughness, written where a lit shader's `textureLod` will read it.
//
// The device-side twin of `EnvironmentMap.prefilter`, and deliberately the
// same convolution rather than a better one: the same fixed spiral of taps,
// the same cosine-power lobe for the roughness, the same weighting. A GPU
// could importance-sample GGX here and look a little nicer on a rough metal;
// what it would lose is the agreement with the software rasteriser that the
// three golden sets are measured by, and the software side is this file read
// aloud. Where the two differ — bilinear taps here against nearest ones there
// — the difference is noise well under the cross-backend budgets.
//
// **Where this writes decides the direction, not the vertex stage.** The
// full-screen triangle hands over a uv with v = 0 at row zero of the level on
// every backend, and a cube face maps (s, t) to a direction by the table every
// graphics API agrees on: row zero of the +X face looks up +Y, column zero
// looks along +Z. `FaceDirection` is that table inverted, face by face, and
// it has to agree with `BoundTexture.sampleCube` on the software side and the
// hardware sampler on the other two, which the conformance check that clears
// one face and reads it back through this stage is for.
//
// The capture is read through the sampler, not through a table of its own:
// the renderer drew each face so that a hardware lookup returns the picture
// in that direction — see `probeFaceViewProjection` for what that took.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The six views the probe captured, base level only.
uniform samplerCube capture_texture;

uniform ProbeInfo {
  /// x: which face is being written, 0..5 in +X, −X, +Y, −Y, +Z, −Z order.
  /// y: the roughness of this level, 0 for the mirror.
  /// z: the level of the capture to read, 0 for a capture with one.
  /// w: how many taps; 1 copies the capture along the axis and nothing else.
  vec4 params;
}
probe_info;

/// The direction the texel at [st] of [face] looks along, with t measured
/// down the face from row zero.
vec3 FaceDirection(int face, vec2 st) {
  float u = st.x * 2.0 - 1.0;
  float v = st.y * 2.0 - 1.0;
  if (face == 0) return normalize(vec3(1.0, -v, -u));
  if (face == 1) return normalize(vec3(-1.0, -v, u));
  if (face == 2) return normalize(vec3(u, 1.0, v));
  if (face == 3) return normalize(vec3(u, -1.0, -v));
  if (face == 4) return normalize(vec3(u, -v, 1.0));
  return normalize(vec3(-u, -v, -1.0));
}

void main() {
  int face = int(probe_info.params.x + 0.5);
  float roughness = probe_info.params.y;
  float lod = probe_info.params.z;
  int samples = clamp(int(probe_info.params.w + 0.5), 1, 128);

  vec3 axis = FaceDirection(face, v_uv);

  // One tap is a copy: the mirror level, and the conformance check's way of
  // reading one texel of one face at one level back out.
  if (samples == 1) {
    frag_color = vec4(textureLod(capture_texture, axis, lod).rgb, 1.0);
    return;
  }

  // Roughness to a specular power, squared first because roughness is
  // authored perceptually — the mapping `EnvironmentMap` uses, so a level here
  // and a level built on the host are the same lobe.
  float alpha = max(roughness * roughness, 1e-3);
  float power = 2.0 / (alpha * alpha) - 2.0;

  // A frame about the axis, so one tap set serves every texel.
  vec3 up = abs(axis.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 right = normalize(cross(up, axis));
  vec3 ahead = cross(axis, right);

  // A fixed spiral rather than a hash of the fragment: the same texel has to
  // come out the same on every backend, or the golden means nothing.
  const float golden = 3.14159265 * (3.0 - sqrt(5.0));
  vec3 sum = vec3(0.0);
  float weight = 0.0;
  for (int i = 0; i < 128; i++) {
    if (i >= samples) break;
    float z = 1.0 - (float(i) + 0.5) / float(samples);
    float radius = sqrt(max(1.0 - z * z, 0.0));
    float theta = golden * float(i);
    // Concentrated towards the axis by the power, so a sharp level does not
    // spend its taps on directions it weights to nothing.
    float spread = pow(z, 1.0 / (power + 1.0));
    vec3 tap = normalize(vec3(radius * cos(theta) * (1.0 - spread),
                              radius * sin(theta) * (1.0 - spread),
                              spread));
    vec3 dir = right * tap.x + ahead * tap.y + axis * tap.z;
    float cosine = dot(dir, axis);
    if (cosine <= 0.0) continue;
    sum += textureLod(capture_texture, dir, lod).rgb * cosine;
    weight += cosine;
  }

  frag_color = vec4(weight > 0.0 ? sum / weight : vec3(0.0), 1.0);
}
