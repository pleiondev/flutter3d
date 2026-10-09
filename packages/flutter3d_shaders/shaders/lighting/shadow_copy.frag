#version 460 core

// Copies one cascade's tile of the static shadow atlas into the frame's own
// — `S1`.
//
// The directional atlas is split the way the cube atlases are: static casters
// in one atlas drawn when they change, and a per-frame atlas that starts each
// redrawn tile from the static one and draws the dynamic casters on top. The
// copy has to carry depth as well as colour, or a dynamic caster behind a
// static wall would pass the depth test against a cleared buffer and write
// its farther depth over the wall's. So this writes the stored depth, which
// is window depth by construction (see `shadow_depth.frag`), to both.
//
// Drawn with the fullscreen triangle inside the tile's viewport, with the
// depth test off and depth writes on.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D static_shadow_texture;

uniform ShadowCopyInfo {
  /// xy: where this tile starts in the atlas, zw: its size, both in the
  /// atlas's own texture coordinates.
  vec4 tile;

  /// A scroll — `S1`: xy how far back, in the tile's own coordinates, the
  /// texel this one shows was held; z what the move added to every stored
  /// depth. Nought for a plain copy. A texel whose source lies outside the
  /// tile is the strip that scrolled in, and reads as nothing there, for
  /// the casters drawn into it next.
  ///
  /// w: how the source stores its depth, and what is written — `A2.8`, the
  /// modes `lib/shadow_storage.glsl` lists. Nought copies a map drawn the
  /// ordinary way, where nothing is one. One copies a map turned round into
  /// another, where nothing is nought and z is already the move in the
  /// stored direction. Two reads a map turned round and writes the depth the
  /// ordinary way, for a pass that compares against it as drawn — the
  /// caustics' copy of a tile.
  vec4 shift;
}
copy_info;

void main() {
  vec2 from = v_uv - copy_info.shift.xy;
  bool inside = all(greaterThanEqual(from, vec2(0.0))) &&
                all(lessThanEqual(from, vec2(1.0)));
  float stored =
      textureLod(static_shadow_texture,
                 copy_info.tile.xy + clamp(from, 0.0, 1.0) * copy_info.tile.zw,
                 0.0)
          .r;
  // Nothing stays nothing: the far end is not a depth the move shifts. It is
  // one the ordinary way round and nought turned round.
  float mode = copy_info.shift.w;
  float nothing = mode > 0.5 ? 0.0 : 1.0;
  float depth = inside && stored != nothing
                    ? clamp(stored + copy_info.shift.z, 0.0, 1.0)
                    : nothing;
  if (mode > 1.5) depth = 1.0 - depth;
  frag_color = vec4(depth, 0.0, 0.0, 1.0);
  gl_FragDepth = depth;
}
