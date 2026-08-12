/// The flutter_gpu side of [GraphicsDevice] and [CommandEncoder].
///
/// Everything that used to reach `gpu.gpuContext` from the renderer, its nodes
/// and its contributors is here, behind an object that arrives as an argument.
/// This is the file a second backend is written *beside*, not inside.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'gpu_formats.dart';
import 'gpu_texture.dart';

/// flutter_gpu as a [GraphicsDevice].
///
/// Construct one and hand it to `Renderer.create`. Nothing else in the engine
/// names flutter_gpu, which is what makes the import graph a property somebody
/// can check: `test/backend_is_contained_test.dart` scans for it.
final class GpuRenderBackend implements GraphicsDevice {
  GpuRenderBackend._(this._library, this._transients);

  /// Loads [bundleAsset] and builds a backend around the running context.
  ///
  /// Throws when the bundle is missing, which is the right moment to fail: a
  /// renderer without its shaders cannot draw anything, and the alternative is
  /// a black screen with a null somewhere.
  factory GpuRenderBackend.create({String bundleAsset = defaultBundleAsset}) {
    final library = gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw StateError('Failed to load the shader bundle: $bundleAsset');
    }
    return GpuRenderBackend._(
      _GpuShaderLibrary(library),
      // Per-frame uniform allocators, rotated rather than reset in place.
      //
      // `CommandBuffer.submit` is asynchronous. Resetting a bump allocator
      // right after submit rewinds storage the GPU may still be reading, so the
      // next frame overwrites live uniforms. The symptom is flickering under
      // load, not a crash, which makes it hard to attribute.
      List<gpu.HostBuffer>.generate(
        _kFramesInFlight,
        (_) => gpu.gpuContext.createHostBuffer(),
      ),
    );
  }

  /// The bundle this package ships, package-qualified.
  ///
  /// It lives here rather than on `Renderer` because it is `impellerc` output:
  /// an artefact only this backend can read, built by this package's
  /// `tool/build_shaders.sh` from this package's `shaders/`. The engine names
  /// the shaders it wants by entry point and does not know what compiled them.
  ///
  /// The `packages/<name>/` prefix is how Flutter addresses a dependency's
  /// assets, and it is the same string from inside this package as from an
  /// application that merely depends on it.
  static const String defaultBundleAsset =
      'packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle';

  static const int _kFramesInFlight = 3;

  final _GpuShaderLibrary _library;
  final List<gpu.HostBuffer> _transients;

  /// Which allocator this frame writes into. -1 until the first [beginFrame].
  int _frame = -1;

  gpu.HostBuffer get _host => _transients[_frame < 0 ? 0 : _frame];

  @override
  ShaderLibrary get shaders => _library;

  @override
  TextureFormat get defaultColorFormat =>
      gpu.gpuContext.defaultColorFormat.toEngine();

  @override
  TextureFormat get defaultDepthStencilFormat =>
      gpu.gpuContext.defaultDepthStencilFormat.toEngine();

  @override
  @override
  // Impeller runs on Metal and Vulkan conventions.
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  // Renderable everywhere flutter_gpu runs, with nothing to enable.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  // Four is what this engine's goldens were recorded with.
  int get preferredSampleCount => 4;

  @override
  bool get supportsOffscreenMsaa => gpu.gpuContext.doesSupportOffscreenMSAA;

  @override
  // Impeller exposes glPolygonMode's equivalent, so the request goes through.
  bool get supportsWireframe => true;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => createGpuTexture(
        spec.storageMode,
        spec.width,
        spec.height,
        format: spec.format,
        sampleCount: spec.sampleCount,
        // Transient textures live in tile memory and cannot be sampled, so
        // asking for shader read on one is a contradiction the driver would
        // have to resolve for us.
        enableShaderReadUsage: spec.storageMode != StorageMode.deviceTransient,
      );

  @override
  PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment) =>
      PipelineHandle(
        backend: gpu.gpuContext.createRenderPipeline(
          vertex.backend as gpu.Shader,
          fragment.backend as gpu.Shader,
        ),
        name: '${vertex.name}+${fragment.name}',
      );

  /// [usage] is ignored here, and that is not laziness.
  ///
  /// A flutter_gpu `DeviceBuffer` is untyped: the same buffer can be bound as
  /// vertices in one draw and as indices in the next. The parameter exists
  /// because WebGL cannot do that — it binds a buffer to its target for life —
  /// and a contract that let one backend infer what the other must be told
  /// would be a contract only one backend could implement.
  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(bytes);
    return GeometryBuffer(
      backend: buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
  }

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
  }) {
    final texture = createGpuTexture(
      // Host-visible and origin-at-the-bottom, because these bytes come from
      // the CPU. Both are consequences of *how the texture is filled* rather
      // than of what it is for, which is why neither is a parameter above.
      StorageMode.hostVisible,
      width,
      height,
      format: format,
      coordinateSystem: TextureCoordinateSystem.uploadFromHost,
    );

    // `overwrite` demands exactly the base mip size and throws otherwise, so
    // asking first turns a mismatch into a null the caller can handle. Bytes
    // per texel is a backend question — padding and alignment are the device's
    // — which is precisely why this check cannot live above the seam.
    if (pixels.lengthInBytes !=
        texture.gpuTexture.getBaseMipLevelSizeInBytes()) {
      return null;
    }
    texture.gpuTexture.overwrite(pixels);
    return texture;
  }

  @override
  void beginFrame() {
    _frame = (_frame + 1) % _kFramesInFlight;
    // Safe to rewind: this allocator was last written a full ring of frames
    // ago, so the GPU is done with it.
    _transients[_frame].reset();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final buffer = gpu.gpuContext.createCommandBuffer();
    final pass = buffer.createRenderPass(_toRenderTarget(descriptor));
    return _GpuCommandEncoder(buffer, pass, _host);
  }

  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) =>
      // `asImage` is the cheap half of Impeller: the image is the same GPU
      // allocation the pass wrote, not a copy, so presenting costs a widget and
      // nothing else. That this is free here is exactly why the contract used
      // to say `ui.Image` — and exactly why saying so was a mistake.
      RawImage(
        image: frame.gpuTexture.asImage(),
        fit: fit,
        filterQuality: quality,
      );

  @override
  Future<ByteData?> readPixels(TextureHandle texture) {
    // Tile memory holds nothing once the pass has ended, and the backend's own
    // failure for this is unhelpful. Say it here, where the caller is in scope.
    if (texture.storageMode == StorageMode.deviceTransient) {
      return Future<ByteData?>.value();
    }
    // Premultiplied, which is what `rawRgba` means and what the reference PNGs
    // are decoded as. The two sides of a golden comparison must agree, and the
    // engine's own output is opaque, so this is the layout with no conversion
    // anywhere in the path.
    return texture.gpuTexture
        .asImage()
        .toByteData(format: ui.ImageByteFormat.rawRgba);
  }

  static gpu.RenderTarget _toRenderTarget(RenderPassDescriptor descriptor) =>
      gpu.RenderTarget(
        colorAttachments: <gpu.ColorAttachment>[
          for (final color in descriptor.colors)
            gpu.ColorAttachment(
              texture: color.texture.gpuTexture,
              resolveTexture: color.resolveTexture?.gpuTexture,
              loadAction: color.loadAction.toGpu(),
              storeAction: color.storeAction.toGpu(),
              clearValue: color.clearValue,
            ),
        ],
        depthStencilAttachment: switch (descriptor.depth) {
          null => null,
          // Cleared on entry and discarded on exit, because that is the only
          // thing any pass in this engine has ever wanted. See [DepthTarget].
          final DepthTarget depth => gpu.DepthStencilAttachment(
              texture: depth.texture.gpuTexture,
              depthClearValue: depth.clearValue,
            ),
        },
      );
}

