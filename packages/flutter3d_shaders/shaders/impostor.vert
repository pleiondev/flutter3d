#version 460 core

// An octahedral impostor's card, turned to face the eye here rather than on
// the CPU — C4.
//
// **The standard vertex layout, repacked**, the way polyline.vert repacks it:
//
//   position   a corner of the card as built, upright in the XY plane around
//              the middle of the baked sphere — not where it is drawn, but
//              what the engine measures a node's bounds from, so a card is
//              culled and sized for a level of detail by the sphere it
//              stands in; the middle is this less the corner's offset
//   normal     +Z, the way the card as built faces
//   texcoord   which corner: (0, 0) top left to (1, 1) bottom right
//   tangent    w the sphere's radius in the node's own space; xyz unused
//   color      a the card's opacity, carried to the fragment stage
//
// **Every input is read.** The vertex layout is taken from the declarations
// in order, and an input the compiler drops is a reflection that no longer
// matches the buffer — impellerc refuses the stage outright.
//
// **The eye comes out of the matrix, not out of a uniform.** A card has to
// know where it is looked at from, and FrameInfo is three matrices with no
// camera in them. The eye is the one point every clip row but z sends to
// nought — x, y and w are all zero there — so three rows of the mvp are a
// 3 x 3 system whose answer is the eye in this node's own space, solved below
// by cross products because WGSL has no `inverse`. An orthographic camera has
// no such point: its w row is constant, the system is singular, and the
// direction to the eye is then the one clip depth falls along.
//
// **Varyings, and what each carries** — the lit stage reads the surface
// through them:
//
//   v_normal     the card's facing, in the world: the direction to the eye
//   v_tangent    the card's right-hand axis in the world, w one
//   v_texcoord   the corner, interpolated: where on the card a fragment is
//   v_color      xyz the direction to the eye in the node's own space, which
//                is what picks the baked views; w the vertex alpha

#include <lib/impostor.glsl>

in vec3 position;
in vec3 normal;
in vec2 texcoord;
in vec4 tangent;
in vec4 color;

uniform FrameInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
}
frame_info;

out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_tangent;
out vec4 v_color;
out vec2 v_lightmap_uv;

vec4 MvpRow(int r) {
  return vec4(frame_info.mvp[0][r], frame_info.mvp[1][r],
              frame_info.mvp[2][r], frame_info.mvp[3][r]);
}

void main() {
  float radius = tangent.w;
  vec3 centre = position - vec3(texcoord.x * 2.0 - 1.0,
                                1.0 - texcoord.y * 2.0, 0.0) * radius;

  vec4 rx = MvpRow(0);
  vec4 ry = MvpRow(1);
  vec4 rz = MvpRow(2);
  vec4 rw = MvpRow(3);
  vec3 yw = cross(ry.xyz, rw.xyz);
  vec3 wx = cross(rw.xyz, rx.xyz);
  vec3 xy = cross(rx.xyz, ry.xyz);
  float det = dot(rx.xyz, yw);
  vec3 eye = -(rx.w * yw + ry.w * wx + rw.w * xy) /
             (abs(det) > 1e-20 ? det : 1.0);
  vec3 toEye = abs(det) > 1e-20 ? eye - centre : -rz.xyz;
  // An eye at the very middle of the sphere sees the card as it was built.
  vec3 d = normalize(dot(toEye, toEye) > 1e-20 ? toEye : normal);

  vec3 right = ImpostorRight(d);
  vec3 up = cross(d, right);
  vec3 corner = centre + (right * (texcoord.x * 2.0 - 1.0) +
                          up * (1.0 - texcoord.y * 2.0)) * radius;

  v_world_position = (frame_info.model * vec4(corner, 1.0)).xyz;
  v_normal = normalize(mat3(frame_info.normal_matrix) * d);
  v_tangent = vec4(normalize(mat3(frame_info.model) * right), 1.0);
  v_texcoord = texcoord;
  v_color = vec4(d, color.a);
  v_lightmap_uv = vec2(0.0);

  gl_Position = frame_info.mvp * vec4(corner, 1.0);
}
