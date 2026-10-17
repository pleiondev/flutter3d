import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'null_pass.dart';
import 'null_texels.dart';

/// A [GraphicsDevice] with no GPU and no rasteriser: it keeps textures in
/// memory, clears, uploads, overwrites and reads them back, and refuses
/// every pipeline at its first draw.
///
/// **What a backend is, with the drawing taken out.** Every member here is
/// one a backend for Vulkan, Metal, Direct3D or a server renderer writes
/// too, against the same published libraries: the handles come from
/// `package:flutter3d_hardware/backend.dart`, a pass is a [PassEncoder]
/// with the [CommandEncoder] mixin, and what the device cannot do it says
/// through [features] and refuses by name. The engine's renderer runs on
/// it, a frame is the clear colour, and each pipeline the frame draws with
/// is reported once on [pipelineRefusals] and skipped.
///
/// Opened as every backend is, with [open], so `DeviceRegistry.addBackend`,
/// `flutter3d_testing`'s `renderFrame(device:)` and the conformance suite
/// take it as they take the four in the engine's repository.
///
/// **A member of a backend's own is best private, or named for the
/// backend.** A 1.x minor adds members with bodies to [GraphicsDevice] and
/// [PassEncoder], and a public member here that a later minor names too
/// either stops compiling against it or, with the same signature, silently
/// replaces the new default. [texelsOf] and [isDisposed] are public for this
/// package's tests, and are the two names this device would have to change
/// if a minor took them. That risk is the backend author's; the stability
/// section of `HAL.md` says so.
final class NullDevice extends GraphicsDevice {
  NullDevice._();

  /// Opens a device. The size is the one every backend is opened at; a
  /// device with no surface keeps none, and draws each pass at the size of
  /// its target.
  static Future<NullDevice> open({
    required int width,
    required int height,
  }) async => NullDevice._();

  /// The name a refusal from this device carries.
  static const String name = 'null';

  @override
  String get backendName => name;

  /// [name], said outright rather than left to the default: the id a
  /// compiler and a manifest match is fixed for good, and must not follow a
  /// later rewording of the name people read.
  @override
  String get backendId => name;

  /// Little beyond the base contract: texture-to-texture copies, 32-bit
  /// float targets, which it holds as it holds every other, and 32-bit
  /// indices, which it takes as it takes any. A capability is reported when
  /// the device does it, and refused by name when asked of it otherwise; a
  /// backend grows this set as it grows, and the conformance suite holds
  /// each answer true both ways.
  @override
  final DeviceFeatures features = DeviceFeatures(const <DeviceFeature>{
    DeviceFeature.textureCopy,
    DeviceFeature.float32Renderable,
    DeviceFeature.indexUint32,
  });

  /// The defaults, with no compute: this device has no compute pass.
  @override
  final DeviceLimits limits = const DeviceLimits(
    maxColorAttachments: 4,
    maxSampleCount: 1,
    maxComputeWorkgroupStorageSize: 0,
    maxComputeInvocationsPerWorkgroup: 0,
    maxComputeWorkgroupSizeX: 0,
    maxComputeWorkgroupSizeY: 0,
    maxComputeWorkgroupSizeZ: 0,
    maxComputeWorkgroupsPerDimension: 0,
  );

  /// The formats this device holds: the eight-bit colours an image arrives
  /// in, the half and full float colours the engine renders in, and depth.
  /// Each is held as four floats a texel, so any of them clears, uploads and
  /// reads back.
  static const Set<TextureFormat> heldFormats = <TextureFormat>{
    TextureFormat.r8g8b8a8UNormInt,
    TextureFormat.b8g8r8a8UNormInt,
    TextureFormat.r16g16b16a16Float,
    TextureFormat.r32g32b32a32Float,
    TextureFormat.r32Float,
    TextureFormat.d32Float,
  };

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      switch (format) {
        TextureFormat.d32Float => const TextureFormatSupport(
          sampled: true,
          renderable: true,
          depthStencil: true,
        ),
        _ when heldFormats.contains(format) => const TextureFormatSupport(
          sampled: true,
          renderable: true,
        ),
        _ => TextureFormatSupport.none,
      };

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32Float;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  int get preferredSampleCount => 1;

  // ------------------------------------------------------------- shaders

  /// Every stage the engine asks for, by name, compiled to nothing: the
  /// renderer is built on this device as on any other, and the pipelines it
  /// links are refused when they draw.
  @override
  final ShaderLibrary shaders = NullShaderLibrary();

