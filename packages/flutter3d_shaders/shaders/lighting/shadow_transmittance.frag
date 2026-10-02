#version 460 core

// What a see-through caster lets through to the sun's shadow map —
// `ShadowSettings.translucentCasters`.
//
// Drawn after the opaque casters into the same atlas, depth-tested against
// them and writing no depth of its own, so a pane behind a wall adds nothing
// and two panes in a row both count.
//
// **The atlas's other three channels, in a layout chosen so that every other
// stage keeps writing exactly what it wrote.** Red stays the depth. Green and
// blue hold how much of red and green is *taken away*, and alpha how much of
// blue is *let through*: an opaque caster writes (z, 0, 0, 1) and so says
// "nothing taken" without knowing this stage exists, and so does the static
// tile's copy. The pass blends green and blue as `src + dst·(1 − src)`, which
// is what absorption does over layers — 1 − (1 − a)(1 − b) — and leaves red
// alone because red comes in as nought; alpha it multiplies.
//
// What one surface lets through:
//
//   * the share of it that is not there at all, 1 − opacity;
//   * of the share that is, what its transmission passes, tinted by its
//     colour;
//   * and of that, what is not reflected away at its surface, from the
//     Schlick term of its index — which is what makes the rim of a glass, met
//     at a grazing angle, darker than its middle.
//
// Where refracted light lands — the bright line down a tube's shadow — is
// not here: that needs the ray followed through both surfaces, and this
// stage sees one at a time.
//
// The body's share is taken as a square root because a closed caster is
// recorded from both of its sides: light crosses its body once, and its two
// surfaces between them give it once. A caster recorded from one side only
// comes out lighter than it is, never darker.

#define F3D_NO_SURFACE_BUFFER
#define F3D_NO_FOG

#include <lib/color.glsl>

uniform TransmittanceInfo {
  /// rgb: the colour light comes out of it: the base colour, and for a
  /// material that transmits, times what its volume leaves after its
  /// thickness. a: its opacity — one for a material that is not blended, and
  /// for one that transmits, whose alpha describes its look rather than
  /// holes in it.
  vec4 color;

  /// xyz: the direction towards the light, in the world. w unused.
  vec4 light;

  /// x: the transmission, nought for a material that has none. y: the
  /// reflectance head-on, ((n − 1) / (n + 1))² of its index. zw unused.
  vec4 params;
}
transmittance_info;

void main() {
  float opacity = clamp(transmittance_info.color.a, 0.0, 1.0);
  float transmission = clamp(transmittance_info.params.x, 0.0, 1.0);
  vec3 body = vec3(1.0 - opacity) +
              opacity * transmission * clamp(transmittance_info.color.rgb, 0.0, 1.0);

  float facing = abs(dot(normalize(v_normal), transmittance_info.light.xyz));
  float f0 = clamp(transmittance_info.params.y, 0.0, 1.0);
  float fresnel = f0 + (1.0 - f0) * pow(1.0 - clamp(facing, 0.0, 1.0), 5.0);

  vec3 through = sqrt(max(body, vec3(0.0))) * (1.0 - fresnel);
  frag_color = vec4(0.0, 1.0 - through.r, 1.0 - through.g, through.b);
}
