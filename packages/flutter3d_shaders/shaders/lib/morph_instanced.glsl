// Morph weights per instance of a batch, read from a texture by instance id.
//
// ## Why this is a file of its own
//
// One batch of a thousand villagers should be able to wear a thousand
// expressions, and until this existed it wore one: `MorphInfo.morph_weights` is
// a uniform, and a uniform is the same for every instance in the draw by
// definition.
//
// The obvious place to put per-instance weights is the instance record — slot
// one, which already carries a transform and a colour and is rewritten every
// frame. That was rejected: the record's size is part of the instanced vertex
// layout, so eight more floats would be paid by every instanced draw in every
// game, including the overwhelming majority that morph nothing.
//
// So: a texture, one row per instance, read by `gl_InstanceIndex`. Two texels
// wide, because eight weights are two `vec4`s. It costs one sampler on one
// stage, and the layout is untouched.
//
// **This is included only by `mesh_instanced.vert`.** A sampler declared in
// `lib/morph.glsl` would be declared on all four mesh vertex stages, and every
// one of them would have to bind something to it on every draw for ever. The
// deltas are worth that; a second sampler that three stages can never use is
// not.
//
// ## What it costs to change a weight
//
// A texture in this engine is created with its contents and never written
// again — `GraphicsDevice` has `createTextureFromPixels` and no update, which
// is a decision the HAL makes on purpose. So a batch whose per-instance weights
// change has to build a new texture, and one whose weights are set once pays
// nothing per frame. That is the right way round for what this is for: a crowd
// where each face is *different* rather than a crowd where each face is
// *moving*. `InstancedMeshNode` rebuilds only when a weight actually changed —
// the same skip `MorphBlend` makes, and for the same reason.

#ifndef MORPH_INSTANCED_GLSL_
#define MORPH_INSTANCED_GLSL_

#include <lib/morph.glsl>

uniform sampler2D morph_instance_weights;

uniform MorphInstanceInfo {
  /// x: 1 when the weights come from the texture, 0 when they come from
  ///    `MorphInfo` and every instance wears the same shape.
  /// y: one texel across, `1 / width`. z: one texel down, `1 / height`.
  /// w unused.
  vec4 instance_params;
}
morph_instance_info;

/// Adds the deltas for [instance]'s own weights onto one vertex.
///
/// Falls through to [ApplyMorph] when the batch has no per-instance weights,
/// which is every batch that does not use this feature: the texture is then a
/// stand-in nobody reads, and the shape comes from the uniform exactly as it
/// does on the three stages that never heard of this file.
void ApplyMorphInstanced(int instance, inout vec3 position, inout vec3 normal,
                         inout vec4 tangent) {
  if (morph_instance_info.instance_params.x < 0.5) {
    ApplyMorph(position, normal, tangent);
    return;
  }

  int count = MorphCount();
  if (count <= 0) return;

  float deltaColumn = MorphColumn();
  float deltaRowStep = morph_info.morph_params.z;

  // The instance's own row, at a texel centre, for the same reason the delta
  // read builds its coordinate by hand: nearest and clamped, and no
  // `textureSize`.
  float row = (float(instance) + 0.5) * morph_instance_info.instance_params.z;

  for (int i = 0; i < kMorphMax; i++) {
    if (i >= count) break;
    // Four weights a texel, so target *i* is in texel `i / 4`, channel `i % 4`
    // — the same arithmetic `morph_weights[i / 4][i % 4]` does over the
    // uniform, which is what makes the two paths agree without either knowing
    // about the other.
    float column =
        (float(i / 4) + 0.5) * morph_instance_info.instance_params.y;
    float weight = texture(morph_instance_weights, vec2(column, row))[i % 4];
    if (weight == 0.0) continue;
    AddMorphTargetAt(i, weight, deltaColumn, deltaRowStep, position, normal,
                     tangent);
  }
}

#endif  // MORPH_INSTANCED_GLSL_