/// A bundle's stages, wrapped so nothing above names `gpu.Shader`.
///
/// Handles are cached per name so that two lookups of the same stage give the
/// same handle. Nothing depends on that today — unlike `TextureHandle`,
/// identity carries no contract here — but a map lookup is cheaper than an
/// allocation on a path the particle contributor takes every frame.
final class _GpuShaderLibrary implements ShaderLibrary {
  _GpuShaderLibrary(this._library);

  final gpu.ShaderLibrary _library;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () {
        final shader = _library[name];
        return shader == null
            ? null
            : ShaderHandle(backend: shader, name: name);
      });
}

/// One flutter_gpu command buffer with one open pass.
///
/// The two are fused because Metal allows a single open encoder per buffer and
/// flutter_gpu offers no way to end a pass, so every site in this engine has
/// always been one buffer, one pass, one submit. See the note on
/// [CommandEncoder].
final class _GpuCommandEncoder implements CommandEncoder {
  _GpuCommandEncoder(this._buffer, this._pass, this._host);

  final gpu.CommandBuffer _buffer;
  final gpu.RenderPass _pass;

  /// This frame's uniform allocator, captured when the pass opened.
  final gpu.HostBuffer _host;

  @override
  void setViewport(ScreenRect rect) => _pass.setViewport(
        gpu.Viewport(
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        ),
      );

