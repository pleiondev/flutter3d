#version 460 core

// A polyline of constant screen width, widened here rather than on the CPU —
// gfx-86n.
//
// **Why a vertex stage and not a rebuilt buffer.** The width is a number of
// pixels, so where a band's edges go depends on the camera, and working them
// out on the CPU means rebuilding the whole line every time the camera moves.
// For a route of tens of thousands of points that is a rebuild per frame. Here
// the camera is `frame_info.mvp`, which the renderer already sets per draw, so
// the buffer is written once and a camera move costs a uniform.
//
// **The standard vertex layout, repacked.** A material's vertex stage reads the
// same sixteen floats every mesh does (see mesh.vert), because the engine lays
// out one format for every draw. A line needs different things from a vertex,
// and they fit into the same slots:
//
//   position   this point
//   normal     the previous point (this one again at the start of the line)
//   texcoord   x the distance along the line in metres, y 0 on one side and
//              1 on the other — passed through, for a fragment stage that
//              wants dashes or an edge falloff
//   tangent    xyz the next point (this one again at the end), w the half
//              width in pixels, signed for which side of the line this is
//   color      the colour at this point, which is what makes a gradient
//
// Each point is two vertices, one per side.
//
// **The viewport comes from the material's own block**, because nothing the
// engine binds to a vertex stage carries it: FrameInfo is three matrices and is
// shared with every mesh stage. `Material.parameters` is the channel an
// application already had for its own shaders; the renderer now hands it to a
// vertex stage the material brought as well, so a resize is one parameter
// written and not a rebuilt line.
//
// **A joint's own width, not a mitre.** Earlier this offset each point by a
// bisector of its two neighbouring segments, stretched to keep both segments
// full width through the turn — correct on paper, and unstable in practice:
// the stretch depends on the *angle* between two independently projected
// directions, and a projection has no floor on how extreme an angle it will
// report. A route that turns a modest 30 degrees in three dimensions can
// still turn near 180 degrees on screen from the right camera angle — most
// of it looking down the route's own general plane — and at that point the
// stretch a `stroke-miterlimit`-style clamp allows (four half widths) is
// already enough for a handful of neighbouring joints to cover a shape that
// has itself foreshortened to a sliver, which is what a turn's own
// mathematically-correct mitre looked like exploding into unrelated
// triangles as the camera swept past that angle.
//
// The offset here is instead the perpendicular of one direction per point —
// the direction from the point before this one to the point after it, which
// is exactly the *only* direction there is at either end of the line, where
// one of those two is a copy of this point. No angle between two directions
// is ever computed, so there is nothing here for an extreme projection to
// destabilise; the trade is a corner that can pinch inward on a sharp turn
// rather than one that mitres outward to meet both segments exactly — the
// same trade a plain averaged-tangent ribbon makes, for the same reason, and
// the one gfx-86n's original mitre existed to avoid. A pinch is bounded by
// the line's own half width; the mitre it replaced was not
// bounded by anything a viewer could see coming.

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

uniform MaterialParams {
  /// xy: the render target in pixels. zw unused.
  vec4 viewport;
}
params;

out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_texcoord;
out vec4 v_tangent;
out vec4 v_color;
out vec2 v_lightmap_uv;

// The w below which a point is treated as at the eye. Dividing by a w near zero
// sends a neighbour to infinity, and dividing by a negative one mirrors it
// through the centre of the screen — either turns the band sideways.
const float kNear = 1e-4;

// `from`, moved along the segment towards `to` until it is in front of the eye.
//
// A neighbour behind the camera would otherwise divide into the wrong half of
// the screen, and the direction of the segment — which is all a neighbour is
// used for — would point backwards.
vec4 InFront(vec4 from, vec4 to) {
  if (from.w >= kNear) return from;
  float t = (kNear - from.w) / (to.w - from.w);
  return mix(from, to, clamp(t, 0.0, 1.0));
}

// A clip position in pixels from the centre of the viewport.
vec2 ToPixels(vec4 clip, vec2 viewport) {
  return clip.xy / clip.w * viewport * 0.5;
}

void main() {
  vec2 viewport = params.viewport.xy;
  float halfWidth = abs(tangent.w);
  float side = tangent.w < 0.0 ? -1.0 : 1.0;

  vec4 here = frame_info.mvp * vec4(position, 1.0);
  vec4 before = frame_info.mvp * vec4(normal, 1.0);
  vec4 after = frame_info.mvp * vec4(tangent.xyz, 1.0);

  // A point behind the eye is pulled forward along whichever segment reaches
  // the front, so the visible part of that segment is drawn where it is. Both
  // neighbours behind as well means nothing of this point is visible, and it
  // is left where the clipper will discard it.
  if (here.w < kNear) {
    here = after.w >= kNear ? InFront(here, after) : InFront(here, before);
  }
  before = InFront(before, here);
  after = InFront(after, here);

  // From the point before this one straight to the point after it — skipping
  // `here` itself, so an end of the line (where one neighbour is a copy of
  // `here`) reduces to the one direction that neighbour alone gives, with
  // nothing to fall back from.
  vec2 dir = ToPixels(after, viewport) - ToPixels(before, viewport);
  float dirLength = length(dir);
  // A pair of coincident points on screen — a true zero-length line, not
  // just a foreshortened one — has no direction to be wide across; any
  // perpendicular is as good as any other for the one degenerate pixel it
  // affects.
  vec2 segmentNormal = dirLength > 1e-9
      ? vec2(-dir.y, dir.x) / dirLength
      : vec2(1.0, 0.0);

  vec2 offset = segmentNormal * halfWidth * side;

  // Back from pixels to clip space, at this point's own w, so the offset is the
  // same number of pixels at every depth.
  gl_Position =
      vec4(here.xy + offset / (viewport * 0.5) * here.w, here.zw);

  v_world_position = (frame_info.model * vec4(position, 1.0)).xyz;
  // A band has no normal of its own. Up is what a route drawn over ground
  // faces, and it is a unit vector, which is what ReadSurface normalises —
  // zero would be a NaN in every screen-space effect that reads the buffer.
  v_normal = normalize(mat3(frame_info.normal_matrix) * vec3(0.0, 1.0, 0.0));
  v_texcoord = texcoord;
  v_tangent = vec4(1.0, 0.0, 0.0, 1.0);
  v_color = color;
  v_lightmap_uv = vec2(0.0);
}
