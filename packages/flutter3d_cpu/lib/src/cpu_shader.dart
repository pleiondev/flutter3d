/// What a shader is on a backend with no shading language.
///
/// The engine asks a library for entry points by name — `MeshVertex`, `Pbr`,
/// `Composite` — and nothing in `flutter3d_graphics` says those names have to
/// resolve to GLSL. `PipelineHandle.backend` is an `Object`. So here they
/// resolve to Dart, and whether that was ever really allowed is the question
/// this whole package exists to answer.
library;

import 'dart:math' as math;
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

  /// The smaller copies, from half size down. Null for almost every texture.
  ///
  /// Held as whole textures rather than as loose byte lists so that sampling a
  /// level is the same code as sampling the base — a second addressing path
  /// for the small levels is a second place for the half-texel offset to be
  /// wrong, and that one is invisible when it is.
  List<CpuTexture>? levels;

  Float32List depthBuffer() =>
      depth ??= Float32List(width * height)..fillRange(0, width * height, 1.0);

  Vector4 _texel(int px, int py) {
    final i = (py * width + px) * 4;
    return Vector4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
  }
}

/// A texture with the sampler it was bound with.
///
/// The pair, not the texture alone, because a texture has no filtering or
/// wrapping of its own — those come from the bind, and the same image is
/// sampled differently by two shaders in the same frame.
///
/// The first version of this backend ignored the sampler entirely and always
/// filtered bilinearly with clamped edges, on the strength of a comment saying
/// every sampler the engine binds is clamped. That comment was wrong:
/// `SamplerOptions.linearRepeat` is documented as the default for material
/// textures. It cost about a percent and a half of every textured golden, and
/// it did not look like a sampler bug in the picture — it looked like the
/// checkerboard was very slightly the wrong size.
final class BoundTexture {
  const BoundTexture(this.texture, this.sampler);

  final CpuTexture texture;
  final SamplerOptions sampler;

  int get width => texture.width;
  int get height => texture.height;
  Float32List get pixels => texture.pixels;

  /// One texel address, wrapped or clamped as the sampler says.
  int _address(int i, int size, SamplerAddressMode mode) => switch (mode) {
        SamplerAddressMode.repeat => i % size < 0 ? i % size + size : i % size,
        SamplerAddressMode.clampToEdge => i.clamp(0, size - 1),
        // Mirror is in the enum and nothing binds it. Refusing beats guessing:
        // a wrong wrap looks like a texture that is subtly the wrong way round
        // in one place, which is not something anybody goes looking for.
        SamplerAddressMode.mirror => throw UnsupportedError(
            'SamplerAddressMode.mirror is not implemented by this backend'),
      };

  /// Samples at [u], [v].
  ///
  /// The half-texel offset is the part that is easy to get wrong and invisible
  /// when it is: a texture coordinate addresses texel *centres*, so `u = 0`
  /// falls on the centre of texel zero and the conversion is `u * size - 0.5`.
  /// Scaling by `size - 1` instead — which reads just as plausibly — stretches
  /// the image by half a texel at each edge and shifts every sample. On a
  /// checkerboard that is a visible seam offset; on a photograph it is
  /// nothing, which is why it survives.
  /// Samples at [u], [v], choosing a mip level from how fast the coordinate is
  /// moving.
  ///
  /// [du] and [dv] are the change in the coordinate per screen pixel — the
  /// derivatives a hardware rasteriser computes from a quad of neighbouring
  /// fragments and this one derives per triangle. Zero means "no idea", which
  /// selects the base level and is what every call that predates mip chains
  /// passes.
  ///
  /// **The shader supplies them, because only the shader knows which varyings
  /// are a texture coordinate.** This rasteriser interpolates a list of floats;
  /// nothing in it can tell a UV from a world position. That is a real
  /// difference from the hardware backends, where the derivative is a property
  /// of the fragment rather than of the call, and it is why this is a
  /// parameter rather than something read off the context.
  Vector4 sample(double u, double v, {double du = 0.0, double dv = 0.0}) {
    final chain = texture.levels;
    if (chain == null || chain.isEmpty || (du == 0.0 && dv == 0.0)) {
      return _sampleLevel(texture, u, v);
    }

    // The footprint in texels: how much of the texture one pixel covers. A
    // level is chosen so that footprint is about one texel, which is the whole
    // of what a mip chain is for.
    final footprint = math.max(du * width, dv * height);
    if (footprint <= 1.0) return _sampleLevel(texture, u, v);

    final lod = math.log(footprint) / math.ln2;
    final top = chain.length;
    if (lod >= top) return _sampleLevel(chain[top - 1], u, v);

    final lower = lod.floor();
    final near = lower == 0 ? texture : chain[lower - 1];
    if (sampler.mipFilter == MipFilter.nearest) return _sampleLevel(near, u, v);

    final far = chain[lower];
    final t = lod - lower;
    final a = _sampleLevel(near, u, v);
    final b = _sampleLevel(far, u, v);
    return Vector4(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
      a.w + (b.w - a.w) * t,
    );
  }

