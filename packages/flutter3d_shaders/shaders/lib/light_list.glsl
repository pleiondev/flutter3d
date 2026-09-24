// The frame's light list, and how a fragment finds its tail in it — `gfx-74n`
// and `L6`.
//
// Split out of `surface.glsl` so a stage that is not a surface can read the
// same lights: `N6`'s six-way particles light each fragment by the list the
// lit models read, clusters and all, without declaring `FragInfo`. The text is
// the one that stood in `surface.glsl`, moved rather than copied, so the lit
// models compile to what they compiled to before.

#ifndef LIGHT_LIST_GLSL_
#define LIGHT_LIST_GLSL_
/// Every light in the scene, one per row, four texels across — `gfx-74n`.
///
/// **A texture rather than a wider uniform block, and that is the design.**
/// `FragInfo` is uploaded on every draw, so widening its four `vec4` arrays to
/// hold thirty-two lights would be a two-kilobyte upload per draw in every
/// scene, including every scene with one light. This is built once a frame and
/// only when a scene has more lights than a draw can hold in its slots.
///
/// Row layout, which `renderer_light_list.dart` writes and only this reads:
///
///  * texel 0 — xyz world position, w type (0 directional, 1 point, 2 spot)
///  * texel 1 — rgb linear colour, w intensity
///  * texel 2 — xyz the direction it points, w range
///  * texel 3 — x cos(inner), y cos(outer), zw unused
///
/// The same four vectors the uniform arrays hold, in the same order, so one
/// reader serves both.
///
/// **`F3D_NO_LIGHT_LIST` leaves both out**, for a model that accumulates no
/// lights. Such a model never reaches the reader below, so the compiler drops
/// the block and the sampler from the Metal function while reflection still
/// lists them, with no buffer or texture index assigned. The renderer used to
/// bind them for every draw, Unlit included, and that bind is a crash inside
/// `setFragmentBuffer:offset:atIndex:` on Metal. Vulkan took the same draw
/// without a word, which is how 0.7.0 shipped with it.
#ifndef F3D_NO_LIGHT_LIST
uniform sampler2D light_list_texture;

uniform LightListInfo {
  /// x: how many rows this draw reads, zero when it reads none.
  /// y, z: one over the texture's width and height.
  /// w: unused.
  vec4 list;

  /// Which rows, four to a vector, in the order they are read.
  ///
  /// Indices rather than the light data itself: the data is the same for every
  /// draw in the frame and belongs in the texture; what differs per draw is
  /// *which* of them reach it, and that is what `Renderer._drawLightsFor`
  /// already decides.
  vec4 indices[6];

  /// How much of each of those survives the edge fade, in the same order.
  ///
  /// Per draw and not in the texture, because the row an index points at is
  /// shared by every draw in the frame: a scale written into it would dim that
  /// light for all of them. `gfx-12n`'s fade lives at the end of the list now —
  /// that is where a light stops contributing, and fading the slots against a
  /// water line that no longer marks a cliff would dim a light for no reason
  /// while its rival stayed bright, making the swap more visible rather than
  /// less.
  vec4 scales[6];

  /// `L6`: the view-projection the light clusters were cut with, so this
  /// finds a fragment's cell the way `LightClusters.clusterOf` does.
  mat4 cluster_view_projection;

  /// xyz: tiles across, tiles up, slices deep. w: one when this draw reads
  /// its tail from the cell it is in rather than from `indices`.
  vec4 cluster_grid;

  /// x: where slices begin, in clip w. y: slices per unit of `ln(w / x)`.
  /// z: the texture row the cells' headers start at, four to a row, each
  /// (offset, count). w: the row their entries start at, sixteen to a row.
  vec4 cluster_depth;

  /// Which rows this draw already holds in its eight slots, minus one for
  /// an empty slot. A cell lists every light that reaches it, and one the
  /// slots already carry must not be counted again.
  vec4 slot_rows[2];
}
light_list_info;

/// One lane of a six-vector table, [slot] counting from nought.
float LightListLane(vec4 four, int slot) {
  int lane = slot - (slot / 4) * 4;
  return lane == 0 ? four.x : lane == 1 ? four.y : lane == 2 ? four.z : four.w;
}

/// The row light [slot] of the list reads.
float LightListRow(int slot) {
  return LightListLane(light_list_info.indices[slot / 4], slot);
}

/// How much of light [slot] of the list survives the edge fade.
float LightListScale(int slot) {
  return LightListLane(light_list_info.scales[slot / 4], slot);
}

/// The cell this fragment falls in, as `LightClusters` wrote it: where its
/// entries start and how many there are. Found once, in [LightCount], and
/// read by every [SampleLight] of the loop that follows.
float g_cluster_offset = 0.0;
float g_cluster_count = 0.0;

bool Clustered() { return light_list_info.cluster_grid.w > 0.5; }

/// One texel of the light list texture, [texel] across and [row] down.
vec4 LightListTexel(float texel, float row) {
  return textureLod(light_list_texture,
                    vec2((texel + 0.5) * light_list_info.list.y,
                         (row + 0.5) * light_list_info.list.z),
                    0.0);
}

void FindCluster(vec3 world) {
  vec4 clip = light_list_info.cluster_view_projection * vec4(world, 1.0);
  vec2 ndc = clip.xy / max(clip.w, 1e-6);
  vec3 grid = light_list_info.cluster_grid.xyz;
  float near = light_list_info.cluster_depth.x;
  float tx = clamp(floor((ndc.x * 0.5 + 0.5) * grid.x), 0.0, grid.x - 1.0);
  float ty = clamp(floor((ndc.y * 0.5 + 0.5) * grid.y), 0.0, grid.y - 1.0);
  float tz = clip.w <= near
                 ? 0.0
                 : clamp(floor(log(clip.w / near) *
                               light_list_info.cluster_depth.y),
                         0.0, grid.z - 1.0);
  float cell = tx + ty * grid.x + tz * grid.x * grid.y;
  float row = floor(cell / 4.0);
  vec4 header =
      LightListTexel(cell - row * 4.0, light_list_info.cluster_depth.z + row);
  g_cluster_offset = header.x;
  g_cluster_count = header.y;
}

/// The row entry [slot] of this fragment's cell names.
float ClusterRow(int slot) {
  float entry = g_cluster_offset + float(slot);
  float row = floor(entry / 16.0);
  float within = entry - row * 16.0;
  float texel = floor(within / 4.0);
  vec4 four = LightListTexel(texel, light_list_info.cluster_depth.w + row);
  return LightListLane(four, int(within - texel * 4.0 + 0.5));
}

/// Whether one of the draw's slots already holds light list row [row].
bool InSlots(float row) {
  vec4 a = abs(light_list_info.slot_rows[0] - vec4(row));
  vec4 b = abs(light_list_info.slot_rows[1] - vec4(row));
  return min(min(min(a.x, a.y), min(a.z, a.w)), min(min(b.x, b.y), min(b.z, b.w))) < 0.5;
}
#endif  // F3D_NO_LIGHT_LIST

#endif  // LIGHT_LIST_GLSL_
