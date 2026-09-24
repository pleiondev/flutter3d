/// A `GraphicsDevice` with no GPU behind it.
///
/// The third implementation, and the reason for it: two backends that agree
/// prove less than they seem to when both are hardware rasterisers driven by a
/// C API. This one shares nothing with either — no driver, no shading language,
/// no command buffer — so whatever the interface still assumes about graphics
/// hardware has to show up here.
///
/// It is also useful rather than only instructive. Rendering on this backend
/// needs no device, so the engine's frames can be checked under a plain
/// `dart test` on the VM, in seconds, where the golden suite currently
/// drives an application for twelve minutes.
///
/// Split across a few files by cohesive concern, all re-exported from here:
/// [CpuShaderLibrary] and `CpuPipeline` are `cpu_shader_library.dart`;
/// [CpuEncoder] — the pass that records state and rasterises on `draw` — is
/// `cpu_encoder.dart`; and the per-vertex attribute assembly instancing needs
/// is `cpu_vertex_fetch.dart`. `CpuFrame`, the widget `presentFrame` in
/// `flutter3d_app` returns for this backend, moved there with it (mcp-02n) —
/// this package is flat, and a Flutter-facing widget file could not stay.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_encoder.dart';
import 'cpu_shader.dart';
import 'cpu_shader_library.dart';

export 'cpu_encoder.dart';
export 'cpu_shader_library.dart';
export 'cpu_vertex_fetch.dart';

/// The software backend.
final class CpuDevice implements GraphicsDevice {
  // The 0.8 cycle's half of the contract, declared in 0.8.0 and not built
  // here yet — see the end of `GraphicsDevice`. Each answer is the one that
  // makes a caller take its fallback.

