// The target's orientation, for a full-screen pass.
//
// Its own block rather than a member of each pass's, so the renderer binds it
// in one place, `drawFullscreen`, for every stage that declares it — the
// contract answers false for a stage that does not, and a pass that adds a
// screen-space pattern later gets the right rows by including this file.

#ifndef FRAG_COORD_INFO_GLSL_
#define FRAG_COORD_INFO_GLSL_

#include <lib/frag_coord.glsl>

uniform FragCoordInfo {
  /// x: the target's rows when its row zero is the bottom of the picture,
  /// zero when it is the top — see [FragCoordFromTop]. yzw unused.
  vec4 origin;
}
frag_coord_info;

/// This fragment's position with row zero at the top of the target.
vec2 TargetFragCoord() {
  return FragCoordFromTop(frag_coord_info.origin.x);
}

#endif  // FRAG_COORD_INFO_GLSL_
