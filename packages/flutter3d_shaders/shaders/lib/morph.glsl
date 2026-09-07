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

/// How many targets this draw blends.
int MorphCount() { return int(morph_info.morph_params.x + 0.5); }

/// The vertex's own column in the delta texture.
///
/// **`gl_VertexIndex`, spelt the way SPIR-V spells it.** GLSL ES 3.00 calls the
/// same builtin `gl_VertexID`, and the browser backend's translator rewrites
/// the name on its way out — one substitution beside the ones it already makes
/// for `#version` and `layout(std140)`. Written the other way round, impellerc
/// refuses it outright: "undeclared identifier (Did you mean gl_VertexIndex?)",
/// which is the friendliest error in this repository.
float MorphColumn() {
  return (float(gl_VertexIndex) + 0.5) * morph_info.morph_params.y;
}

/// Adds target *t*'s deltas onto one vertex, scaled by [weight].
///
/// Split out of [ApplyMorph] so that a stage which gets its weights from
/// somewhere else — `lib/morph_instanced.glsl`, where each instance of a batch
/// wears its own — reads the deltas through the same three lines rather than
/// through a second copy of them.
///
/// [column] and [rowStep] are the caller's, worked out once rather than per
/// target.
///
/// **Splitting this out moved the picture, by 31 pixels of silhouette on
/// Impeller**, and the reference set was re-recorded rather than the split
/// abandoned. The arithmetic is the same arithmetic — it was checked against
/// the software backend, which draws it identically either way — so what moved
/// is what impellerc's optimiser does with a function call it can no longer
/// see through. Hoisting the coordinates was the first guess at the cause and
/// was not it: the same 31 pixels moved with them hoisted. Worth writing down,
/// because the next person to factor a line out of a vertex stage will see a
/// golden fail and reach for the same wrong explanation.
void AddMorphTargetAt(int t, float weight, float column, float rowStep,
                      inout vec3 position, inout vec3 normal,
                      inout vec4 tangent) {
  float row = (float(t * kMorphRows) + 0.5) * rowStep;

  position += texture(morph_texture, vec2(column, row)).xyz * weight;
  normal += texture(morph_texture, vec2(column, row + rowStep)).xyz * weight;
  tangent.xyz +=
      texture(morph_texture, vec2(column, row + rowStep * 2.0)).xyz * weight;
}

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
  int count = MorphCount();
  if (count <= 0) return;

  float column = MorphColumn();
  float rowStep = morph_info.morph_params.z;

  for (int i = 0; i < kMorphMax; i++) {
    if (i >= count) break;
    float weight = morph_info.morph_weights[i / 4][i % 4];
    if (weight == 0.0) continue;
    AddMorphTargetAt(i, weight, column, rowStep, position, normal, tangent);
  }
}

#endif  // MORPH_GLSL_
