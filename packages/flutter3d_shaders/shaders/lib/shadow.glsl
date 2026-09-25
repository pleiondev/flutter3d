// Sampling the directional light's shadow map.
//
// A separate header for the same reason material_maps.glsl is one: the sampler
// must only be declared by shaders that actually read it, or the compiler drops
// the slot while the engine still tries to bind it.

#ifndef SHADOW_GLSL_
#define SHADOW_GLSL_

#include <lib/evsm.glsl>
#include <lib/surface.glsl>

/// Linear depth from the light's point of view, in the red channel — or,
/// with the `evsm` filter (`S2`), the blurred moments `evsm_filter.frag`
/// made of it, bound to the same slot so the lit stages spend no sampler on
/// the choice.
uniform sampler2D shadow_texture;

/// Point [i] of [n] on a Vogel disc turned by [turn] radians — `S3`: the
/// golden angle between neighbours, so any prefix of the points covers the
/// disc evenly, and a radius growing with the square root, so they cover it
/// at an even density.
vec2 VogelDisc(int i, int n, float turn) {
  float r = sqrt((float(i) + 0.5) / float(n));
  float theta = float(i) * 2.3999632 + turn;
  return r * vec2(cos(theta), sin(theta));
}

/// Interleaved gradient noise at this pixel, in [0, 1), stepped on by the
/// frame's slice while a temporal resolve runs (`target_origin.w`) so the
/// history averages the rotations. The pattern needs no texture, which keeps
/// the lit stages at the samplers they have. Rows are counted from the top
/// (`target_origin.x`), as the point shadow's rotation counts them, so WebGL2
/// turns the kernel on the same pixels as every other backend.
float ShadowNoise() {
  vec2 at = FragCoordFromTop(frag_info.target_origin.x) +
            5.588238 * max(frag_info.target_origin.w, 0.0);
  return fract(52.9829189 * fract(dot(at, vec2(0.06711056, 0.00583715))));
}

