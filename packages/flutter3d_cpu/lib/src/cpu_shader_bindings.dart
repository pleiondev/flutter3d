/// The uniform blocks and textures a draw was given, by the names the shader
/// asks for.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_texture.dart';

/// A map rather than a generated struct, because the binding contract is by
/// name: the engine writes `bindUniformBlock(shader, 'FragInfo', {...})` and a
/// backend looks the members up. A Dart shader does the same lookup.
final class ShaderBindings {
  const ShaderBindings(this.blocks, this.textures);

  /// Block name to member name to floats, exactly as the engine wrote them.
  final Map<String, Map<String, Float32List>> blocks;

  /// Sampler slot name to what is bound there, with the sampler it came with.
  final Map<String, BoundTexture> textures;

  /// [member] of [block], or null if the engine did not write it.
  ///
  /// Null rather than an error: a shader here plays the part of a compiled one,
  /// and a compiled shader that reads a member nobody wrote gets zeros. Making
  /// this throw would hold Dart shaders to a stricter rule than the GLSL ones
  /// they stand in for.
  Float32List? read(String block, String member) => blocks[block]?[member];

  /// [member] of [block] as a vector, or [fallback].
  Vector4 vec4(String block, String member, Vector4 fallback, {int at = 0}) {
    final data = read(block, member);
    if (data == null || data.length < at * 4 + 4) return fallback;
    return Vector4(
      data[at * 4],
      data[at * 4 + 1],
      data[at * 4 + 2],
      data[at * 4 + 3],
    );
  }

  /// [member] of [block] as a matrix, or the identity.
  Matrix4 mat4(String block, String member, {int at = 0}) {
    final data = read(block, member);
    if (data == null || data.length < at * 16 + 16) return Matrix4.identity();
    return Matrix4.fromList(
      List<double>.generate(16, (i) => data[at * 16 + i]),
    );
  }
}