  @override
  void setScissor(ScreenRect rect) => _pass.setScissor(
        gpu.Scissor(
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        ),
      );

  @override
  void setPrimitiveType(PrimitiveType type) =>
      _pass.setPrimitiveType(type.toGpu());

  @override
  void setPolygonMode(PolygonMode mode) => _pass.setPolygonMode(mode.toGpu());

  @override
  void setCullMode(CullMode mode) => _pass.setCullMode(mode.toGpu());

  @override
  void setWindingOrder(WindingOrder order) =>
      _pass.setWindingOrder(order.toGpu());

  @override
  void setDepthWrite(bool enabled) => _pass.setDepthWriteEnable(enabled);

  @override
  void setDepthCompare(CompareFunction compare) =>
      _pass.setDepthCompareOperation(compare.toGpu());

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    _pass.setColorBlendEnable(state != null, colorAttachmentIndex: attachment);
    if (state == null) return;
    _pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: state.colorOperation.toGpu(),
        sourceColorBlendFactor: state.sourceColorFactor.toGpu(),
        destinationColorBlendFactor: state.destinationColorFactor.toGpu(),
        alphaBlendOperation: state.alphaOperation.toGpu(),
        sourceAlphaBlendFactor: state.sourceAlphaFactor.toGpu(),
        destinationAlphaBlendFactor: state.destinationAlphaFactor.toGpu(),
      ),
      colorAttachmentIndex: attachment,
    );
  }

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      _pass.bindPipeline(pipeline.backend as gpu.RenderPipeline);

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount) =>
      _pass.bindVertexBuffer(_view(buffer), vertexCount);

  @override
  void bindVertexData(ByteData bytes, int vertexCount) =>
      _pass.bindVertexBuffer(_host.emplace(bytes), vertexCount);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _pass.bindIndexBuffer(_view(buffer), type.toGpu(), indexCount);

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      _pass.bindIndexBuffer(_host.emplace(bytes), type.toGpu(), indexCount);

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final slot =
        (shader.backend as gpu.Shader).getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;

    final data = ByteData(size);
    members.forEach((name, values) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) return;
      // Whole arrays written from their reflected base offset. Impeller
      // reflects the array, not its elements — `lights[0]` comes back null —
      // but the std140 stride for a vec4 array is a flat 16 bytes, so a
      // contiguous write lands each element correctly.
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(offset + i * 4, values[i], Endian.host);
      }
    });

    _pass.bindUniform(slot, _host.emplace(data));
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) {
    // Tile memory cannot be sampled, and the backend's own assertion for this
    // fires from inside `bindTexture` with no idea which slot or which pass.
    // The handle carries the storage mode, so this can be said here, where the
    // slot name is in scope and the message names the mistake.
    assert(
      texture.storageMode != StorageMode.deviceTransient,
      'the "$slot" slot was handed a deviceTransient texture, which lives in '
      'tile memory and can only ever be an attachment',
    );
    _pass.bindTexture(
      (shader.backend as gpu.Shader).getUniformSlot(slot),
      texture.gpuTexture,
      sampler: (sampler ?? SamplerOptions.linearRepeat).toGpu(),
    );
  }

  @override
  void clearBindings() => _pass.clearBindings();

  @override
  void draw() => _pass.draw();

  @override
  void submit() => _buffer.submit();

  static gpu.BufferView _view(GeometryBuffer buffer) => gpu.BufferView(
        buffer.backend as gpu.DeviceBuffer,
        offsetInBytes: buffer.offsetInBytes,
        lengthInBytes: buffer.lengthInBytes,
      );
}