  /// A bundle is decoded, so bytes that are not one are refused the way
  /// every backend refuses them, and its stages are answered by name. The
  /// section this backend's compiler writes, when the bundle carries one,
  /// adds the materials compiled for it.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async =>
      NullLoadedShaderLibrary(ShaderBundle.decode(bytes));

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => wrapPipeline(
    owner: this,
    backend: Object(),
    name: '${vertex.name}+${fragment.name}',
  );

  // ------------------------------------------------------------ textures

  final Expando<NullTexels> _texels = Expando<NullTexels>('texels');

  /// The texels behind [texture], which this device made.
  NullTexels texelsOf(TextureHandle texture) {
    debugCheckLive(texture, 'NullDevice');
    final texels = _texels[texture];
    if (texels == null) {
      throw ArgumentError.value(texture, 'texture', 'was not made by $name');
    }
    return texels;
  }

  TextureHandle _make({
    required int width,
    required int height,
    required TextureFormat format,
    int layers = 1,
    int levels = 1,
    StorageMode storageMode = StorageMode.devicePrivate,
    TextureType type = TextureType.texture2D,
  }) {
    if (!heldFormats.contains(format)) {
      throw refuseResource(
        'a ${format.name} texture',
        '$name holds ${heldFormats.map((f) => f.name).join(', ')}',
      );
    }
    final texels = NullTexels(
      width: width,
      height: height,
      layers: layers,
      levels: levels,
    );
    final texture = wrapTexture(
      owner: this,
      backend: texels,
      width: width,
      height: height,
      format: format,
      storageMode: storageMode,
      type: type,
      mipLevelCount: levels,
    );
    _texels[texture] = texels;
    return texture;
  }

  /// A flat texture of one of [heldFormats], to draw into, overwrite or
  /// copy. Every other shape is refused by the feature it needs; writing
  /// one with `writeTexture` needs `DeviceFeature.textureWrites`, which this
  /// device does not report.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    // A volume is filled by `writeTexture` alone, so it is refused by that
    // first; the layered shapes a pass can draw into, a storage usage and
    // more than one sample are refused by the feature the descriptor names.
    final dimension = descriptor.dimension;
    if (dimension != TextureDimension.d2 &&
        dimension != TextureDimension.d2Array &&
        dimension != TextureDimension.cube &&
        dimension != TextureDimension.cubeArray) {
      throw refuse(DeviceFeature.textureWrites);
    }
    descriptor.checkFeatures(features, backend: name);
    return _make(
      width: descriptor.width,
      height: descriptor.height,
      format: descriptor.format,
      storageMode: descriptor is RenderTargetDescriptor
          ? descriptor.storageMode
          : StorageMode.devicePrivate,
    );
  }

  /// Refused by the feature the descriptor names first: `buffers`, which
  /// this device does not report.
  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    descriptor.checkFeatures(features, backend: name);
    throw refuse(DeviceFeature.buffers);
  }

  @override
  TransferEncoder beginTransferPass({String? label}) => NullTransfer(this);

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => throw refuse(DeviceFeature.cubeTextures);

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    if (mipLevels != null && mipLevels.isNotEmpty) {
      throw refuse(DeviceFeature.manualMipmaps);
    }
    final expected = width * height * format.bytesPerTexel;
    if (format.bytesPerTexel == 0 || pixels.lengthInBytes != expected) {
      throw refuseResource(
        'createTextureFromPixels',
        'a ${width}x$height ${format.name} texture takes $expected bytes and '
            '${pixels.lengthInBytes} were given',
      );
    }
    final texture = _make(
      width: width,
      height: height,
      format: format,
      storageMode: StorageMode.hostVisible,
    );
    texelsOf(texture).decode(format, pixels, layer: 0, level: 0);
    return texture;
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    if (!readbackFormats.contains(target.format)) {
      throw refuseResource(
        'overwriteTexture',
        'TextureFormat.${target.format.name} is not one of readbackFormats',
      );
    }
    if (mipLevel != 0) {
      throw refuseResource(
        'overwriteTexture',
        'mip level $mipLevel is refused; only the base level (0) may be '
            'overwritten',
      );
    }
    final rect = region ?? ScreenRect.of(target);
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
    texelsOf(target).decodeRegion(target.format, rgba, rect);
  }

  @override
  void releaseTexture(TextureHandle texture) => _texels[texture] = null;

  // ------------------------------------------------------------ geometry

  final Expando<Uint8List> _bytes = Expando<Uint8List>('geometry');

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final copy = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final buffer = wrapGeometry(
      backend: copy,
      offsetInBytes: 0,
      lengthInBytes: copy.length,
      release: releaseGeometry,
    );
    _bytes[buffer] = copy;
    return buffer;
  }

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    debugCheckLive(target, 'overwriteGeometry');
    final held = target.backend;
    if (held is! Uint8List) {
      throw ArgumentError.value(target, 'target', 'was not made by $name');
    }
    final at = target.offsetInBytes + offsetInBytes;
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
        'fit inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    held.setRange(
      at,
      at + bytes.lengthInBytes,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) => _bytes[geometry] = null;

  // -------------------------------------------------------------- frames

  @override
  void beginFrame() {}

  /// At once: a pass is done by the time it is submitted.
  @override
  void onFrameComplete(void Function() whenDone) => whenDone();

  /// Clears what the pass clears, and hands back a pass that refuses every
  /// pipeline it draws with.
  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    descriptor
      ..checkAttachmentLimit(limits.maxColorAttachments, backend: name)
      ..checkFeatures(features, backend: name);
    for (final color in descriptor.colors) {
      if (color.loadAction != LoadAction.clear) continue;
      // Every kind of clear as doubles, which hold an integer one exactly.
      final clear = (color.clearValue ?? ClearColor.transparentBlack).channels;
      texelsOf(color.texture).fill(
        layer: color.layer + color.face,
        level: color.mipLevel,
        r: clear[0],
        g: clear[1],
        b: clear[2],
        a: clear[3],
      );
    }
    final depth = descriptor.depth;
    if (depth != null && depth.loadAction == LoadAction.clear) {
      final value = depth.clearValue;
      texelsOf(depth.texture).fill(
        layer: depth.layer + depth.face,
        level: depth.mipLevel,
        r: value,
        g: value,
        b: value,
        a: value,
      );
    }
    return NullPass(this);
  }

  /// The texels as they are now: the copy is taken when it is asked for,
  /// so a pass submitted after the call is not in it.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    final texels = texelsOf(texture);
    if (readbackConverts(texture, region: region)) {
      return Future<ByteData>.value(
        texels.encode(TextureFormat.r8g8b8a8UNormInt, ScreenRect.of(texture)),
      );
    }
    final rect = readbackRegionOf(texture, region);
    return Future<ByteData>.value(texels.encode(texture.format, rect));
  }

  // ------------------------------------------------------------ lifetime

  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast();

  /// One [DeviceLossReason.destroyed], when [dispose] runs: nothing else can
  /// take a device with no GPU away, and every backend owes a caller at
  /// least the loss it causes itself.
  @override
  Stream<DeviceLoss> get lost => _lost.stream;

  @override
  bool get isLost => _disposed;

  /// Says so on [lost], once, and closes it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lost.add(
      const DeviceLoss(
        reason: DeviceLossReason.destroyed,
        message: 'the device was disposed',
      ),
    );
    unawaited(_lost.close());
  }
}