  @override
  bool get supportsGpuTimestamps => false;

  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  @override
  bool get supportsCompute => false;

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
  }) => throw UnsupportedError(_noCompute);

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) =>
      throw UnsupportedError(_noCompute);

  @override
  ComputeEncoder beginComputePass({String? label}) =>
      throw UnsupportedError(_noCompute);

  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) =>
      throw UnsupportedError(_noCompute);

  @override
  void releaseStorageBuffer(StorageBuffer buffer) =>
      throw UnsupportedError(_noCompute);

  static const String _noCompute =
      'The software rasteriser runs no compute: supportsCompute is false. Ask before '
      'creating a storage buffer, a compute pipeline or a compute pass.';

  @override
  bool get supportsFloat32Filtering => false;

  @override
  bool get supportsIndependentBlend => false;

  @override
  List<TextureFormat> get hdrOutputFormats => const <TextureFormat>[];

  CpuDevice({
    required this.width,
    required this.height,
    required this.shaders,
    this.maxColorAttachments = 2,
  });

  final int width;
  final int height;

  @override
  final CpuShaderLibrary shaders;

  /// The bundle's names, answered with this device's own Dart stages; a name
  /// it has no Dart for is a refusal naming the bundle and the stage. See
  /// [CpuLoadedShaderLibrary]. Nothing is compiled, so nothing is waited for.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      CpuLoadedShaderLibrary.load(shaders, bytes);

  @override
  // The engine's own convention, and here it is a choice rather than a
  // constraint — nothing underneath has an opinion. Choosing the engine's
  // saves a matrix multiply per frame and, more to the point, means this
  // backend does not quietly become a second test of `toDepthRange`.
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  // Row zero is the top, because that is where this backend puts it. There is
  // no framebuffer here to disagree with.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32FloatS8UInt;

  @override
  // Float everywhere internally, so this costs nothing and is not a lie: the
  // values really are kept beyond one.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  // No multisampling. Answering one rather than four is the difference between
  // a backend that says what it does and one whose pictures quietly differ.
  int get preferredSampleCount => 1;

  @override
  bool get supportsOffscreenMsaa => false;

  @override
  // A field on the pass and four arms in the blend equation, which is the whole
  // of what a blend constant is when the blending is arithmetic this backend
  // does itself.
  bool get supportsBlendColor => true;

  @override
  // A byte per pixel beside the depth, tested and written the way the
  // specification says, every operation of the eight. See `CpuEncoder`.
  bool get supportsStencil => true;

  @override
  // Line *primitives* are drawn — debug geometry arrives as those. Wireframe
  // is a different request: it asks for triangles to be drawn as their edges,
  // which means clipping and joining edges this rasteriser has no path for.
  // Answering true and filling them instead would be the silent substitution
  // the contract exists to forbid.
  bool get supportsWireframe => false;

  @override
  // Both halves are here now: the chain is stored as whole textures and the
  // level is chosen from a per-triangle derivative. See `BoundTexture.sample`
  // for why the derivative is a parameter rather than a property of the
  // fragment, which is the one place this backend cannot imitate hardware.
  bool get supportsMipmaps => true;

  /// No to every block-compressed format, and that is the whole answer: this
  /// backend samples raw texels and has no decoder for a block, by design —
  /// `createTextureFromPixels` says the same by throwing when one arrives
  /// anyway. Everything else it stores as floats whatever the format says.
  @override
  bool supportsTextureFormat(TextureFormat format) => !format.isCompressed;

  @override
  // One tap along one axis from one level, chosen per triangle — see
  // `BoundTexture.sample`, which takes the taps since `gfx-02n`: a sampler
  // asking for eight gets eight, spread along the long axis of its footprint,
  // each at the level the short axis asks for. This answered one until then,
  // and `anisotropic-floor` is the scene whose cross-backend budget was the
  // measured size of that difference — a budget now describing a smaller gap
  // than it was written for, since the remaining difference is the weighting
  // of the taps rather than their absence.
  //
  // Sixteen because that is what the hardware backends report and what a
  // sampler is clamped against; the cost here is linear in the taps and paid
  // only by a sampler that asked.
  int get maxAnisotropy => 16;

  /// Two by default, and settable — `gfx-50n`.
  ///
  /// The rasteriser could write into any number of arrays, so the two is a
  /// choice rather than a limit: it answers what the hardware backends answer
  /// where they work, because a reference that could do more than the thing
  /// it is a reference for would record pictures no shipping backend can
  /// reproduce.
  ///
  /// **Settable for the harder reason.** The device this stands in for is
  /// Impeller on OpenGL ES, which aborts rather than refusing, so the no-MRT
  /// path cannot be run on the hardware that has it — there is no way to see
  /// what the engine does there except to build a device that says one. A
  /// rasteriser that can be that device is the only place the path is
  /// exercised with real pixels at the end of it.
  @override
  final int maxColorAttachments;

  @override
  // Nothing to probe: a cube here is six arrays of floats and a table saying
  // which of them a direction lands on.
  bool get supportsCubeTextures => true;

  @override
  // A level is an array like any other, and the rasteriser writes into
  // whichever one the attachment names — see `CpuTexture.subresource`.
  bool get supportsRenderToMip => true;

  @override
  TextureHandle? createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    // The same shape `createCubeTextureFromPixels` builds, so
    // `BoundTexture.sampleCube` reads a rendered cube exactly as it reads an
    // uploaded one: six faces hanging off face zero, a chain per face. The
    // chain reaches one by one and no further, which is where the upload's
    // arithmetic stops too.
    final faces = List<CpuTexture>.generate(
      6,
      (_) => CpuTexture(size, size, format),
    );
    if (mipLevels > 1) {
      for (final face in faces) {
        final chain = <CpuTexture>[];
        var side = size;
        for (var level = 1; level < mipLevels && side > 1; level++) {
          side = side >> 1;
          chain.add(CpuTexture(side, side, format));
        }
        face.levels = chain;
      }
    }
    final cube = faces[0]..faces = faces;
    return TextureHandle(
      backend: cube,
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    if (format.isCompressed) {
      throw UnsupportedError(
        'The software rasteriser samples raw RGBA texels — '
        'TextureFormat.${format.name} is block-compressed and has no decode '
        'path here, by design (see ARCHITECTURE.md §15).',
      );
    }
    if (faces.length != 6) return null;

    CpuTexture? read(ByteData source, int side) {
      final need = side * side * 4;
      // **Exactly, not "at least".** The interface says null when a face is not
      // the size its description says, and the other two backends enforce it —
      // WebGL because `texSubImage2D` would read past the level, Impeller
      // because `overwrite` throws. This one accepted a longer buffer and used
      // its prefix, which turns a chain built with the wrong arithmetic into a
      // cube that loads and reflects noise.
      if (source.lengthInBytes != need) return null;
      final texture = CpuTexture(side, side, format);
      final bytes = source.buffer.asUint8List(source.offsetInBytes, need);
      for (var i = 0; i < need; i++) {
        texture.pixels[i] = bytes[i] / 255.0;
      }
      return texture;
    }

    final built = <CpuTexture>[];
    for (final face in faces) {
      final texture = read(face, size);
      if (texture == null) return null;
      built.add(texture);
    }

    // **A chain per face, not one chain for the cube.** Each face is sampled as
    // its own square, so the levels have to hang off the face that owns them;
    // hanging them off face zero would give five faces a chain belonging to the
    // sixth, which reads as a seam that moves with the roughness.
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chains = List<List<CpuTexture>>.generate(6, (_) => <CpuTexture>[]);
      var side = size;
      for (final level in mipLevels) {
        if (level.length != 6) return null;
        side = side > 1 ? side >> 1 : 1;
        for (var face = 0; face < 6; face++) {
          final texture = read(level[face], side);
          if (texture == null) return null;
          chains[face].add(texture);
        }
      }
      for (var face = 0; face < 6; face++) {
        built[face].levels = chains[face];
      }
    }

    // The handle's own texture is face zero, so anything that samples this as
    // an ordinary 2D texture gets +X rather than nothing. The six live beside
    // it, and `BoundTexture.sampleCube` is what reaches them.
    final cube = built[0]..faces = built;
    return TextureHandle(
      backend: cube,
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => TextureHandle(
    backend: CpuTexture(spec.width, spec.height, spec.format),
    width: spec.width,
    height: spec.height,
    format: spec.format,
    sampleCount: 1,
    storageMode: spec.storageMode,
  );

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    if (format.isCompressed) {
      throw UnsupportedError(
        'The software rasteriser samples raw RGBA texels — '
        'TextureFormat.${format.name} is block-compressed and has no decode '
        'path here, by design (see ARCHITECTURE.md §15).',
      );
    }
    // **Exactly, not "at least"** — the same rule the cube path above spells
    // out, and for the same reason. `GraphicsDevice.createTextureFromPixels`
    // says null when the buffer is not the size the description asks for;
    // Impeller refuses on `!=` because `overwrite` would throw, WebGL on `!=`
    // because `texSubImage2D` reads exactly that many bytes. This one took the
    // prefix of anything longer, so a decoder that disagreed with the engine
    // about the dimensions was refused on two backends and silently drew
    // something else on the third.
    final expected = width * height * _texelBytes(format);
    if (pixels.lengthInBytes != expected) return null;
    final texture = CpuTexture(width, height, format);
    _decodeInto(texture.pixels, pixels, format, width * height);
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chain = <CpuTexture>[];
      var w = width;
      var h = height;
      for (final level in mipLevels) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        final small = CpuTexture(w, h, format);
        final need = w * h * _texelBytes(format);
        // Exactly, as above. A chain built with the wrong arithmetic is the
        // case this catches, and it is the one that looks like a filtering bug
        // rather than like a bad upload.
        if (level.lengthInBytes != need) return null;
        _decodeInto(small.pixels, level, format, w * h);
        chain.add(small);
      }
      texture.levels = chain;
    }
    return TextureHandle(
      backend: texture,
      width: width,
      height: height,
      format: format,
      sampleCount: 1,
      storageMode: StorageMode.devicePrivate,
    );
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    if (!readbackFormats.contains(target.format)) {
      throw UnsupportedError(
        'overwriteTexture: TextureFormat.${target.format.name} is not one '
        'of readbackFormats — the two this call, like readback, insists on.',
      );
    }
    if (mipLevel != 0) {
      throw UnsupportedError(
        'overwriteTexture: mip level $mipLevel is refused; only the base '
        'level (0) may be overwritten.',
      );
    }
    final rect =
        region ?? ScreenRect(width: target.width, height: target.height);
    if (rect.x < 0 ||
        rect.y < 0 ||
        rect.x + rect.width > target.width ||
        rect.y + rect.height > target.height) {
      throw ArgumentError(
        'overwriteTexture: $rect does not fit inside a '
        '${target.width}x${target.height} texture',
      );
    }
    if (rgba.lengthInBytes != rect.width * rect.height * 4) {
      throw ArgumentError(
        'overwriteTexture: ${rgba.lengthInBytes} bytes does not match '
        '${rect.width}x${rect.height} RGBA8',
      );
    }

    final texture = target.backend as CpuTexture;
    for (var y = 0; y < rect.height; y++) {
      for (var x = 0; x < rect.width; x++) {
        final src = (y * rect.width + x) * 4;
        final dstTexel = ((rect.y + y) * target.width + (rect.x + x)) * 4;
        for (var c = 0; c < 4; c++) {
          texture.pixels[dstTexel + c] = rgba.getUint8(src + c) / 255.0;
        }
      }
    }
  }

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    // The usage is recorded rather than acted on: nothing here binds a buffer
    // to anything for life. Recorded anyway, because a backend that forgets
    // which it was told would pass the conformance check for the wrong reason.
    final copy = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return GeometryBuffer(
      backend: (bytes: ByteData.sublistView(copy), usage: usage),
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  /// Writes straight into the `Uint8List` [uploadGeometry] copied the
  /// original bytes into — there is no separate device-side copy to keep in
  /// step, which is the one respect in which this backend's write is simpler
  /// than the other three's.
  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    final backend = target.backend as ({ByteData bytes, GeometryUsage usage});
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
        'fit inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    final at = target.offsetInBytes + offsetInBytes;
    backend.bytes.buffer
        .asUint8List(backend.bytes.offsetInBytes + at, bytes.lengthInBytes)
        .setAll(
          0,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) {
    // Every format this backend can read is floats. The integer ones exist in
    // the vocabulary because flutter_gpu has them; a stage here receives one
    // `Float32List`, so a `uint32` attribute would have to be reinterpreted,
    // and reinterpreting it silently is how a joint index becomes 1.4e-45.
    if (layout != null) {
      for (final buffer in layout.buffers) {
        for (final attribute in buffer.attributes) {
          if (!attribute.format.name.startsWith('float')) {
            throw UnsupportedError(
              'attribute "${attribute.name}" is ${attribute.format.name}. This '
              'backend hands a vertex stage a list of floats, so it reads only '
              'the float formats.',
            );
          }
        }
      }
    }
    final v = (vertex.backend as CpuStage).vertex;
    final f = (fragment.backend as CpuStage).fragment;
    if (v == null || f == null) {
      throw StateError(
        'createPipeline("${vertex.name}", "${fragment.name}"): the stages are '
        'the wrong way round, or one of them is not the kind it is being used '
        'as.',
      );
    }
    return PipelineHandle(
      backend: CpuPipeline(v, f, layout),
      name: '${vertex.name}+${fragment.name}',
    );
  }

  @override
  void beginFrame() {
    // Nothing rotates here. Implemented as nothing, which is the answer the
    // contract asks for rather than the absence of one.
  }

  @override
  void onFrameComplete(void Function() whenDone) {
    // Straight away, and honestly: this backend rasterises on the calling
    // thread, so by the time anybody could ask, the frame is finished.
    whenDone();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. Nothing here would abort — the rasteriser writes into
    // whichever lists it is handed — and it refuses all the same, because a
    // reference implementation that accepted a pass the shipping backends
    // would not is a reference for the wrong thing.
    descriptor.checkAttachmentLimit(
      maxColorAttachments,
      backend: 'the software rasteriser',
    );
    return CpuEncoder(descriptor);
  }

  @override
  Future<ByteData?> readPixels(TextureHandle texture) async {
    final backend = texture.backend as CpuTexture;
    final out = Uint8List(backend.width * backend.height * 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = (backend.pixels[i].clamp(0.0, 1.0) * 255.0).round();
    }
    return ByteData.sublistView(out);
  }

  /// [texture]'s own RGBA floats, unclamped and unconverted — what
  /// [readPixels] throws away on the way to an 8-bit picture.
  ///
  /// **Only this backend can answer this, and only this backend needs to.**
  /// A hardware texture's bytes live on the GPU in whatever layout the driver
  /// chose; reading them back as linear floats is the round trip
  /// `GraphicsDevice.readback` already declines for anything but its two
  /// 8-bit formats. This backend's own texture already *is* a `Float32List`
  /// — see `CpuTexture` — so there is nothing to convert and nothing to ask
  /// a driver for.
  ///
  /// A diagnostic wants exactly what a picture cannot show: a depth of forty
  /// metres does not fit in `0..1`, and a `double.nan` a broken shader wrote
  /// clamps to `1.0` before it ever reaches [readPixels] — silently, since
  /// `1.0` is a perfectly ordinary channel value. Reading the texture as it
  /// actually stands is the only way to tell a NaN or an out-of-range value
  /// apart from the picture it happens to resemble once rounded.
  Float32List readHdrPixels(TextureHandle texture) {
    final backend = texture.backend as CpuTexture;
    return Float32List.fromList(backend.pixels);
  }

  /// The region, converted on the spot.
  ///
  /// Nothing here is in flight: the pass that wrote these floats ran to the
  /// end before `submit` returned, so "the texture as the passes before this
  /// call left it" is simply the texture. The future is already complete when
  /// it is handed back, which is the honest answer and also what makes the
  /// engine's own tests of the callers run in a plain `flutter test`.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    final rect = readbackRegionOf(texture, region);
    final backend = texture.backend as CpuTexture;
    final out = Uint8List(rect.width * rect.height * 4);
    final source = backend.pixels;
    for (var y = 0; y < rect.height; y++) {
      final from = ((rect.y + y) * backend.width + rect.x) * 4;
      final to = y * rect.width * 4;
      for (var i = 0; i < rect.width * 4; i++) {
        out[to + i] = (source[from + i].clamp(0.0, 1.0) * 255.0).round();
      }
    }
    return Future<ByteData>.value(ByteData.sublistView(out));
  }

  /// A no-op, and honestly one: every texture and buffer this backend hands
  /// out is a plain Dart object — a [CpuTexture] wrapping a `Float32List`, a
  /// record wrapping a `ByteData` — with nothing external to release. The
  /// garbage collector already does the whole of what this method would do on
  /// a backend with a driver underneath it.
  @override
  void dispose() {}

  /// Nothing to free, for the same reason [dispose] has nothing to free: a
  /// texture here is a Dart list, and dropping the handle is already the whole
  /// of releasing it. Written out rather than left to a default so that a
  /// backend which grows a driver underneath it has to say so.
  @override
  void releaseTexture(TextureHandle texture) {}

  @override
  void releaseGeometry(GeometryBuffer geometry) {}
}

