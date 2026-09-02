#version 460 core

// `mesh.vert` for a level with a baked lightmap.
//
// The same vertex layout as every other model — see mesh.vert for why there
// is one — with one attribute read differently: `color.xy` carries the
// vertex's place in the lightmap rather than a tint. A brush face has no
// vertex colour to lose, and a fourth vertex layout would be a fourth
// pipeline per lighting model on three backends for two floats. So the
// level's geometry writes its second coordinate where the colour goes, and
// this stage hands the fragment an opaque white tint and the coordinate.
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

void main() {
  vec4 world = frame_info.model * vec4(position, 1.0);
  v_world_position = world.xyz;
  v_normal = mat3(frame_info.normal_matrix) * normal;
  v_texcoord = texcoord;
  v_tangent = vec4(mat3(frame_info.model) * tangent.xyz, tangent.w);
  v_color = vec4(1.0);
  v_lightmap_uv = color.xy;

  gl_Position = frame_info.mvp * vec4(position, 1.0);
}