/// Every stage name, answered with a handle that compiles to nothing.
final class NullShaderLibrary with ShaderLibrary {
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) => _handles.putIfAbsent(
    name,
    () => wrapShader(
      backend: name,
      name: name,
      release: (ShaderHandle h) => forgetShader(_handles, h),
    ),
  );
}

/// A loaded bundle's stages by name, kept across a reload that keeps them.
final class NullLoadedShaderLibrary with ShaderLibrary, LoadedShaderLibrary {
  NullLoadedShaderLibrary(ShaderBundle bundle)
    : _bundle = bundle,
      _names = _namesIn(bundle);

  ShaderBundle _bundle;
  Set<String> _names;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  /// The stages [bundle] claims, and the materials in this backend's own
  /// section: what `NullMaterialCompiler` wrote, a JSON list of names.
  static Set<String> _namesIn(ShaderBundle bundle) {
    final section = bundle.section(nullSection);
    return <String>{
      ...bundle.names,
      if (section != null)
        ...(jsonDecode(
                  utf8.decode(
                    section.buffer.asUint8List(
                      section.offsetInBytes,
                      section.lengthInBytes,
                    ),
                  ),
                )
                as List<Object?>)
            .cast<String>(),
    };
  }

  @override
  String get name => _bundle.name;

  @override
  ShaderHandle? operator [](String name) => _names.contains(name)
      ? _handles.putIfAbsent(
          name,
          () => wrapShader(
            backend: name,
            name: name,
            release: (ShaderHandle h) => forgetShader(_handles, h),
          ),
        )
      : null;

  /// Takes [bytes] in place of the bundle, unless it drops a stage already
  /// handed out, which is refused naming it.
  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final names = _namesIn(bundle);
    final dropped = _handles.keys.where((n) => !names.contains(n));
    if (dropped.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason: 'it no longer has ${dropped.join(', ')}, already in use',
      );
    }
    _bundle = bundle;
    _names = names;
  }
}

/// The id of the null backend's section of a shader bundle.
const String nullSection = 'null';
