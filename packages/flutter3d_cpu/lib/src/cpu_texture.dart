/// A texture as this backend holds one, and sampling it.
///
/// [CpuTexture] and [BoundTexture] stay in one file rather than two: a bound
/// texture's sampling reads a texture's texels directly, by the same private
/// accessor whichever level or cube face it is reading from, and splitting the
/// pair would mean making that accessor public for no reader outside this
/// file.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

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

  /// The six faces of a cube, in the order the graphics interface documents:
  /// **+X, −X, +Y, −Y, +Z, −Z**. Null for every ordinary texture.
  ///
  /// Held as whole textures for the same reason [levels] is: sampling a face is
  /// then the same code as sampling anything else.
  List<CpuTexture>? faces;

  Float32List depthBuffer() =>
      depth ??= Float32List(width * height)..fillRange(0, width * height, 1.0);

  /// The array a pass named through `ColorTarget.face` and
  /// `ColorTarget.mipLevel`: [face] of a cube, then [mipLevel] down its chain.
  ///
  /// The counterpart of `BoundTexture.sampleCube`'s addressing on the writing
  /// side, and it walks the same structure — a cube is its faces and a level
  /// hangs off the face that owns it — so a face rendered here is the face the
  /// sampler reads. A 2D texture ignores [face], as the interface says it may;
  /// a level the texture does not have is a caller mistake and throws, which
  /// is what the other two backends do with an attachment out of range.
  CpuTexture subresource({int face = 0, int mipLevel = 0}) {
    final base = faces?[face] ?? this;
    if (mipLevel == 0) return base;
    final chain = base.levels;
    if (chain == null || mipLevel > chain.length) {
      throw RangeError(
        'mip level $mipLevel of a texture with '
        '${(chain?.length ?? 0) + 1} level(s)',
      );
    }
    return chain[mipLevel - 1];
  }

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

  /// Samples a cube in `direction`, which need not be normalised.
  ///
  /// The face is the one the largest component points at, and the two
  /// coordinates on it are the other two divided by that component's magnitude.
  /// The table of which axis goes where, and with which sign, is **the GL
  /// specification's** and is written out rather than derived: one wrong sign
  /// mirrors a face, and a mirrored face is a sky that is complete, seamless
  /// and wrong. `flutter3d_conformance` draws six known directions against six
  /// known colours precisely because nothing in a picture says which.
  ///
  /// Edges are clamped rather than filtered across the seam. Metal and WebGL2
  /// both filter across it, so at a face boundary this backend blends two
  /// copies of the edge texel where they reach into the neighbour. On a smooth
  /// sky the difference is far below the cross-backend tolerance; on a detailed
  /// one it would not be, and the fix — rebuilding the direction for each of
  /// the four half-texel offsets — costs four times a tap and is not worth
  /// building before something measures it.
  Vector4 sampleCube(double x, double y, double z, [double lod = 0.0]) {
    final cube = texture.faces;
    if (cube == null || cube.length != 6) {
      // A 2D texture asked for a direction: sample it as though the direction
      // were a coordinate rather than returning nothing, so a misconfigured
      // bind is visible as a wrong picture rather than as a black one.
      return sample(x, y);
    }

    final ax = x.abs();
    final ay = y.abs();
    final az = z.abs();

    final int face;
    final double sc;
    final double tc;
    final double ma;
    if (ax >= ay && ax >= az) {
      ma = ax;
      if (x > 0.0) {
        face = 0; // +X
        sc = -z;
        tc = -y;
      } else {
        face = 1; // -X
        sc = z;
        tc = -y;
      }
    } else if (ay >= az) {
      ma = ay;
      if (y > 0.0) {
        face = 2; // +Y
        sc = x;
        tc = z;
      } else {
        face = 3; // -Y
        sc = x;
        tc = -z;
      }
    } else {
      ma = az;
      if (z > 0.0) {
        face = 4; // +Z
        sc = x;
        tc = -y;
      } else {
        face = 5; // -Z
        sc = -x;
        tc = -y;
      }
    }

    if (ma <= 0.0) return Vector4.zero();
    final u = (sc / ma + 1.0) * 0.5;
    final v = (tc / ma + 1.0) * 0.5;
    if (lod <= 0.0) {
      return BoundTexture(
        cube[face],
        SamplerOptions.linearClamp,
      )._sampleLevel(cube[face], u, v);
    }

    // **The level is asked for, not derived.** Everywhere else in this file a
    // mip is chosen from how fast the coordinate moves; a prefiltered
    // environment is the one case where the level *is* the parameter — it is the
    // roughness — and deriving it from screen derivatives would give a mirror
    // and a matte wall the same reflection whenever they were the same size on
    // screen. `textureLod` is what the GLSL side calls, and this is its twin.
    final chain = cube[face].levels;
    if (chain == null || chain.isEmpty) {
      return BoundTexture(
        cube[face],
        SamplerOptions.linearClamp,
      )._sampleLevel(cube[face], u, v);
    }
    final bound = BoundTexture(cube[face], SamplerOptions.linearClamp);
    final top = chain.length;
    if (lod >= top) return bound._sampleLevel(chain[top - 1], u, v);
    final lower = lod.floor();
    final near = lower == 0 ? cube[face] : chain[lower - 1];
    final far = chain[lower];
    final a = bound._sampleLevel(near, u, v);
    final b = bound._sampleLevel(far, u, v);
    final t = lod - lower;
    return Vector4(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
      a.w + (b.w - a.w) * t,
    );
  }

  /// One texel address, wrapped, mirrored or clamped as the sampler says.
  int _address(int i, int size, SamplerAddressMode mode) => switch (mode) {
    SamplerAddressMode.repeat => i % size < 0 ? i % size + size : i % size,
    SamplerAddressMode.clampToEdge => i.clamp(0, size - 1),
    SamplerAddressMode.mirror => _mirror(i, size),
  };

  /// One texel address under [SamplerAddressMode.mirror].
  ///
  /// The period is two widths: the first walks the texture forwards and the
  /// second walks it back, so a boundary lands on two copies of one texel
  /// rather than on a jump from the last to the first.
  ///
  /// This is reached from ordinary assets rather than from a setting somebody
  /// went looking for — glTF's `MIRRORED_REPEAT` maps straight onto it — and
  /// the other two backends have always honoured it. Refusing here threw out
  /// of the inner rasteriser loop, which meant a model that drew on hardware
  /// took the frame down on the backend the tests, the golden set and the
  /// software fallback all run.
  static int _mirror(int i, int size) {
    final period = size * 2;
    var m = i % period;
    if (m < 0) m += period;
    return m < size ? m : period - 1 - m;
  }

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

    final top =
        texture._texel(ax0, ay0) * (1 - fx) + texture._texel(ax1, ay0) * fx;
    final bottom =
        texture._texel(ax0, ay1) * (1 - fx) + texture._texel(ax1, ay1) * fx;
    return top * (1 - fy) + bottom * fy;
  }
}