/// How many bytes one texel of [format] occupies in an upload.
///
/// **This used to be four for everything.** Every texture the engine uploaded
/// was eight-bit RGBA, so a constant was right by accident until the morph
/// deltas arrived as `r32g32b32a32Float`: sixteen bytes a texel, refused by the
/// size check, and a model that quietly drew its base shape on this backend
/// while the other two morphed. A format the sampler cannot describe is not a
/// format this rasteriser should guess at, so anything unlisted keeps the old
/// four and is refused by the size check if that is wrong — which is a null
/// upload and a warning rather than a texture full of misread bytes.
int _texelBytes(TextureFormat format) => switch (format) {
  TextureFormat.r32g32b32a32Float => 16,
  TextureFormat.r16g16b16a16Float => 8,
  TextureFormat.r32Float => 4,
  _ => 4,
};

/// Reads [count] texels out of [pixels] into a [CpuTexture]'s four-float
/// storage.
///
/// The float formats are copied as they are; everything else is the eight-bit
/// unorm decode this backend has always done. A single-channel float lands in
/// red with the rest at nought and alpha at one, which is what sampling one of
/// these means everywhere else.
void _decodeInto(
  Float32List into,
  ByteData pixels,
  TextureFormat format,
  int count,
) {
  switch (format) {
    case TextureFormat.r32g32b32a32Float:
      for (var i = 0; i < count * 4; i++) {
        into[i] = pixels.getFloat32(i * 4, Endian.little);
      }
    case TextureFormat.r16g16b16a16Float:
      // Read through a Float32List rather than by hand: `dart:typed_data` has
      // no half-float view, and the conversion belongs in one place.
      for (var i = 0; i < count * 4; i++) {
        into[i] = _halfToDouble(pixels.getUint16(i * 2, Endian.little));
      }
    case TextureFormat.r32Float:
      for (var i = 0; i < count; i++) {
        into[i * 4] = pixels.getFloat32(i * 4, Endian.little);
        into[i * 4 + 1] = 0.0;
        into[i * 4 + 2] = 0.0;
        into[i * 4 + 3] = 1.0;
      }
    default:
      for (var i = 0; i < count * 4; i++) {
        into[i] = pixels.getUint8(i) / 255.0;
      }
  }
}

/// One IEEE binary16 as a double.
double _halfToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1F;
  final mantissa = bits & 0x3FF;

  if (exponent == 0) return sign * mantissa * _halfSubnormal;
  if (exponent == 0x1F) {
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign * (1.0 + mantissa / 1024.0) * _twoTo(exponent - 15);
}

/// 2⁻²⁴, the step between subnormal halves.
const double _halfSubnormal = 1.0 / 16777216.0;

double _twoTo(int power) {
  var value = 1.0;
  for (var i = 0; i < power.abs(); i++) {
    value *= 2.0;
  }
  return power < 0 ? 1.0 / value : value;
}