/// How much of the light survives at this fragment, from 0 to 1.
///
/// Returns 1 when shadows are off, when the fragment falls outside the map, or
/// when the light in question is not the caster — a fragment beyond the shadow
/// volume is unshadowed, not black, and getting that wrong puts a hard edge
/// across the scene at the edge of the map.
float ShadowFactor(Surface s, LightSample light, int lightIndex) {
  float strength = frag_info.shadow_params.w;
  if (strength <= 0.0) return 1.0;
  if (lightIndex != int(frag_info.frame_params.z + 0.5)) return 1.0;

  // Normal offset: move the sample point along the surface normal before
  // projecting it. It costs nothing and fixes the shadow acne that a depth bias
  // alone cannot, because the error is proportional to the surface's slope
  // relative to the light rather than to depth.
  //
  // **A flat distance plus what the kernel's reach needs, and no more.** The
  // flat part alone was tuned for surfaces the map never recorded: with the
  // default `casterFaces: back` a closed mesh writes only the faces turned
  // away from the sun, so a lit face compares against its own far side. A
  // double-sided material writes its lit faces too, and then the offset has
  // to lift the point clear of its own plane as far out as the 3×3 kernel
  // reads: a tap one texel over lands in a texel whose centre is up to a
  // texel and a half away, where the plane is 1.5·texel·tanθ nearer the
  // light. A step d along the normal clears the plane by d / cosθ along the
  // ray, so d = 1.5·texel·sinθ is exactly enough, taken per axis of the map
  // because a slope running diagonally across it reaches further in texels.
  // Nothing at normal incidence, a texel and a half at grazing. The depth
  // bias covers the rest. Every metre more than this moves the shadow away
  // from its caster, and in the far cascade a texel is decimetres. Measured
  // per cascade in the loop below, since each has a texel of its own.

  // Which cascade covers this fragment.
  //
  // Chosen by distance from the camera and then *checked*, because the volumes
  // are spheres on the line of sight rather than fitted frusta: a fragment at
  // the edge of the view can be past the end of the cascade its distance
  // suggests. Falling through to the next one costs a branch and removes a
  // whole class of missing-shadow bug, and the last cascade is fitted to the
  // entire scene, so the fall-through always terminates somewhere real.
  int cascadeCount = int(frag_info.shadow_cascades.z + 0.5);
  float viewDistance = length(v_world_position - frag_info.camera_position.xyz);
  int cascade = 0;
  if (cascadeCount > 1 && viewDistance > frag_info.shadow_cascades.x) cascade = 1;
  if (cascadeCount > 2 && viewDistance > frag_info.shadow_cascades.y) cascade = 2;

  vec2 uv = vec2(0.0);
  vec3 projected = vec3(0.0);
  bool found = false;
  // `S3`: what the soft path needs of the cascade it lands in — metres per
  // texel across, and metres per unit of stored depth along the light.
  float cascadeTexel = 1.0;
  float cascadeDepth = 1.0;
  for (int attempt = 0; attempt < 3; attempt++) {
    int which = cascade + attempt;
    if (which >= cascadeCount) break;

    mat4 matrix = which == 0
        ? frag_info.shadow_matrix
        : (which == 1 ? frag_info.shadow_matrix_far
                      : frag_info.shadow_matrix_farthest);
    // One texel of this cascade in metres. The projection is orthographic,
    // so its first row is 2 / width, and a tile texel is `shadow_cascades.w`
    // of the width. The rows are also the map's axes in the world, which is
    // what the normal is measured along: its share across each axis is the
    // sine of the slope in that direction.
    vec3 axisX = vec3(matrix[0][0], matrix[1][0], matrix[2][0]);
    vec3 axisY = vec3(matrix[0][1], matrix[1][1], matrix[2][1]);
    float rowX = max(length(axisX), 1e-6);
    float rowY = max(length(axisY), 1e-6);
    float texelMetres = 2.0 * frag_info.shadow_cascades.w / rowX;
    float reach = 1.5 * 2.0 * frag_info.shadow_cascades.w *
        (abs(dot(s.n, axisX)) / (rowX * rowX) +
         abs(dot(s.n, axisY)) / (rowY * rowY));
    vec3 origin = v_world_position + s.n * (frag_info.shadow_params.z + reach);
    vec4 lightSpace = matrix * vec4(origin, 1.0);
    if (lightSpace.w <= 0.0) continue;
    vec3 candidate = lightSpace.xyz / lightSpace.w;

    // Clip space x and y are in [-1, 1]; a tile is in [0, 1] with the origin at
    // the top, matching where the render target's row zero is.
    vec2 inTile = vec2(candidate.x * 0.5 + 0.5, 0.5 - candidate.y * 0.5);
    if (inTile.x < 0.0 || inTile.x > 1.0 || inTile.y < 0.0 || inTile.y > 1.0) {
      continue;
    }
    // Depth is already in [0, 1] here, as every projection in this engine
    // produces. **Past the far plane is behind every caster, not outside the
    // map.** The last cascade's depth is fitted to the casters alone, so a
    // floor that runs on past them — the tip of a long evening shadow — sits
    // beyond it. Skipping that point called it lit and cut the shadow off
    // along the line where the far plane meets the floor. A nearer cascade
    // may still be missing casters and hands the point on; the last one
    // clamps, and 1.0 compares lit only against a texel nothing was drawn in.
    if (candidate.z > 1.0) {
      if (which < cascadeCount - 1) continue;
      candidate.z = 1.0;
    }

    // Into the atlas: the cascades sit side by side in one texture.
    uv = vec2((inTile.x + float(which)) / float(cascadeCount), inTile.y);
    projected = candidate;
    cascade = which;
    cascadeTexel = texelMetres;
    cascadeDepth =
        1.0 / max(length(vec3(matrix[0][2], matrix[1][2], matrix[2][2])), 1e-6);
    found = true;
    break;
  }
  if (!found) return 1.0;

  float bias = cascade == 0
      ? frag_info.shadow_bias.x
      : (cascade == 1 ? frag_info.shadow_bias.y : frag_info.shadow_bias.z);
  // Horizontally a texel of the atlas, vertically a texel of a tile. With one
  // cascade they are the same number and this is the kernel it has always been.
  vec2 texel = vec2(frag_info.shadow_params.x, frag_info.shadow_cascades.w);

  // **Every tap is held inside its own cascade's tile**, half a texel in from
  // the edge, and after the offset rather than before: the cube atlas learned
  // this first (`PointShadowDistance`). The cascades sit side by side, so a
  // tap that stepped past a seam read the neighbouring cascade's depth,
  // measured through another projection, and a fragment at the edge of the
  // near tile took its shadow partly from the far one. With one cascade the
  // tile is the whole texture and the clamp is the sampler's own edge.
  vec2 tileLo = vec2(float(cascade) / float(cascadeCount), 0.0) + 0.5 * texel;
  vec2 tileHi =
      vec2(float(cascade + 1) / float(cascadeCount), 1.0) - 0.5 * texel;

  // **`textureLod` and not `texture`, and the level asked for is the only one
  // there is.** Everything above this loop is a reason not to be here — the
  // cascade search returns early when no cascade contains the fragment, and the
  // light loop that calls it skips a light facing away — so a WGSL backend sees
  // a sample taken where the four invocations of a quad need not agree, and
  // refuses it: the implicit derivative `texture` asks for is only defined
  // where they all arrive. The cascade atlas is a depth render target with a
  // single level, so the derivative was never doing anything but selecting
  // level zero, and naming that level directly costs nothing and changes no
  // pixel on any backend.
  //
  // **The softness, where it rides, and what zero means.**
  //
  // `ambient_ground.w` is the directional light's apparent size. It has
  // nothing to do with ambient light and everything to do with this being the
  // one component left unspent in a block six shaders share: `frame_params.w`
  // was the slot reserved for exactly this and the environment's level count
  // took it, and appending to the block moves offsets four backends have
  // agreed on. The alternative was a second uniform block bound per draw for
  // one float. Named here because a reader arriving at `ambient_ground` has
  // every right to be surprised.
  //
  // Zero is the 3×3 kernel this has always had, which is what keeps every
  // recorded golden where it is. Above zero the edge widens with the distance
  // between the occluder and what it falls on — what a real light does, and
  // what no fixed kernel can.
  //
  // **Below zero is the `evsm` filter** (`S2`), and the texture bound here is
  // then the moments atlas rather than depth: one filtered tap replaces the
  // kernel, and how far under minus one the value sits is the light-bleeding
  // cut. A sign rather than another uniform, for the reason the softness
  // itself rides here.
  float softness = frag_info.ambient_ground.w;
  float lit = 0.0;
  if (softness < 0.0) {
    // The blur already happened, once for the whole atlas, so the one tap
    // is the filter: the sampler's own bilinear step is all it adds.
    vec4 moments = textureLod(shadow_texture, clamp(uv, tileLo, tileHi), 0.0);
    lit = EvsmVisibility(moments, projected.z - bias,
                         clamp(-softness - 1.0, 0.0, 0.95));
  } else if (softness <= 0.0) {
    // PCF 3x3. Four samples would band visibly at this map size and nine is
    // the smallest kernel that reads as a soft edge rather than as stair
    // steps.
    for (int y = -1; y <= 1; y++) {
      for (int x = -1; x <= 1; x++) {
        float occluder = textureLod(
            shadow_texture,
            clamp(uv + vec2(float(x), float(y)) * texel, tileLo, tileHi),
            0.0).r;
        lit += projected.z - bias > occluder ? 0.0 : 1.0;
      }
    }
    lit *= 1.0 / 9.0;
  } else {
    // **Find what is casting before deciding how wide to blur**, then blur by
    // what a light of this size would leave — `S3`. Sixteen taps each way on
    // a Vogel disc turned per pixel, where there were five fixed ones: the
    // turn trades the five's regular pattern for noise the eye reads as
    // grain, and a temporal resolve averages away.
    //
    // **In metres, per cascade.** The gap between the blocker and this
    // fragment is measured in the cascade's stored depth, whose unit is a
    // different length in each cascade; converted to metres, the penumbra is
    // the gap times the light's apparent diameter, and in texels it is that
    // over the cascade's own texel. A shadow keeps its softness crossing
    // from one cascade into the next.
    float spread = 2.0 * tan(min(softness, 0.5));
    float turn = ShadowNoise() * 6.2831853;

    // As wide as the widest penumbra could be at this depth, and no wider:
    // the whole of the distance back to the light is the largest gap there
    // is.
    float searchRadius =
        clamp(spread * projected.z * cascadeDepth / cascadeTexel, 1.0, 16.0);
    float blockerSum = 0.0;
    float blockerCount = 0.0;
    for (int i = 0; i < 16; i++) {
      float occluder = textureLod(
          shadow_texture,
          clamp(uv + VogelDisc(i, 16, turn) * texel * searchRadius, tileLo,
                tileHi),
          0.0).r;
      if (projected.z - bias > occluder) {
        blockerSum += occluder;
        blockerCount += 1.0;
      }
    }
    // Nothing between this fragment and the light: lit, and no second loop.
    if (blockerCount <= 0.0) return 1.0;

    float gap = max(projected.z - blockerSum / blockerCount, 0.0) * cascadeDepth;
    // One texel at the tightest, so a contact edge stays an edge; the cap
    // keeps a distant occluder from reaching across a whole cascade.
    float radius = clamp(spread * gap / cascadeTexel, 1.0, 16.0);

    for (int i = 0; i < 16; i++) {
      float occluder = textureLod(
          shadow_texture,
          clamp(uv + VogelDisc(i, 16, turn + 1.0) * texel * radius, tileLo,
                tileHi),
          0.0).r;
      lit += projected.z - bias > occluder ? 0.0 : 1.0;
    }
    lit *= 1.0 / 16.0;
  }

  // Strength lerps towards fully lit, so the control is "how dark", not "how
  // much of the kernel".
  return mix(1.0, lit, clamp(strength, 0.0, 1.0));
}

#endif  // SHADOW_GLSL_
