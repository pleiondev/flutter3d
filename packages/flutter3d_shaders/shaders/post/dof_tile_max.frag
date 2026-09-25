#version 460 core

// The largest circle of confusion along one row of a tile — `gfx-34n`.
//
// The first step of the depth of field's neighbourhood, and the only one of
// its own: the frame is cut into square tiles as wide as the largest circle,
// and this walks each tile's rows, turning depth into a circle as it goes.
// The columns and the three-by-three neighbourhood that follow are the motion
// blur's own passes (`VelocityTileMax`, `VelocityNeighborMax`) reading a
// circle in red and nought in green, which is a motion whose length is the
// circle.
//
// **Why the gather needs it.** A pixel gathers from as far as the largest
// circle that could reach it, not from as far as its own: a sharp pixel
// beside a blurred foreground has a circle of nought and still lies under the
// foreground's disc.

#include <lib/circle_of_confusion.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform DofTileInfo {
  // As `DofInfo.lens`: focus distance, focal length, f-number. w unused.
  vec4 lens;

  // As `DofInfo.params`: xy unused, z the largest circle in texels, w texels
  // per metre across the sensor.
  vec4 params;

  // xy: one texel of the scene, the grid the gather samples on. z: texels
  // per tile. w unused.
  vec4 source;

  // xy: this target's size in texels. zw unused.
  vec4 target;
}
dof_tile_info;

void main() {
  // `textureLod`, for `velocity_tile_max.frag`'s reason: a loop whose exit
  // is per fragment.
  int taps = int(dof_tile_info.source.z + 0.5);
  vec2 texel = floor(v_uv * dof_tile_info.target.xy);
  float row = (texel.y + 0.5) * dof_tile_info.source.y;
  float first = texel.x * float(taps);

  float largest = 0.0;
  for (int i = 0; i < 64; i++) {
    if (i >= taps) break;
    vec2 at = vec2((first + float(i) + 0.5) * dof_tile_info.source.x, row);
    float depth = textureLod(surface_texture, at, 0.0).a;
    largest = max(largest,
                  CircleOfConfusion(depth, dof_tile_info.lens,
                                    dof_tile_info.params));
  }
  frag_color = vec4(largest, 0.0, 0.0, 1.0);
}
