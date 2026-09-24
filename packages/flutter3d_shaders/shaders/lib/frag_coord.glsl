// Where a fragment sits, counted from the top of its target on every backend.

#ifndef FRAG_COORD_GLSL_
#define FRAG_COORD_GLSL_

/// `gl_FragCoord.xy` with row zero at the top of the picture.
///
/// [rows] is the target's height where the backend's row zero is the bottom
/// of the picture, and zero where it is the top. WebGL2 is the first kind:
/// window coordinates start at the lower left, and the engine draws the
/// picture upright there rather than mirroring every projection. Metal,
/// WebGPU and the software rasteriser are the second.
///
/// **Why a pattern cares and a picture does not.** Every screen-space pattern
/// in the engine — the Bayer dither, the grain, the jitter a ray march starts
/// from, the rotation of a shadow kernel — is a function of the pixel's row.
/// Read from the bottom, the same frame gets the pattern turned upside down,
/// and a four-row Bayer cell lands on different rows unless the height is a
/// multiple of four. The picture underneath is identical; the pattern on top
/// of it is not, and a comparison across backends counts every pixel it
/// moved.
vec2 FragCoordFromTop(float rows) {
  return rows > 0.0 ? vec2(gl_FragCoord.x, rows - gl_FragCoord.y)
                    : gl_FragCoord.xy;
}

#endif  // FRAG_COORD_GLSL_
