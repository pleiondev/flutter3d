/// The flutter_gpu side of [GraphicsDevice] and [CommandEncoder].
///
/// Everything that used to reach `gpu.gpuContext` from the renderer, its nodes
/// and its contributors is here, behind an object that arrives as an argument.
/// This is the file a second backend is written *beside*, not inside.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

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
  ///
  /// **A static method rather than a factory constructor**, because loading the
  /// bundle became asynchronous in flutter_gpu 3.47 and a factory constructor
  /// cannot be. The name is kept so every call site reads the same with an
  /// `await` in front of it.
  /// [extraBundles] are the application's own compiled bundles, searched before
  /// the engine's — see [_GpuShaderLibrary]. Each is loaded the same way and
  /// each has to exist: a bundle named and not found is a stage that will come
  /// back null at the first draw, which on this backend is a pipeline built
  /// from nothing.
  static Future<GpuRenderBackend> create({
    String bundleAsset = defaultBundleAsset,
    List<String> extraBundles = const <String>[],
  }) async {
    final library = await gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw StateError('Failed to load the shader bundle: $bundleAsset');
    }
    final extra = <gpu.ShaderLibrary>[];
    for (final asset in extraBundles) {
      final loaded = await gpu.ShaderLibrary.fromAsset(asset);
      if (loaded == null) {
        // Thrown rather than skipped, and named. The failure this avoids is an
        // application whose effect silently falls back to the engine's stage of
        // the same name, or to nothing — both of which look like the effect
        // being wrong rather than the bundle being absent.
        throw StateError('Failed to load an extra shader bundle: $asset');
      }
      extra.add(loaded);
    }
    return GpuRenderBackend._(
      _GpuShaderLibrary(library, extra),
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
  // Through `gpu_texture.dart`, which keeps the first answer — see the note
  // there about a context that stops reporting one.
  TextureFormat get defaultColorFormat => defaultColorFormatOfContext;

  @override
  TextureFormat get defaultDepthStencilFormat =>
      gpu.gpuContext.defaultDepthStencilFormat.toEngine();

  @override
  // Impeller runs on Metal and Vulkan conventions.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
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
  bool get supportsMipmaps => gpu.gpuContext.doesSupportManuallyMippedTextures;

  /// Probed once, because flutter_gpu reports no capability for it.
  ///
  /// Every other `supports` here answers from `gpuContext`; there is no
  /// `doesSupportCubeTextures`. Allocating a one-by-one cube is the cheapest
  /// question that gets a real answer from the driver, and the alternative —
  /// returning a constant true — is a claim about every device this ever runs
  /// on, made by someone who tested one.
  @override
  bool get supportsCubeTextures => _cubesWork ??= _probeCubes();

  bool? _cubesWork;

  bool _probeCubes() {
    try {
      gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        textureType: gpu.TextureType.textureCube,
        enableRenderTargetUsage: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
  }) {
    // Six, in the order the interface documents: +X, −X, +Y, −Y, +Z, −Z. A
    // shorter list is a caller bug rather than a device one, and refusing it
    // here is what stops five faces and one of whatever the allocation happened
    // to contain.
    if (faces.length != 6) return null;
    if (!supportsCubeTextures) return null;

    final texture = createGpuTexture(
      StorageMode.hostVisible,
      size,
      size,
      format: format,
      type: TextureType.textureCube,
      // Nothing renders into a face: `ColorTarget` carries no slice, so a cube
      // can only ever be filled from the host. Asking for render-target usage
      // would be asking for an allocation nothing can use.
      enableRenderTargetUsage: false,
    );

    final expected = texture.gpuTexture.getBaseMipLevelSizeInBytes();
    for (final face in faces) {
      if (face.lengthInBytes != expected) return null;
    }
    for (var i = 0; i < 6; i++) {
      texture.gpuTexture.overwrite(faces[i], slice: i);
    }
    return texture;
  }

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
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) =>
      PipelineHandle(
        backend: gpu.gpuContext.createRenderPipeline(
          vertex.backend as gpu.Shader,
          fragment.backend as gpu.Shader,
          // Null is passed through rather than replaced with a layout derived
          // from the shader. flutter_gpu does that derivation itself, and doing
          // it here as well would be a second answer to the question the
          // reflection already answers.
          vertexLayout: layout?.toGpu(),
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
    List<ByteData>? mipLevels,
  }) {
    final texture = createGpuTexture(
      // Host-visible, because these bytes come from the CPU. That is a
      // consequence of *how the texture is filled* rather than of what it is
      // for, which is why it is not a parameter above.
      //
      // This used to also ask for origin-at-the-bottom, via a
      // `TextureCoordinateSystem` flutter_gpu deleted in 3.47. It never had an
      // effect worth the line: the setting was read by the path that turns a
      // texture into a `ui.Image`, not by a shader sampling one, and the two
      // backends that have no such concept have always drawn these textures
      // the same way up — `normal-mapping`, a grid of tiles where a vertical
      // flip could not hide, sits at 1.1% between them.
      StorageMode.hostVisible,
      width,
      height,
      format: format,
      // One more than the levels below it. flutter_gpu clamps its own
      // allocation at `fullMipCount`, which stops one short of one-by-one, so a
      // longer chain than the device will hold is trimmed rather than refused —
      // and the trimming happens there, where the limit is known.
      mipLevelCount: mipLevels == null ? 1 : mipLevels.length + 1,
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
    if (mipLevels != null) {
      // Level by level, and only as far as the texture actually goes: asking
      // to write a level it does not have throws, and a chain longer than
      // `fullMipCount` is the ordinary case rather than a mistake.
      final levels = texture.gpuTexture.mipLevelCount;
      for (var i = 0; i < mipLevels.length && i + 1 < levels; i++) {
        texture.gpuTexture.overwrite(mipLevels[i], mipLevel: i + 1);
      }
    }
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
/// The engine's bundle, and any an application brought with it.
///
/// The application's are searched **first**, which is the only ordering that
/// makes them useful: a plugin shipping its own `Composite` is saying it wants
/// that one, and a lookup that found the engine's first would silently ignore
/// the file the author compiled. It is also the ordering that can go wrong
/// quietly, so it is stated here rather than left to the loop.
///
/// Why this exists at all: shaders on this backend are compiled ahead of time
/// into a bundle asset. The software rasteriser takes a Dart object and WebGL
/// takes GLSL at runtime, so on both an application can simply hand its stage
/// over — and on Impeller it could not, at all, which made "write your own post
/// effect" a thing that worked on two backends out of three.
final class _GpuShaderLibrary implements ShaderLibrary {
  _GpuShaderLibrary(this._library, [this._extra = const <gpu.ShaderLibrary>[]]);

  final gpu.ShaderLibrary _library;
  final List<gpu.ShaderLibrary> _extra;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () {
        for (final library in _extra) {
          final shader = library[name];
          if (shader != null) return ShaderHandle(backend: shader, name: name);
        }
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

  /// **`false` does not work, and the reason is not here.**
  ///
  /// **Fixed upstream, and this note is kept because what it says was true.**
  /// Until recently `flutter_gpu`'s native setter ignored its argument and
  /// wrote the literal `true`, so the call could only ever switch depth writes
  /// *on*. As of the SDK this repository builds with (3.47.0, pinned in
  /// `mise.toml`) it passes the flag through:
  ///
  /// ```cpp
  /// // bin/cache/pkg/flutter_gpu/render_pass.cc:560
  /// void InternalFlutterGpu_RenderPass_SetDepthWriteEnable(
  ///     flutter::gpu::RenderPass* wrapper,
  ///     bool enable) {
  ///   auto& depth = wrapper->GetDepthAttachmentDescriptor();
  ///   depth.depth_write_enabled = enable;
  /// }
  /// ```
  ///
  /// Worth knowing rather than deleting, for two reasons. It is the whole
  /// argument for `PassState`'s fields being optional — a redundant
  /// `setDepthWrite(false)` flipped behaviour on two backends out of three
  /// while this bug was live — and it is what a backdrop rests on:
  /// `Material.depthWrite` is a promise this backend could not keep until now.
  ///
  /// **Settled on a machine with a GPU, and the note it replaces was wrong.**
  /// `particle-stack` used to be recorded deliberately showing the broken
  /// picture — eight additive particles at one point drawing as one, a burst
  /// about three per cent dim — and this docstring said so. Checked directly:
  /// the recorded frame shows the stack as a blown-out core with a warm halo,
  /// which is eight particles accumulating, and the cross-backend budget puts
  /// it 0.431% from the software rasteriser, the same noise floor every other
  /// scene sits at. The rasteriser honours `depthWrite` in its own code, so
  /// agreement to that tolerance is the flag arriving here too. Nothing is
  /// pending.
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

  /// How many indices the last index bind described.
  ///
  /// flutter_gpu 3.47 moved the counts off the binds and onto the draw. The HAL
  /// keeps them on the binds — that is where the other two backends put them,
  /// and where the count is actually known — so this remembers the one the draw
  /// will need. Zero means nothing has been bound, which [draw] treats as
  /// nothing to do rather than as an error: the same thing `flutter_gpu` did
  /// when the count travelled with the binding.
  int _indexCount = 0;

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount,
          {int slot = 0}) =>
      _pass.bindVertexBuffer(_view(buffer), slot: slot);

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _pass.bindVertexBuffer(_host.emplace(bytes), slot: slot);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _pass.bindIndexBuffer(_view(buffer), type.toGpu());
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _pass.bindIndexBuffer(_host.emplace(bytes), type.toGpu());
    _indexCount = indexCount;
  }

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
  void clearBindings() {
    _pass.clearBindings();
    // The count is a binding like any other. Leaving it behind would let a
    // draw after a `clearBindings` inherit the previous mesh's index count,
    // which is the kind of state leak that draws a plausible wrong picture.
    _indexCount = 0;
  }

  @override
  void draw({int instanceCount = 1}) {
    if (_indexCount == 0 || instanceCount <= 0) return;
    _pass.drawIndexed(_indexCount, instanceCount: instanceCount);
  }

  @override
  void submit() => _buffer.submit();

  static gpu.BufferView _view(GeometryBuffer buffer) => gpu.BufferView(
        buffer.backend as gpu.DeviceBuffer,
        offsetInBytes: buffer.offsetInBytes,
        lengthInBytes: buffer.lengthInBytes,
      );
}
