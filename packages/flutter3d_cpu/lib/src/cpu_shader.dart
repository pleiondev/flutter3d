/// What a shader is on a backend with no shading language.
///
/// The engine asks a library for entry points by name — `MeshVertex`, `Pbr`,
/// `Composite` — and nothing in `flutter3d_graphics` says those names have to
/// resolve to GLSL. `PipelineHandle.backend` is an `Object`. So here they
/// resolve to Dart, and whether that was ever really allowed is the question
/// this whole package exists to answer.
library;

import 'dart:typed_data';

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:vector_math/vector_math.dart';

/// The uniform blocks and textures a draw was given, by the names the shader
/// asks for.
///
/// A map rather than a generated struct, because the binding contract is by
/// name: the engine writes `bindUniformBlock(shader, 'FragInfo', {...})` and a
/// backend looks the members up. A Dart shader does the same lookup.
final class ShaderBindings {
  const ShaderBindings(this.blocks, this.textures);

  /// Block name to member name to floats, exactly as the engine wrote them.
  final Map<String, Map<String, Float32List>> blocks;

  /// Sampler slot name to what is bound there.
  final Map<String, CpuTexture> textures;

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
    return Vector4(data[at * 4], data[at * 4 + 1], data[at * 4 + 2],
        data[at * 4 + 3]);
  }

  /// [member] of [block] as a matrix, or the identity.
  Matrix4 mat4(String block, String member, {int at = 0}) {
    final data = read(block, member);
    if (data == null || data.length < at * 16 + 16) return Matrix4.identity();
    return Matrix4.fromList(
        List<double>.generate(16, (i) => data[at * 16 + i]));
  }
}

/// A texture as this backend holds one: linear float RGBA, row zero at the top.
///
/// Float rather than bytes for every format, because the engine renders in
/// linear HDR and an 8-bit intermediate would clip the values it tone maps
/// from. Converted on the way out, in `readPixels`, which is the only place the
/// distinction can be observed.
final class CpuTexture {
  CpuTexture(this.width, this.height, this.format)
      : pixels = Float32List(width * height * 4);

  final int width;
  final int height;
  final TextureFormat format;

  /// RGBA per pixel, row-major from the top.
  final Float32List pixels;

  /// Depth, allocated on first use: most textures never carry one.
  Float32List? depth;

  Float32List depthBuffer() =>
      depth ??= Float32List(width * height)..fillRange(0, width * height, 1.0);

  /// Bilinear sample, clamped. Every sampler this engine binds is clamped, and
  /// a repeat mode nothing uses would be a guess about a call site.
  Vector4 sample(double u, double v) {
    final x = (u.clamp(0.0, 1.0) * (width - 1));
    final y = (v.clamp(0.0, 1.0) * (height - 1));
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final fx = x - x0;
    final fy = y - y0;

    Vector4 at(int px, int py) {
      final i = (py * width + px) * 4;
      return Vector4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
    }

    final top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx;
    final bottom = at(x0, y1) * (1 - fx) + at(x1, y1) * fx;
    return top * (1 - fy) + bottom * fy;
  }
}

/// Turns one vertex into a clip position and some varyings.
abstract interface class CpuVertexShader {
  /// How many floats of varying this stage writes, so the rasteriser knows how
  /// much to interpolate.
  int get varyingCount;

  /// Reads [attributes] — the vertex, as the engine laid it out — and writes a
  /// clip-space position plus [varyings].
  Vector4 run(Float32List attributes, ShaderBindings bindings,
      Float32List varyings);
}

/// Turns interpolated varyings into a colour.
abstract interface class CpuFragmentShader {
  /// Returns linear RGBA. Null discards the fragment.
  Vector4? run(Float32List varyings, ShaderBindings bindings);
}

/// A stage, which is one or the other.
final class CpuStage {
  const CpuStage.vertex(this.vertex) : fragment = null;
  const CpuStage.fragment(this.fragment) : vertex = null;

  final CpuVertexShader? vertex;
  final CpuFragmentShader? fragment;
}
