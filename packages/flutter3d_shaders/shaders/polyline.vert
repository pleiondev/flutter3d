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

// **Joins are mitred.** The two vertices at an elbow go out along the bisector
// of the two segments, far enough that both segments keep their full width, so
// the band turns a corner instead of leaving a wedge of screen between two
// quads. A mitre grows without bound as the turn tightens, so past four half
// widths — a turn sharper than about 29 degrees — it is held at four, and the
// band narrows at the tip of a hairpin rather than spiking across the screen.
// A bevel would need a third vertex per point, and this layout has two.
//
// **Within about two and a half degrees of folding straight back on itself,
// the bisector stops being the offset's direction.** See the comment at its
// one use below for the reason and the number; a route this sharp already
// narrows to the clamp above, and a stable tip that does not rotate with the
// camera is worth more than one that carries the bisector exactly.

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

// How long a mitre may get, in half widths. Four is the SVG default for
// `stroke-miterlimit`, which is where most people's sense of a sharp join
// comes from.
const float kMiterLimit = 4.0;

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

  vec2 at = ToPixels(here, viewport);
  vec2 incoming = at - ToPixels(before, viewport);
  vec2 outgoing = ToPixels(after, viewport) - at;

  // The ends of the line have one segment, and the missing one is a copy of
  // this point, so it has no length: use the other.
  if (dot(incoming, incoming) < 1e-12) incoming = outgoing;
  if (dot(outgoing, outgoing) < 1e-12) outgoing = incoming;

  vec2 offset = vec2(0.0);
  if (dot(incoming, incoming) >= 1e-12) {
    vec2 inDir = normalize(incoming);
    vec2 outDir = normalize(outgoing);
    vec2 segmentNormal = vec2(-inDir.y, inDir.x);

    // How far the turn is from folding straight back on itself, from the
    // half-angle identity rather than from the bisector's own length.
    //
    // **The bisector's length is not what was unstable here — its direction
    // was, and only the length was being read.** `dot(miter, segmentNormal)`
    // used to come from a bisector that is the sum of two nearly opposite
    // unit vectors near a reversal, and a screen-space recompute makes that
    // sum's *direction* as sensitive to the camera as the cancellation
    // itself: swept through 180 degrees, the old miter rotated by ninety
    // degrees inside one degree of turn, and the length read off it collapsed
    // from the clamp (4) to nothing (1) exactly at the reversal — backwards,
    // since a reversal is where the join should be at its widest, not its
    // narrowest. `cosHalf` answers the same question without going through
    // that vector at all, and is smooth all the way through it.
    float cosTurn = dot(inDir, outDir);
    float cosHalf = sqrt(max(0.0, (1.0 + cosTurn) * 0.5));

    // Within about two and a half degrees of a straight reversal, the
    // bisector's *direction* — not just its length — is the sum of two
    // nearly cancelling unit vectors, so which way the residue leans flips
    // with the camera rather than with the road. `segmentNormal` depends on
    // `inDir` alone, so past this point it replaces the bisector as the
    // offset's direction; a route this sharp is already past what a two-
    // vertex join was ever going to draw as a clean point, and a stable,
    // correctly clamped tip beats one that spins with the view.
    vec2 miter = cosTurn < -0.999
        ? segmentNormal
        : normalize(vec2(-(inDir + outDir).y, (inDir + outDir).x));

    float stretch = 1.0 / max(cosHalf, 1.0 / kMiterLimit);
    offset = miter * halfWidth * stretch * side;
  }

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
