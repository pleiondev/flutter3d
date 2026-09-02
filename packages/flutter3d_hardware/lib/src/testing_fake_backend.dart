/// A device that records rather than draws, and the shader library it answers
/// every name with.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'testing_fake_pass.dart';

/// A bundle that has every stage anybody asks for, except the ones it is told
/// to withhold.
///
/// Withholding matters: `ParticleContributor` draws nothing when its stages are
/// missing, and that path had never been exercised.
final class FakeShaderLibrary implements ShaderLibrary {
  FakeShaderLibrary({this.missing = const <String>{}});

  final Set<String> missing;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) => missing.contains(name)
      ? null
      : _handles.putIfAbsent(
          name,
          () => ShaderHandle(backend: name, name: name),
        );
}

/// A device that records rather than draws.
final class FakeBackend implements GraphicsDevice {
  FakeBackend({
    Set<String> missingShaders = const <String>{},
    this.supportsWireframe = true,
    this.unsupportedFormats = const <TextureFormat>{},
    this.maxAnisotropy = 16,
  }) : shaders = FakeShaderLibrary(missing: missingShaders);

  @override
  final FakeShaderLibrary shaders;

  /// The formats this fake says it cannot sample, so a test can be the
  /// device that has no BC7 and see what a loader does about it.
  final Set<TextureFormat> unsupportedFormats;

  @override
  bool supportsTextureFormat(TextureFormat format) =>
      !unsupportedFormats.contains(format);

  /// Sixteen, which is what most hardware answers, and settable so a test
  /// can be the device that answers one and see what a caller clamps to.
  @override
  final int maxAnisotropy;

  /// Settable, because the interesting case is the backend that says no —
  /// OpenGL ES has no `glPolygonMode`, and the engine is supposed to decline
  /// its own wireframe setting rather than let the request reach a backend
  /// that would refuse it mid-frame.
  @override
  final bool supportsWireframe;

  /// True, because a fake has nothing to be incapable with. The real answer is
  /// a device property, and the two backends that have one disagree.
  @override
  bool get supportsMipmaps => true;

  @override
  bool get supportsCubeTextures => true;

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    // Recorded by no fake and refused by none: this backend answers the shape
    // of a call, not the contents of a texture.
    List<List<ByteData>>? mipLevels,
  }) => faces.length == 6
      ? TextureHandle(
          backend: const Object(),
          width: size,
          height: size,
          format: format,
          type: TextureType.textureCube,
        )
      : null;

  /// The engine's own convention, so a fake never exercises the remap. The
  /// backends that need the other one are covered by running them.
  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  int get preferredSampleCount => 4;

  /// Every pass ever opened, in the order it was opened.
  final List<FakePass> passes = <FakePass>[];

  final List<RenderTargetSpec> createdTextures = <RenderTargetSpec>[];

  int frames = 0;
  int _serial = 0;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.b8g8r8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d24UnormS8Uint;

  @override
  bool get supportsOffscreenMsaa => true;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) {
    createdTextures.add(spec);
    return TextureHandle(
      backend: 'fake ${_serial++}',
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );
  }

  /// Frames whose work the GPU has not "finished".
  ///
  /// Held rather than run, so a test can decide when a frame is over — which is
  /// the whole question the renderer's finished-frame textures turn on.
  final List<void Function()> pendingFrames = <void Function()>[];

  /// Whether [onFrameComplete] runs its callback at once.
  ///
  /// True by default, so every test that does not care about this sees a
  /// backend that finishes as it goes.
  bool completesImmediately = true;

  @override
  void onFrameComplete(void Function() whenDone) {
    if (completesImmediately) {
      whenDone();
      return;
    }
    pendingFrames.add(whenDone);
  }

  /// Lets the oldest unfinished frame complete.
  void finishOldestFrame() {
    if (pendingFrames.isEmpty) return;
    pendingFrames.removeAt(0)();
  }

  /// Pixel uploads, in order, so a test can assert what reached the device.
  final List<RenderTargetSpec> uploadedTextures = <RenderTargetSpec>[];

  /// The bytes of each of those, for a test that cares what colour it was.
  final List<ByteData> uploadedPixels = <ByteData>[];

  /// The chain each of those came with — null for an upload that brought
  /// none — so a test can tell a base level from a base level and its mips.
  final List<List<ByteData>?> uploadedMipLevels = <List<ByteData>?>[];

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final spec = RenderTargetSpec(
      width: width,
      height: height,
      format: format,
      storageMode: StorageMode.hostVisible,
    );
    uploadedTextures.add(spec);
    uploadedPixels.add(pixels);
    uploadedMipLevels.add(mipLevels);
    return createTexture(spec);
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) => PipelineHandle(
    backend: '${vertex.name}+${fragment.name}',
    name: '${vertex.name}+${fragment.name}',
  );

  /// Recorded with its usage, because a backend exists that cannot change its
  /// mind about one later.
  final List<GeometryUsage> uploads = <GeometryUsage>[];

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    uploads.add(usage);
    return _geometry(bytes);
  }

  GeometryBuffer _geometry(ByteData bytes) => GeometryBuffer(
    backend: 'uploaded ${_serial++}',
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
  );

  @override
  void beginFrame() => frames++;

  /// Nothing was drawn, so there is nothing to show, and pretending otherwise
  /// would be worse than refusing: a test handed a blank widget could assert
  /// something about a frame that never existed. Nothing under test here
  /// reaches this — only an application does, once per frame.
  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) => throw UnsupportedError(
    'FakeBackend draws nothing, so there is nothing to present of $frame',
  );

  /// Null, which is a legitimate answer rather than a refusal: it is what a
  /// real device says about a texture whose pixels cannot be read.
  @override
  Future<ByteData?> readPixels(TextureHandle texture) =>
      Future<ByteData?>.value();

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final pass = FakePass(descriptor);
    passes.add(pass);
    return pass;
  }

  /// Whether [dispose] has been called, for a test that wants to assert a
  /// device was actually torn down rather than merely dropped.
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  /// What was handed back one at a time, in the order it was handed back.
  ///
  /// Recorded rather than ignored because the thing worth testing about a
  /// release is that it happened at all: the leak this contract exists for is
  /// a caller that reallocates and never calls it, which is invisible to a
  /// backend whose own release is a no-op.
  final List<TextureHandle> releasedTextures = <TextureHandle>[];
  final List<GeometryBuffer> releasedGeometry = <GeometryBuffer>[];

  @override
  void releaseTexture(TextureHandle texture) => releasedTextures.add(texture);

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      releasedGeometry.add(geometry);
}
