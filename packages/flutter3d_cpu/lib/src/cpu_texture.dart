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

import 'portable_log2.dart';

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

  /// The layers of a 2D array — or the cubes of a cube array, each carrying
  /// its own [faces] — with this texture as layer zero. Null for every
  /// texture that is not an array.
  ///
  /// Hung off layer zero the way [faces] hang off face zero, so that
  /// anything treating an array as a plain 2D texture reads its first layer
  /// rather than nothing, and each layer owns its own [levels].
  List<CpuTexture>? layers;

  /// The depth slices of one level of a 3D texture, with this texture as
  /// slice zero. Null for every texture that is not 3D.
  ///
  /// Per level rather than per slice, unlike [layers]: a 3D texture's chain
  /// halves the depth too, so level one of a sixteen-deep volume has eight
  /// slices, and each entry of the base's [levels] carries its own.
  List<CpuTexture>? slices;

  Float32List depthBuffer() =>
      depth ??= Float32List(width * height)..fillRange(0, width * height, 1.0);

  /// The stencil, a byte per pixel beside [depth]. Allocated on first use for
  /// the same reason the depth is: it belongs to the one texture per frame
  /// that is a depth attachment, and to none of the others.
  ///
  /// Eight bits, which is what every stencil format the engine names holds,
  /// and a `Uint8List` masks a stored value to that width by itself — which
  /// is the wrap the two wrapping operations want and the clamp the two
  /// clamping ones have to add.
  Uint8List? stencil;

  Uint8List stencilBuffer() => stencil ??= Uint8List(width * height);

  /// The array a pass named through `ColorTarget.face` and
  /// `ColorTarget.mipLevel`: [face] of a cube, then [mipLevel] down its chain.
  ///
  /// The counterpart of `BoundTexture.sampleCube`'s addressing on the writing
  /// side, and it walks the same structure — a cube is its faces and a level
  /// hangs off the face that owns it — so a face rendered here is the face the
  /// sampler reads. A 2D texture ignores [face], as the interface says it may;
  /// a level the texture does not have is a caller mistake and throws, which
  /// is what the other two backends do with an attachment out of range.
  ///
  /// [layer] picks the layer of an array or the cube of a cube array before
  /// either, as `ColorTarget.layer` does; on a 3D texture it is the slice of
  /// level [mipLevel] instead, the level chosen first.
  CpuTexture subresource({int face = 0, int mipLevel = 0, int layer = 0}) {
    if (slices != null) return plane(mipLevel: mipLevel, z: layer);
    final owner = layer == 0 ? this : _layer(layer);
    final base = owner.faces?[face] ?? owner;
    return base._level(mipLevel);
  }

  /// The plane a `TextureRegion.z` or `TextureCopyLocation.z` names: the
  /// layer of an array, the face of a cube, `layer × 6 + face` of a cube
  /// array, or the slice of a 3D texture — at level [mipLevel].
  CpuTexture plane({int mipLevel = 0, int z = 0}) {
    if (slices != null) {
      final level = _level(mipLevel);
      final atLevel = level.slices ?? <CpuTexture>[level];
      if (z < 0 || z >= atLevel.length) {
        throw RangeError('slice $z of a level ${atLevel.length} deep');
      }
      return atLevel[z];
    }
    final perLayer = faces == null ? 1 : 6;
    return subresource(
      face: z % perLayer,
      layer: z ~/ perLayer,
      mipLevel: mipLevel,
    );
  }

  /// How many planes [plane] can address at level [mipLevel].
  int planeCount([int mipLevel = 0]) {
    if (slices != null) return _level(mipLevel).slices?.length ?? 1;
    return (layers?.length ?? 1) * (faces == null ? 1 : 6);
  }

  CpuTexture _layer(int layer) {
    final all = layers;
    if (all == null || layer < 0 || layer >= all.length) {
      throw RangeError(
        'layer $layer of a texture with ${all?.length ?? 1} layer(s)',
      );
    }
    return all[layer];
  }

  CpuTexture _level(int mipLevel) {
    if (mipLevel == 0) return this;
    final chain = levels;
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
/// `SamplerDescriptor.linearRepeat` is documented as the default for material
/// textures. It cost about a percent and a half of every textured golden, and
/// it did not look like a sampler bug in the picture — it looked like the
/// checkerboard was very slightly the wrong size.
final class BoundTexture {
  const BoundTexture(this.texture, this.sampler);

  final CpuTexture texture;
  final SamplerDescriptor sampler;

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
        SamplerDescriptor.linearClamp,
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
        SamplerDescriptor.linearClamp,
      )._sampleLevel(cube[face], u, v);
    }
    final bound = BoundTexture(cube[face], SamplerDescriptor.linearClamp);
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

  /// Samples layer [layer] of a 2D array at [u], [v] — GLSL's
  /// `texture(sampler2DArray, vec3(u, v, layer))`.
  ///
  /// The layer is rounded and clamped to the array, as every API specifies;
  /// the derivatives are [sample]'s. A texture that is not an array is its
  /// own only layer.
  Vector4 sampleLayer(
    double u,
    double v,
    double layer, {
    double du = 0.0,
    double dv = 0.0,
  }) {
    final all = texture.layers;
    if (all == null) return sample(u, v, du: du, dv: dv);
    return BoundTexture(
      all[_layerIndex(layer, all.length)],
      sampler,
    ).sample(u, v, du: du, dv: dv);
  }

  /// Samples cube [layer] of a cube array in `direction` at level [lod] —
  /// `texture(samplerCubeArray, vec4(direction, layer))`. See [sampleCube].
  Vector4 sampleCubeLayer(
    double x,
    double y,
    double z,
    double layer, [
    double lod = 0.0,
  ]) {
    final all = texture.layers;
    if (all == null) return sampleCube(x, y, z, lod);
    return BoundTexture(
      all[_layerIndex(layer, all.length)],
      sampler,
    ).sampleCube(x, y, z, lod);
  }

  static int _layerIndex(double layer, int count) {
    final i = layer.round();
    return i < 0 ? 0 : (i >= count ? count - 1 : i);
  }

  /// Samples a 3D texture at ([u], [v], [w]) and level of detail [lod] —
  /// `textureLod(sampler3D, …)`.
  ///
  /// Filtered across slices by the sampler's mag filter and addressed along
  /// the depth by `SamplerDescriptor.depthAddressMode`, the third axis behaving
  /// exactly as the first two do. The level is asked for rather than derived,
  /// as [sampleCube]'s is: a volume's footprint has three axes and the
  /// rasteriser hands a stage two. A texture that is not 3D is one slice
  /// deep.
  Vector4 sample3D(double u, double v, double w, {double lod = 0.0}) {
    final chain = texture.levels;
    final clamped = _clampLod(lod);
    final top = chain?.length ?? 0;
    if (clamped <= 0.0 || top == 0) return _sampleVolume(texture, u, v, w);
    if (clamped >= top) return _sampleVolume(chain![top - 1], u, v, w);
    final lower = clamped.floor();
    final near = lower == 0 ? texture : chain![lower - 1];
    if (sampler.mipFilter == MipFilter.nearest) {
      return _sampleVolume(near, u, v, w);
    }
    return _mix(
      _sampleVolume(near, u, v, w),
      _sampleVolume(chain![lower], u, v, w),
      clamped - lower,
    );
  }

  Vector4 _sampleVolume(CpuTexture level, double u, double v, double w) {
    final planes = level.slices ?? <CpuTexture>[level];
    final depth = planes.length;
    final mode = sampler.depthAddressMode;
    final border = sampler.borderColor;
    Vector4 slice(int i) {
      if (border != null &&
          mode == SamplerAddressMode.clampToEdge &&
          (i < 0 || i >= depth)) {
        return _borderOf(border);
      }
      return _sampleLevel(planes[_address(i, depth, mode)], u, v);
    }

    if (sampler.magFilter == MinMagFilter.nearest) {
      return slice((w * depth).floor());
    }
    final z = w * depth - 0.5;
    final z0 = z.floor();
    return _mix(slice(z0), slice(z0 + 1), z - z0);
  }

  /// A comparison sample — `texture(sampler2DShadow, vec3(u, v, reference))`:
  /// the share of the footprint where `reference <compare> stored` holds,
  /// with the sampler's `SamplerDescriptor.compare` as the test.
  ///
  /// Reads the depth a pass wrote when the texture has one, and red
  /// otherwise — a depth copied into a float colour target is the same
  /// number. Linear filtering compares each of the four texels and blends
  /// the answers, which is hardware percentage-closer filtering; nearest
  /// compares one. Throws a [StateError] for a sampler that is not a
  /// comparison sampler.
  double sampleCompare(double u, double v, double reference) {
    final compare = sampler.compare;
    if (compare == null) {
      throw StateError(
        'sampleCompare through a sampler with no compare function — bind a '
        'SamplerOptions(compare: …) for a comparison sample',
      );
    }
    final width = texture.width;
    final height = texture.height;
    final depth = texture.depth;
    final border = sampler.borderColor;
    double passes(int ix, int iy) {
      final outside = ix < 0 || iy < 0 || ix >= width || iy >= height;
      final double stored;
      if (outside &&
          border != null &&
          ((ix < 0 || ix >= width) &&
                  sampler.widthAddressMode == SamplerAddressMode.clampToEdge ||
              (iy < 0 || iy >= height) &&
                  sampler.heightAddressMode ==
                      SamplerAddressMode.clampToEdge)) {
        stored = _borderOf(border).x;
      } else {
        final x = _address(ix, width, sampler.widthAddressMode);
        final y = _address(iy, height, sampler.heightAddressMode);
        stored = depth != null
            ? depth[y * width + x]
            : texture.pixels[(y * width + x) * 4];
      }
      return _compares(compare, reference, stored) ? 1.0 : 0.0;
    }

    if (sampler.magFilter == MinMagFilter.nearest) {
      return passes((u * width).floor(), (v * height).floor());
    }
    final x = u * width - 0.5;
    final y = v * height - 0.5;
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    return (passes(x0, y0) * (1 - fx) + passes(x0 + 1, y0) * fx) * (1 - fy) +
        (passes(x0, y0 + 1) * (1 - fx) + passes(x0 + 1, y0 + 1) * fx) * fy;
  }

  static bool _compares(CompareFunction f, double reference, double stored) =>
      switch (f) {
        CompareFunction.never => false,
        CompareFunction.always => true,
        CompareFunction.less => reference < stored,
        CompareFunction.lessEqual => reference <= stored,
        CompareFunction.greater => reference > stored,
        CompareFunction.greaterEqual => reference >= stored,
        CompareFunction.equal => reference == stored,
        CompareFunction.notEqual => reference != stored,
      };

  static Vector4 _borderOf(SamplerBorderColor color) => switch (color) {
    SamplerBorderColor.transparentBlack => Vector4.zero(),
    SamplerBorderColor.opaqueBlack => Vector4(0, 0, 0, 1),
    SamplerBorderColor.opaqueWhite => Vector4(1, 1, 1, 1),
  };

  static Vector4 _mix(Vector4 a, Vector4 b, double t) => Vector4(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
    a.w + (b.w - a.w) * t,
  );

  /// Whether the sampler narrows the levels it may read.
  bool get _clampsLod =>
      sampler.lodMinClamp != 0.0 || sampler.lodMaxClamp != 32.0;

  double _clampLod(double lod) {
    if (lod < sampler.lodMinClamp) return sampler.lodMinClamp;
    if (lod > sampler.lodMaxClamp) return sampler.lodMaxClamp;
    return lod;
  }

  /// [sample] for a sampler with a level-of-detail clamp: the level the
  /// footprint asks for, held inside `lodMinClamp..lodMaxClamp`.
  ///
  /// One tap, at the clamped level: a sampler that narrows its levels and
  /// also asks for anisotropy gets the clamp and not the taps, since the
  /// taps exist to choose a sharper level than the footprint and the clamp
  /// exists to forbid exactly that choice.
  Vector4 _sampleClamped(double u, double v, double du, double dv) {
    final chain = texture.levels;
    final footprint = math.max(du * width, dv * height);
    final wanted = du == 0.0 && dv == 0.0 || footprint <= 1.0
        ? 0.0
        : portableLog2(footprint);
    final lod = _clampLod(wanted);
    final top = chain?.length ?? 0;
    if (lod <= 0.0 || top == 0) return _sampleLevel(texture, u, v);
    if (lod >= top) return _sampleLevel(chain![top - 1], u, v);
    final lower = lod.floor();
    final near = lower == 0 ? texture : chain![lower - 1];
    if (sampler.mipFilter == MipFilter.nearest) return _sampleLevel(near, u, v);
    return _mix(
      _sampleLevel(near, u, v),
      _sampleLevel(chain![lower], u, v),
      lod - lower,
    );
  }

  /// [_sampleLevel] for a sampler with a border colour: every tap that
  /// falls outside the texture along a clamped axis reads the border
  /// instead of the edge texel.
  Vector4 _sampleBordered(CpuTexture level, double u, double v) {
    final width = level.width;
    final height = level.height;
    final border = _borderOf(sampler.borderColor!);
    final clampU = sampler.widthAddressMode == SamplerAddressMode.clampToEdge;
    final clampV = sampler.heightAddressMode == SamplerAddressMode.clampToEdge;
    Vector4 tap(int ix, int iy) {
      if (clampU && (ix < 0 || ix >= width)) return border;
      if (clampV && (iy < 0 || iy >= height)) return border;
      return level._texel(
        _address(ix, width, sampler.widthAddressMode),
        _address(iy, height, sampler.heightAddressMode),
      );
    }

    if (sampler.magFilter == MinMagFilter.nearest) {
      return tap((u * width).floor(), (v * height).floor());
    }
    final x = u * width - 0.5;
    final y = v * height - 0.5;
    final x0 = x.floor();
    final y0 = y.floor();
    return _mix(
      _mix(tap(x0, y0), tap(x0 + 1, y0), x - x0),
      _mix(tap(x0, y0 + 1), tap(x0 + 1, y0 + 1), x - x0),
      y - y0,
    );
  }

  /// One texel address, wrapped, mirrored or clamped as the sampler says.
  ///
  /// The clamp is spelled out rather than `int.clamp`, which is a call with
  /// argument checks on every tap of every sample.
  int _address(int i, int size, SamplerAddressMode mode) => switch (mode) {
    SamplerAddressMode.repeat => i % size < 0 ? i % size + size : i % size,
    SamplerAddressMode.clampToEdge => i < 0 ? 0 : (i >= size ? size - 1 : i),
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
  Vector4 sample(
    double u,
    double v, {
    double du = 0.0,
    double dv = 0.0,
    double dudx = 0.0,
    double dvdx = 0.0,
    double dudy = 0.0,
    double dvdy = 0.0,
  }) {
    if (_clampsLod) return _sampleClamped(u, v, du, dv);
    final chain = texture.levels;
    if (chain == null || chain.isEmpty || (du == 0.0 && dv == 0.0)) {
      return _sampleLevel(texture, u, v);
    }

    // The footprint in texels: how much of the texture one pixel covers. A
    // level is chosen so that footprint is about one texel, which is the whole
    // of what a mip chain is for.
    final along = du * width;
    final across = dv * height;
    final footprint = math.max(along, across);
    if (footprint <= 1.0) return _sampleLevel(texture, u, v);

    // **Anisotropy — `gfx-02n`.** A trilinear sampler has one footprint and
    // must pick a level for it, so at a grazing angle it serves the long axis
    // and blurs the short one: a floor receding to the horizon loses its
    // checks long before perspective would. The fix the hardware has always
    // had is to take several taps *along* the long axis and choose the level
    // from the short one.
    //
    // **A sampler that did not ask is untouched**, which is what makes this
    // safe to add to a backend 96 golden scenes are recorded on: with
    // `anisotropy` at one — the default everywhere in this engine — the
    // arithmetic below is not reached and the bytes are the ones that were
    // recorded. `anisotropic-floor` is the one scene that asks.
    final int wanted = sampler.anisotropy;
    if (wanted > 1 && (dudx != 0.0 || dvdy != 0.0 || dudy != 0.0)) {
      // **The two screen derivatives as vectors, not their axis maxima.** The
      // footprint is the parallelogram they span; what a mip level cannot
      // serve is its *ratio*, and `du`/`dv` have already thrown that away by
      // taking a maximum per axis. The first version of this read them and
      // measured a ratio of about one on a floor receding to the horizon —
      // zero differing pixels, and the fixture said so.
      final double lx = math.sqrt(
        dudx * width * dudx * width + dvdx * height * dvdx * height,
      );
      final double ly = math.sqrt(
        dudy * width * dudy * width + dvdy * height * dvdy * height,
      );
      final double major = math.max(lx, ly);
      final double minor = math.min(lx, ly);
      if (minor > 0.0 && major > 1.0) {
        final int taps = math.min(wanted, math.max(1, (major / minor).round()));
        if (taps > 1) {
          return _anisotropic(
            u,
            v,
            lx >= ly ? dudx : dudy,
            lx >= ly ? dvdx : dvdy,
            minor,
            taps,
          );
        }
      }
    }

    final lod = portableLog2(footprint);
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

  /// [taps] samples spread along the long axis of the footprint, each at the
  /// level the *short* axis asks for.
  ///
  /// The taps are placed symmetrically about the centre and averaged flat,
  /// which is what a box filter along the axis is. Hardware weights them —
  /// the exact weighting is a vendor's own and is not written down anywhere —
  /// so this will not match a GPU texel for texel and is not meant to: what
  /// it matches is the *behaviour*, which is that the checks survive.
  /// [taps] samples spread along the long axis of the footprint, each at the
  /// level the *short* axis asks for.
  ///
  /// [stepU] and [stepV] are the long axis as a step in texture coordinates —
  /// one whole screen pixel's worth — and [minor] is the short axis in
  /// texels, which is the level every tap is taken at. The taps are placed
  /// symmetrically about the centre and averaged flat, which is a box filter
  /// along the axis. Hardware weights them, and the weighting is a vendor's
  /// own and written down nowhere, so this will not match a GPU texel for
  /// texel and is not meant to: what it matches is the behaviour, which is
  /// that the checks survive.
  Vector4 _anisotropic(
    double u,
    double v,
    double stepU,
    double stepV,
    double minor,
    int taps,
  ) {
    // The level the short axis wants, expressed the way `_trilinear` reads
    // it: a per-pixel derivative whose footprint in texels is `minor`.
    final double lodU = minor / width;
    final double lodV = minor / height;

    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var a = 0.0;
    for (var i = 0; i < taps; i++) {
      // Centres of `taps` equal slices across the footprint: -½ + (i + ½)/n.
      final double t = (i + 0.5) / taps - 0.5;
      final Vector4 tap = _trilinear(u + stepU * t, v + stepV * t, lodU, lodV);
      r += tap.x;
      g += tap.y;
      b += tap.z;
      a += tap.w;
    }
    return Vector4(r / taps, g / taps, b / taps, a / taps);
  }

  /// One trilinear sample — the path [sample] takes when nothing asks for
  /// anisotropy, factored out so the taps above can reuse it without
  /// recursing back into the anisotropy check.
  Vector4 _trilinear(double u, double v, double du, double dv) {
    final chain = texture.levels;
    if (chain == null || chain.isEmpty) return _sampleLevel(texture, u, v);

    final footprint = math.max(du * width, dv * height);
    if (footprint <= 1.0) return _sampleLevel(texture, u, v);

    final lod = portableLog2(footprint);
    final top = chain.length;
    if (lod >= top) return _sampleLevel(chain[top - 1], u, v);

    final lower = lod.floor();
    final near = lower == 0 ? texture : chain[lower - 1];
    if (sampler.mipFilter == MipFilter.nearest) return _sampleLevel(near, u, v);

    final far = chain[lower];
    final t = lod - lower;
    final first = _sampleLevel(near, u, v);
    final second = _sampleLevel(far, u, v);
    return Vector4(
      first.x + (second.x - first.x) * t,
      first.y + (second.y - first.y) * t,
      first.z + (second.z - first.z) * t,
      first.w + (second.w - first.w) * t,
    );
  }

  Vector4 _sampleLevel(CpuTexture texture, double u, double v) {
    if (sampler.borderColor != null) return _sampleBordered(texture, u, v);
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

    // The bilinear blend of the four texels, written out a channel at a time
    // instead of as `Vector4` arithmetic, which allocated thirteen vectors per
    // tap. **Every intermediate goes through a `float` all the same**: each
    // `Vector4` operation the previous form made stored its result in the
    // vector's `Float32List`, rounding it, and the goldens were recorded with
    // those roundings in them. [_lane] is the same store, so each product and
    // each sum below is rounded exactly where it was.
    final pixels = texture.pixels;
    final i00 = (ay0 * width + ax0) * 4;
    final i10 = (ay0 * width + ax1) * 4;
    final i01 = (ay1 * width + ax0) * 4;
    final i11 = (ay1 * width + ax1) * 4;
    final gx = 1 - fx;
    final gy = 1 - fy;
    final lane = _lane;
    final result = Vector4.zero();
    final out = result.storage;
    for (var c = 0; c < 4; c++) {
      lane[0] = pixels[i00 + c] * gx;
      lane[1] = pixels[i10 + c] * fx;
      lane[0] = lane[0] + lane[1];
      lane[2] = pixels[i01 + c] * gx;
      lane[3] = pixels[i11 + c] * fx;
      lane[2] = lane[2] + lane[3];
      lane[0] = lane[0] * gy;
      lane[2] = lane[2] * fy;
      out[c] = lane[0] + lane[2];
    }
    return result;
  }

  /// Scratch `float`s for [_sampleLevel]'s intermediates: writing a double
  /// here and reading it back rounds it the way a `Vector4` lane does.
  static final Float32List _lane = Float32List(4);
}
