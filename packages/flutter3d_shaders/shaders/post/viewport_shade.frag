#version 460 core

// Viewport shading, read out of the surface buffer — `gfx-43n`, `gfx-44n` and
// `gfx-45n`, three branches of one stage.
//
// **This deletes a bug class rather than adding a look.** The modeller's
// normals view works by walking the subject and swapping every material for a
// debug one, remembering the old one to put back; its own docstring documents
// what happens when the remembering fails. Nothing here touches a material.
// The scene pass already wrote a world normal, a roughness and a view-axis
// depth into the second attachment, and every mode below is arithmetic on
// those — so the subject is never modified, there is nothing to restore, and
// a mode is a uniform rather than a traversal.
//
// **The cost is real and is stated where a caller can see it.** Declaring a
// read of the surface buffer attaches the second colour attachment, and
// attachments in one target must agree on sample count, so a frame with any
// of these modes on is a frame the scene pass did not multisample.
// `FrameResult.antiAliasing.msaaDeclined` says so; `anchor_identity_test.dart`
// is where that trade is pinned.
//
// One stage with branches rather than three stages, because all three read the
// same two channels and the difference between them is a handful of lines. A
// branch on a uniform is coherent across the whole draw — every fragment takes
// the same one — so it costs a compare and not a divergence.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;

uniform ShadeInfo {
  // x: which mode. 0 leaves the picture alone, 1 normals as colour, 2 clay,
  // 3 outline, 4 curvature. z and w below mean different things per mode,
  // which is what keeps this to one block.
  // y: how much of the shaded result to mix over the lit picture, 0 to 1.
  // z: mode 2 — how much ambient sits under the studio light. mode 3 — the
  //    depth difference, in metres, an edge starts at. mode 4 — the gain on
  //    the curvature estimate.
  // w: mode 3 — how far apart in angle two normals must be to count as an
  //    edge, in cosine. mode 4 — how much of the cavity is darkened rather
  //    than lit.
  vec4 params;

  // x, y: one texel. z: the outline's width in texels. w: unused.
  vec4 screen;

  // xyz: which way the studio light points, for mode 2. w: unused.
  vec4 light;
}
shade_info;

// The octahedral decode every reader of this buffer keeps — see `ssao.frag`,
// which carries the argument for the encoding.
vec3 DecodeOctahedral(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

void main() {
  vec4 scene = texture(scene_texture, v_uv);
  int mode = int(shade_info.params.x + 0.5);
  float mix_amount = clamp(shade_info.params.y, 0.0, 1.0);
  if (mode < 1 || mix_amount <= 0.0) {
    frag_color = scene;
    return;
  }

  vec4 surface = texture(surface_texture, v_uv);
  float depth = surface.a;
  // Nothing was drawn here: the buffer is cleared to zero and a normal
  // decoded from that is a direction pointing nowhere. The background keeps
  // whatever the scene left, which is what makes every mode below a shading
  // of the *subject* rather than a wash over the frame.
  if (depth <= 0.0) {
    frag_color = scene;
    return;
  }

  vec3 normal = DecodeOctahedral(surface.rg);
  vec3 shaded = scene.rgb;

  if (mode == 1) {
    // **Normals as colour**, the mode the material swap existed for. The
    // usual half-and-half mapping, so a surface facing the camera is the
    // pale blue everybody recognises from every other modeller.
    shaded = normal * 0.5 + 0.5;
  } else if (mode == 2) {
    // **Clay**: one studio light and an ambient floor, no texture, no
    // material. What it is for is shape — a form with its albedo taken away,
    // which is the whole reason a sculptor turns it on.
    float ambient = clamp(shade_info.params.z, 0.0, 1.0);
    float lambert = max(dot(normal, normalize(shade_info.light.xyz)), 0.0);
    shaded = vec3(ambient + (1.0 - ambient) * lambert);
  } else if (mode == 3) {
    // **Outline**, from depth *and* normal, because either alone misses half
    // the edges a modeller is looking for. A depth step finds a silhouette
    // and misses a crease in a flat wall; a normal step finds the crease and
    // misses two surfaces at the same angle one behind the other. Both, and
    // an edge is either.
    vec2 texel = shade_info.screen.xy * max(shade_info.screen.z, 1.0);
    float depthEdge = 0.0;
    float normalEdge = 0.0;
    // Four neighbours rather than eight: a Sobel would weight diagonals it
    // then has to normalise, and the answer here is a threshold rather than a
    // gradient direction.
    vec2 offsets[4] = vec2[4](
        vec2(texel.x, 0.0), vec2(-texel.x, 0.0),
        vec2(0.0, texel.y), vec2(0.0, -texel.y));
    for (int i = 0; i < 4; i++) {
      vec4 tap = texture(surface_texture, v_uv + offsets[i]);
      if (tap.a <= 0.0) {
        // Against the background: that is a silhouette, and the strongest
        // edge there is.
        depthEdge = 1.0;
        continue;
      }
      depthEdge = max(depthEdge, abs(tap.a - depth));
      normalEdge =
          max(normalEdge, 1.0 - dot(DecodeOctahedral(tap.rg), normal));
    }

    float depthHit = step(max(shade_info.params.z, 1e-4), depthEdge);
    float normalHit = step(max(shade_info.params.w, 1e-4), normalEdge);
    float edge = max(depthHit, normalHit);
    // The line is drawn *dark over the picture* rather than as its own
    // colour: an outline that replaced the pixel would hide the shading it is
    // meant to clarify.
    shaded = scene.rgb * (1.0 - edge);
  } else if (mode == 4) {
    // **Curvature and cavity**, from how fast the normal field turns. The
    // divergence of the normals across a pixel: a convex ridge turns one way,
    // a concave crease the other, and a flat face does not turn at all.
    //
    // Read from the normal buffer rather than from depth, deliberately: a
    // depth-based curvature is dominated by how far away the surface is, so a
    // model twice as far reads as half as detailed. A normal field is the same
    // at any distance.
    vec2 texel = shade_info.screen.xy;
    vec3 right = DecodeOctahedral(
        texture(surface_texture, v_uv + vec2(texel.x, 0.0)).rg);
    vec3 left = DecodeOctahedral(
        texture(surface_texture, v_uv - vec2(texel.x, 0.0)).rg);
    vec3 down = DecodeOctahedral(
        texture(surface_texture, v_uv + vec2(0.0, texel.y)).rg);
    vec3 up = DecodeOctahedral(
        texture(surface_texture, v_uv - vec2(0.0, texel.y)).rg);

    // The x component of the horizontal change plus the y of the vertical:
    // the screen-space divergence, which is positive on a ridge and negative
    // in a groove.
    float curvature = ((right.x - left.x) + (down.y - up.y)) *
                      max(shade_info.params.z, 0.0);
    float cavity = clamp(-curvature, 0.0, 1.0) *
                   clamp(shade_info.params.w, 0.0, 1.0);
    float ridge = clamp(curvature, 0.0, 1.0);
    // Grey, lit on the ridges and darkened in the cavities, which is what a
    // cavity map is read for: the creases a sculpt has, seen without its
    // colour.
    shaded = vec3(clamp(0.5 + ridge * 0.5 - cavity, 0.0, 1.0));
  }

  frag_color = vec4(mix(scene.rgb, shaded, mix_amount), scene.a);
}