  Vector4 _sampleLevel(CpuTexture texture, double u, double v) {
    final width = texture.width;
    final height = texture.height;
    final x = u * width - 0.5;
    final y = v * height - 0.5;
    final x0 = x.floor();
    final y0 = y.floor();

    if (sampler.magFilter == MinMagFilter.nearest) {
      // Nearest rounds to the containing texel, which is the floor of the
      // unshifted coordinate rather than of the shifted one.
      return texture._texel(
        _address((u * width).floor(), width, sampler.widthAddressMode),
        _address((v * height).floor(), height, sampler.heightAddressMode),
      );
    }

    final fx = x - x0;
    final fy = y - y0;
    final ax0 = _address(x0, width, sampler.widthAddressMode);
    final ax1 = _address(x0 + 1, width, sampler.widthAddressMode);
    final ay0 = _address(y0, height, sampler.heightAddressMode);
    final ay1 = _address(y0 + 1, height, sampler.heightAddressMode);

    final top = texture._texel(ax0, ay0) * (1 - fx) +
        texture._texel(ax1, ay0) * fx;
    final bottom = texture._texel(ax0, ay1) * (1 - fx) +
        texture._texel(ax1, ay1) * fx;
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

/// Everything a fragment stage gets that is not a varying or a binding.
///
/// One object rather than more parameters, because both of the things on it are
/// per-fragment state that GLSL provides as globals — and because a stage that
/// grows a third one should not change the signature of the twenty-three that
/// did not.
final class FragmentContext {
  FragmentContext();

  /// `gl_FragCoord`: window x and y, window depth in z, and `1/w` in w.
  ///
  /// The depth is what the shadow pass stores, so this is not a diagnostic —
  /// leaving it out means `ShadowDepth` cannot be written at all.
  final Vector4 coord = Vector4.zero();

  /// How fast each varying moves across the screen, per pixel.
  ///
  /// Filled once per triangle, and only when something bound to the pass has a
  /// mip chain — the arithmetic is cheap but it is not free, and almost no draw
  /// in this engine needs it.
  ///
  /// **Constant across the triangle, where hardware computes it per fragment.**
  /// A GPU differences a quad of neighbouring fragments, so its answer follows
  /// the perspective; this is the affine gradient of the varying in window
  /// space, which is the same thing only for a triangle facing the camera. The
  /// difference is a fraction of a level of detail, and a level is a power of
  /// two — so it changes which mip is picked only for a surface seen at a sharp
  /// angle, and by one level when it does.
  Float32List? ddx;
  Float32List? ddy;

  /// What the stage wrote to attachment one, or null if it wrote nothing.
  ///
  /// The engine's lit models write the surface buffer from the same call that
  /// writes colour, so a surface cannot be lit into the frame without also
  /// describing itself. A stage that declares `F3D_NO_SURFACE_BUFFER` — the
  /// shadow passes — leaves this alone, and the device then writes nothing,
  /// which is the same thing a pass with one attachment does.
  Vector4? surface;
}

/// Turns interpolated varyings into a colour.
abstract interface class CpuFragmentShader {
  /// Returns linear RGBA for attachment zero. Null discards the fragment.
  Vector4? run(
      Float32List varyings, ShaderBindings bindings, FragmentContext context);
}

/// A stage, which is one or the other.
final class CpuStage {
  const CpuStage.vertex(this.vertex) : fragment = null;
  const CpuStage.fragment(this.fragment) : vertex = null;

  final CpuVertexShader? vertex;
  final CpuFragmentShader? fragment;
}
