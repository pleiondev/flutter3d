/// `lib/morph.glsl`, transcribed: a vertex moved towards the shapes its mesh
/// carries.
///
/// **Read against the GLSL and not against `MorphBlend`**, which is the same
/// arithmetic on the host. A transcription of a transcription is one drift
/// further from the thing it stands for, and this backend is the oracle the
/// cross-backend comparison rests on.
///
/// The delta texture is one column a vertex and three rows a target —
/// positions, normals, tangents — and the sampler is nearest and clamped, so
/// reading a texel centre and reading the texel are the same thing. The GLSL
/// builds that centre by hand because impellerc crashes on `texelFetch` in a
/// vertex stage; here there is no such compiler, and the arithmetic is
/// reproduced anyway. Anything else would be this backend agreeing with the
/// engine and disagreeing with the two that draw the picture.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// Rows one target occupies. `kMorphRows` in the GLSL, `rowsPerTarget` on the
/// host, and all three have to move together.
const int kMorphRows = 3;

/// The most targets one draw blends. `kMorphMax` in the GLSL.
const int kMorphMax = 8;

/// Adds the blended deltas onto one vertex, in place.
///
/// [position], [normal] and [tangent] are the attributes as they were read.
/// The tangent's w is left alone: it is a handedness rather than a direction,
/// and glTF does not morph it.
void applyMorph(
  int vertexIndex,
  ShaderBindings bindings,
  Vector3 position,
  Vector3 normal,
  Vector4 tangent,
) {
  final count = _targetCount(bindings);
  if (count <= 0) return;

  final limit = count < kMorphMax ? count : kMorphMax;
  for (var i = 0; i < limit; i++) {
    final weight = _weightAt(bindings, i);
    if (weight == 0.0) continue;
    addMorphTarget(i, weight, vertexIndex, bindings, position, normal, tangent);
  }
}

/// How many targets this draw blends. `MorphCount()` in the GLSL.
int _targetCount(ShaderBindings bindings) {
  final params = bindings.vec4('MorphInfo', 'morph_params', Vector4.zero());
  return (params.x + 0.5).floor();
}

/// Adds target [t]'s deltas onto one vertex, scaled by [weight].
///
/// `AddMorphTarget` in the GLSL, and split out here for the same reason it is
/// split out there: two callers with different ideas about where a weight comes
/// from, and one place that knows where a delta is.
void addMorphTarget(
  int t,
  double weight,
  int vertexIndex,
  ShaderBindings bindings,
  Vector3 position,
  Vector3 normal,
  Vector4 tangent,
) {
  final texture = bindings.textures['morph_texture'];
  if (texture == null) return;

  final params = bindings.vec4('MorphInfo', 'morph_params', Vector4.zero());
  final columnStep = params.y;
  final rowStep = params.z;
  if (columnStep <= 0.0 || rowStep <= 0.0) return;

  final column = (vertexIndex + 0.5) * columnStep;
  final row = (t * kMorphRows + 0.5) * rowStep;

  final dp = texture.sample(column, row);
  position.setValues(
    position.x + dp.x * weight,
    position.y + dp.y * weight,
    position.z + dp.z * weight,
  );

  final dn = texture.sample(column, row + rowStep);
  normal.setValues(
    normal.x + dn.x * weight,
    normal.y + dn.y * weight,
    normal.z + dn.z * weight,
  );

  final dt = texture.sample(column, row + rowStep * 2.0);
  tangent.setValues(
    tangent.x + dt.x * weight,
    tangent.y + dt.y * weight,
    tangent.z + dt.z * weight,
    tangent.w,
  );
}

/// Weight *i*, out of the `vec4[2]` the block declares.
///
/// The GLSL indexes it as `morph_weights[i / 4][i % 4]`; the engine writes
/// eight floats in a row, which is the same bytes and the reason the two agree
/// without either knowing about the other.
double _weightAt(ShaderBindings bindings, int i) {
  final data = bindings.read('MorphInfo', 'morph_weights');
  if (data == null || i >= data.length) return 0.0;
  return data[i];
}

