// Morph targets, applied in the vertex stage from a texture of deltas.
//
// ## Why a texture and not attributes
//
// The vertex layout in this engine is **structural**: the `in` declarations of
// `mesh.vert` are the layout, and one layout serves every model so that a
// lighting model needs one pipeline rather than one per attribute set. Morph
// deltas as attributes would mean a second layout, and with it a second vertex
// shader for every lighting model — six of them — and a second pipeline for
// each. A texture read by vertex index costs one sampler and no layout at all.
//
// That the read is possible is measured rather than assumed:
// `checkVertexTextureSampling` in `flutter3d_conformance` draws through a
// vertex stage that samples, on all three backends. It answers yes on each,
// Impeller included, which was the one that could not be settled by reading a
// header.
//
// ## The layout of the texture
//
// `r32g32b32a32Float`, width = the mesh's vertex count, height = one row per
// delta stream per target. Target *t* occupies rows `t * MORPH_ROWS` upwards:
//
//     row + 0   position delta, xyz
//     row + 1   normal delta, xyz     (zero when the file carried none)
//     row + 2   tangent delta, xyz    (zero when the file carried none)
//
// Three rows always, so the arithmetic is a multiply rather than a table: a
// target that morphs only positions costs two rows of zeros, which is memory
// and not branches. `MorphTargetTexture` on the Dart side packs exactly this.
//
// **`texture` at a texel centre, and it should have been `texelFetch`.** There
// is nothing to filter — a vertex has exactly one delta per target — so the
// fetch is the operation this wants: no size arithmetic, no sampler state, no
// half-texel to get wrong.
//
// It is not used because **impellerc crashes on `texelFetch` in a vertex
// stage**: SIGABRT, no diagnostic, exit 134. Bisected — the same call in a
// *fragment* stage compiles, `gl_VertexIndex` alone compiles, and `texture()`
// in a vertex stage compiles, so it is that one combination. So the coordinate
// is built by hand, `(index + 0.5) / size`, and the sampler is bound nearest
// and clamped: exactly the texel, reached the long way round. The size comes
// down in `morph_params` rather than from `textureSize`, which is one more
// thing that would have to survive the same compiler.

#ifndef MORPH_GLSL_
#define MORPH_GLSL_

/// Rows of the delta texture each target occupies. See the header.
const int kMorphRows = 3;

/// The most targets one draw can blend.
///
/// Eight because glTF's own guidance is that an engine support at least eight
/// active targets, and because a `vec4[2]` is two registers. A model carrying
/// more is not refused — the renderer sends the first eight and says so, which
/// is a face missing an expression rather than a face that will not load.
const int kMorphMax = 8;

uniform sampler2D morph_texture;

uniform MorphInfo {
  /// Weight of target *i* at `morph_weights[i / 4][i % 4]`.
  vec4 morph_weights[2];

  /// x: how many targets are active, as a float.
  /// y: one texel across, `1 / width`. z: one texel down, `1 / height`.
  /// w unused.
  ///
  /// A count rather than a convention that a zero weight means absent: a
  /// target held at exactly nought is a face that is not smiling, and reading
  /// it as "the list ends here" would stop the ones after it.
  vec4 morph_params;
}
morph_info;

/// Adds the blended deltas onto one vertex.
///
/// Called with the attributes as they were read and before anything else
/// touches them — skinning included, which is the order glTF specifies: a
/// skinned morphed mesh morphs in its rest pose and is then posed by the
/// skeleton.
///
/// The tangent is a `vec4` and only its xyz move: w is the bitangent sign, a
/// handedness rather than a direction, and glTF does not morph it.
void ApplyMorph(inout vec3 position, inout vec3 normal, inout vec4 tangent) {
  int count = int(morph_info.morph_params.x + 0.5);
  if (count <= 0) return;

  // The vertex's own column: the index this vertex was drawn with, which is
  // exactly the row of the delta arrays the loader built.
  //
  // **`gl_VertexIndex`, spelt the way SPIR-V spells it.** GLSL ES 3.00 calls
  // the same builtin `gl_VertexID`, and the browser backend's translator
  // rewrites the name on its way out — one substitution beside the ones it
  // already makes for `#version` and `layout(std140)`. Written the other way
  // round, impellerc refuses it outright: "undeclared identifier (Did you mean
  // gl_VertexIndex?)", which is the friendliest error in this repository.
  float column = (float(gl_VertexIndex) + 0.5) * morph_info.morph_params.y;
  float rowStep = morph_info.morph_params.z;

  for (int i = 0; i < kMorphMax; i++) {
    if (i >= count) break;
    float weight = morph_info.morph_weights[i / 4][i % 4];
    if (weight == 0.0) continue;

    float row = (float(i * kMorphRows) + 0.5) * rowStep;
    position += texture(morph_texture, vec2(column, row)).xyz * weight;
    normal += texture(morph_texture, vec2(column, row + rowStep)).xyz * weight;
    tangent.xyz +=
        texture(morph_texture, vec2(column, row + rowStep * 2.0)).xyz * weight;
  }
}

#endif  // MORPH_GLSL_