/// `lib/morph_instanced.glsl`, transcribed: the same blend with each instance's
/// own weights.
///
/// Reads the weights out of a texture by instance rather than out of the
/// uniform, when the batch has any. A batch that has none falls through to
/// [applyMorph], which is what the GLSL does at the same point and for the same
/// reason: the feature costs a sampler and a branch, and every batch that does
/// not use it pays only the branch.
void applyMorphInstanced(
  int vertexIndex,
  int instanceIndex,
  ShaderBindings bindings,
  Vector3 position,
  Vector3 normal,
  Vector4 tangent,
) {
  final params = bindings.vec4(
    'MorphInstanceInfo',
    'instance_params',
    Vector4.zero(),
  );
  if (params.x < 0.5) {
    applyMorph(vertexIndex, bindings, position, normal, tangent);
    return;
  }

  final weights = bindings.textures['morph_instance_weights'];
  if (weights == null) return;
  final columnStep = params.y;
  final rowStep = params.z;
  if (columnStep <= 0.0 || rowStep <= 0.0) return;

  final count = _targetCount(bindings);
  if (count <= 0) return;

  final row = (instanceIndex + 0.5) * rowStep;
  final limit = count < kMorphMax ? count : kMorphMax;
  for (var i = 0; i < limit; i++) {
    // Four weights a texel, exactly as the uniform packs them into a `vec4[2]`
    // — which is what makes an instance's face and a batch's face the same
    // arithmetic reached two ways.
    final column = (i ~/ 4 + 0.5) * columnStep;
    final texel = weights.sample(column, row);
    final weight = switch (i % 4) {
      0 => texel.x,
      1 => texel.y,
      2 => texel.z,
      _ => texel.w,
    };
    if (weight == 0.0) continue;
    addMorphTarget(i, weight, vertexIndex, bindings, position, normal, tangent);
  }
}

/// Whether this draw morphs anything, for a stage deciding whether to copy its
/// attributes before touching them.
bool morphs(ShaderBindings bindings) {
  final params = bindings.vec4('MorphInfo', 'morph_params', Vector4.zero());
  return params.x >= 0.5;
}

/// Scratch a stage reuses rather than allocating three vectors a vertex.
///
/// A vertex stage runs once per vertex per draw, so a `Vector3` made here is
/// one made hundreds of thousands of times a frame — which is the allocation
/// pattern every hot loop in this repository is written to avoid.
final class MorphScratch {
  final Vector3 position = Vector3.zero();
  final Vector3 normal = Vector3.zero();
  final Vector4 tangent = Vector4.zero();

  /// Loads the attributes at [offsets] and morphs them, returning whether
  /// anything moved. False leaves a caller reading its attributes directly.
  bool load(
    int vertexIndex,
    Float32List attributes,
    ShaderBindings bindings, {
    required int positionAt,
    required int normalAt,
    required int tangentAt,

    /// The copy being drawn, for a stage whose batch gives each instance its
    /// own weights. Negative asks for the batch-wide ones, which is every
    /// stage but the instanced one.
    int instanceIndex = -1,
  }) {
    if (!morphs(bindings)) return false;
    position.setValues(
      attributes[positionAt],
      attributes[positionAt + 1],
      attributes[positionAt + 2],
    );
    normal.setValues(
      attributes[normalAt],
      attributes[normalAt + 1],
      attributes[normalAt + 2],
    );
    tangent.setValues(
      attributes[tangentAt],
      attributes[tangentAt + 1],
      attributes[tangentAt + 2],
      attributes[tangentAt + 3],
    );
    if (instanceIndex < 0) {
      applyMorph(vertexIndex, bindings, position, normal, tangent);
    } else {
      applyMorphInstanced(
        vertexIndex,
        instanceIndex,
        bindings,
        position,
        normal,
        tangent,
      );
    }
    return true;
  }
}
