/// A `GraphicsDevice` over WebGPU, far enough to draw one triangle and read it
/// back, and no further.
///
/// **Deliberately incomplete, and the incompleteness is the shape of the
/// finding.** Every member that throws says which of two things it is: a piece
/// of ordinary work a backend would do and this spike did not, or a point where
/// the contract and WebGPU do not meet — and the second kind names its entry in
/// `webgpuContractGaps`. A reader chasing "what would the fourth backend cost"
/// can read the throws.
///
/// Nothing here is a backend. It allocates no bind groups, keeps no pipeline
/// cache across passes, presents nothing to a widget and loads no bundle.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgpu_conventions.dart';
import 'webgpu_interop.dart';
import 'webgpu_spike_encoder.dart';

/// One compiled stage, as `ShaderHandle.backend` carries it here.
///
/// A module and an entry point rather than a module alone, because WGSL puts
/// every stage of a bundle in one module and names them with `@vertex` and
/// `@fragment` — so the thing a pipeline is built from is the pair, not the
/// module.
final class WebGpuSpikeStage {
  const WebGpuSpikeStage(this.module, this.entryPoint);
  final GPUShaderModule module;
  final String entryPoint;
}

/// What `createPipeline` records, since WebGPU cannot build anything yet.
///
/// **The pipeline is not built here and cannot be.** A `GPURenderPipeline`
/// declares its colour formats, its depth format, its sample count, its
/// topology, its cull mode, its winding, its depth test and its blend equation,
/// and at `createPipeline` the caller has said none of those — the first five
/// belong to a pass that has not been opened and the rest arrive as setters
/// afterwards. So this is the stage pair and the layout, and the real object is
/// looked up at the draw against a `WebGpuPipelineKey`.
///
/// The contract calls `createPipeline` expensive and tells callers to cache. On
/// this API it is free and the expense moves to the first draw of each distinct
/// state — which is not a contract change, but it does make the advice describe
/// the wrong end of the frame.
final class WebGpuSpikePipeline {
  const WebGpuSpikePipeline({
    required this.name,
    required this.vertex,
    required this.fragment,
    required this.layout,
  });

  final String name;
  final WebGpuSpikeStage vertex;
  final WebGpuSpikeStage fragment;

  /// Never null here. `GraphicsDevice.createPipeline` says a null layout means
  /// the backend works it out from the shader, and this one refuses instead —
  /// see the throw in `WebGpuSpikeDevice.createPipeline`.
  final VertexLayoutSpec layout;
}

/// A texture this device owns.
final class WebGpuSpikeTexture {
  const WebGpuSpikeTexture(this.texture);
  final GPUTexture texture;
}

/// A buffer this device owns.
final class WebGpuSpikeBuffer {
  const WebGpuSpikeBuffer(this.buffer);
  final GPUBuffer buffer;
}

/// The stages this spike carries, which are its own and not the engine's.
///
/// **The engine's bundle has no WebGPU section**, and that is the first entry of
/// `webgpuContractGaps` rather than an accident of this file: `ShaderBundle`
/// names a section per backend and has constants for two. So the spike compiles
/// its own WGSL, and `loadShaders` refuses anything handed to it by name.
final class WebGpuSpikeLibrary implements ShaderLibrary {
  WebGpuSpikeLibrary(GPUDevice device) : _stages = <String, ShaderHandle>{} {
    final module = device.createShaderModule(
      GPUShaderModuleDescriptor(code: spikeShaderSource),
    );
    _stages['SpikeVertex'] = ShaderHandle(
      backend: WebGpuSpikeStage(module, 'spikeVertex'),
      name: 'SpikeVertex',
    );
    _stages['SpikeFragment'] = ShaderHandle(
      backend: WebGpuSpikeStage(module, 'spikeFragment'),
      name: 'SpikeFragment',
    );
  }

  final Map<String, ShaderHandle> _stages;

  @override
  ShaderHandle? operator [](String name) => _stages[name];
}

/// The whole of the spike's shader code: position and colour through, nothing
/// sampled and no uniform block.
///
/// Flat and interpolated colour only, because the moment a stage declares a
/// uniform block or a sampler this spike would need a bind group, and a bind
/// group needs the group and binding numbers that WGSL has at compile time and
/// not at run time. That is the reflection entry of `webgpuContractGaps`, and it
/// is where a spike stops and a backend starts.
const String spikeShaderSource = '''
struct VertexOut {
  @builtin(position) position : vec4<f32>,
  @location(0) colour : vec4<f32>,
};

@vertex
fn spikeVertex(
  @location(0) position : vec3<f32>,
  @location(1) colour : vec4<f32>,
) -> VertexOut {
  var out : VertexOut;
  out.position = vec4<f32>(position, 1.0);
  out.colour = colour;
  return out;
}

@fragment
fn spikeFragment(in : VertexOut) -> @location(0) vec4<f32> {
  return in.colour;
}
''';

/// A device, as far as one triangle needs one.
final class WebGpuSpikeDevice implements GraphicsDevice {
  WebGpuSpikeDevice._(this.gpuDevice)
    : _library = WebGpuSpikeLibrary(gpuDevice);

  /// Asks the browser for a device, or answers null where there is no WebGPU.
  ///
  /// **Asynchronous, and that is the first thing outside this package that would
  /// have to move.** `navigator.gpu.requestAdapter()` and `adapter.requestDevice()`
  /// are both promises, so a WebGPU device cannot be built by a constructor the
  /// way the other three are. Nothing in `flutter3d_hardware` says how a device
  /// is made — the contract starts once one exists — so this costs the contract
  /// nothing and costs whatever chooses a backend an `await`.
  ///
  /// Null rather than a throw for a browser with no WebGPU: that is the ordinary
  /// case, not a failure, and a caller's move is to pick another backend.
  static Future<WebGpuSpikeDevice?> create() async {
    final gpu = gpuNavigator.gpu;
    if (gpu == null) return null;
    final adapter = await gpu.requestAdapter().toDart;
    if (adapter == null) return null;
    return WebGpuSpikeDevice._(await adapter.requestDevice().toDart);
  }

  /// The browser's device. Public because the encoder beside this one records
  /// into it, and because a spike has nothing to hide.
  final GPUDevice gpuDevice;

  final WebGpuSpikeLibrary _library;

  /// Real pipelines, keyed on everything WebGPU bakes into one.
  ///
  /// Shared across passes on purpose: the key already carries the attachment
  /// formats and the sample count, so a pipeline built for one pass is valid in
  /// the next pass that matches.
  final Map<WebGpuPipelineKey, GPURenderPipeline> pipelines =
      <WebGpuPipelineKey, GPURenderPipeline>{};

  bool _disposed = false;

  // ------------------------------------------------------- the conventions

  /// Top left, like Metal and Impeller and unlike OpenGL. WebGPU's framebuffer
  /// coordinates start at the top left corner and its render attachments are
  /// written from there, so nothing has to be turned over anywhere: an uploaded
  /// image and a rendered one are the same way up, which is the pair WebGL2 has
  /// to keep apart.
  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  /// Near at zero, far at one. The engine builds its projections for this and
  /// corrects at the boundary for a backend that says otherwise, so a WebGPU
  /// backend is the case that needs no correction.
  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d24UnormS8Uint;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  /// Four, which is the only multisample count above one WebGPU guarantees.
  @override
  int get preferredSampleCount => 4;

  @override
  bool get supportsOffscreenMsaa => true;

  /// **False, and the false is a finding rather than a limitation.**
  /// `setBlendConstant` exists and two of the four constant-reading
  /// `BlendFactor` values map straight onto `"constant"` and
  /// `"one-minus-constant"`. The other two are OpenGL's `CONSTANT_ALPHA`, which
  /// Metal and Vulkan also have and WebGPU does not, so a backend answering true
  /// would be promising four factors and able to honour two. The capability is
  /// one answer for all four, so the honest answer is the one that loses the two
  /// it could have had. See `webgpuContractGaps`.
  @override
  bool get supportsBlendColor => false;

  /// False: WebGPU has no polygon fill mode at all. A wireframe there is line
  /// primitives and an index buffer built for them, which is the renderer's
  /// decision — the same answer WebGL2 gives for the same reason.
  @override
  bool get supportsWireframe => false;

  @override
  bool get supportsStencil => true;

  @override
  bool get supportsMipmaps => true;

  @override
  bool get supportsCubeTextures => true;

  /// True. A view built with a `baseMipLevel` is an ordinary attachment here,
  /// which is the half of this that OpenGL ES refuses.
  @override
  bool get supportsRenderToMip => true;

  @override
  int get maxAnisotropy => 16;

  /// Whether WebGPU has a name for the format, asked through the one table that
  /// also does the uploads — so the answer here cannot drift from what an
  /// allocation would do.
  ///
  /// Compressed formats are gated by adapter features in WebGPU and this spike
  /// requests none, so every one of them would be a false on a real backend
  /// until the feature is asked for. That is a backend's bookkeeping and not a
  /// contract point: `supportsTextureFormat` is exactly the question for it.
  @override
  bool supportsTextureFormat(TextureFormat format) =>
      gpuTextureFormat(format) != null && !format.isCompressed;

  @override
  ShaderLibrary get shaders => _library;

  // -------------------------------------------------------------- resources

  @override
  TextureHandle createTexture(RenderTargetSpec spec) {
    final format = gpuTextureFormat(spec.format);
    if (format == null) {
      throw ArgumentError.value(
        spec.format,
        'format',
        'has no WebGPU spelling; ask supportsTextureFormat first',
      );
    }
    final texture = gpuDevice.createTexture(
      GPUTextureDescriptor(
        size: GPUExtent3DDict(
          width: spec.width,
          height: spec.height,
          depthOrArrayLayers: 1,
        ),
        format: format,
        usage:
            web.$GPUTextureUsage.RENDER_ATTACHMENT |
            web.$GPUTextureUsage.COPY_SRC |
            web.$GPUTextureUsage.TEXTURE_BINDING,
        sampleCount: spec.sampleCount,
        mipLevelCount: 1,
      ),
    );
    return TextureHandle(
      backend: WebGpuSpikeTexture(texture),
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );
  }

  @override
  void releaseTexture(TextureHandle texture) =>
      (texture.backend as WebGpuSpikeTexture).texture.destroy();

  /// A buffer of [bytes], for the use it names.
  ///
  /// `GeometryUsage` is not a hint here any more than it is on WebGL2: a WebGPU
  /// buffer declares `VERTEX` or `INDEX` at creation and cannot be bound as the
  /// other afterwards. The contract already asks for it, which is one of the
  /// places it turned out not to be describing one API.
  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final buffer = gpuDevice.createBuffer(
      GPUBufferDescriptor(
        // Rounded up to four, which `writeBuffer` requires of every size and
        // offset it is given.
        size: (bytes.lengthInBytes + 3) & ~3,
        usage:
            (usage == GeometryUsage.vertices
                ? web.$GPUBufferUsage.VERTEX
                : web.$GPUBufferUsage.INDEX) |
            web.$GPUBufferUsage.COPY_DST,
      ),
    );
    gpuDevice.queue.writeBuffer(buffer, 0, gpuWritableBytes(bytes).toJS);
    return GeometryBuffer(
      backend: WebGpuSpikeBuffer(buffer),
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      (geometry.backend as WebGpuSpikeBuffer).buffer.destroy();

  /// Records the pair. See [WebGpuSpikePipeline] for why nothing is built.
  ///
  /// **A null [layout] is refused, and that refusal is the finding.** The
  /// contract says null means the backend works the layout out from the shader,
  /// and that is what every pipeline in the engine passes. Impeller reads it
  /// from `impellerc`'s reflection and WebGL2 from `getActiveAttrib`; a
  /// `GPUShaderModule` answers no question about its own inputs, so there is
  /// nothing here to work it out from. See `webgpuContractGaps`.
  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) {
    if (layout == null) {
      throw UnimplementedError(
        'a WebGPU pipeline needs its vertex layout stated: WGSL carries '
        '@location numbers and no names, and GPUShaderModule reflects nothing, '
        'so "the backend works it out from the shader" has nothing to read. '
        'See webgpuContractGaps.',
      );
    }
    return PipelineHandle(
      backend: WebGpuSpikePipeline(
        name: '${vertex.name}+${fragment.name}',
        vertex: vertex.backend as WebGpuSpikeStage,
        fragment: fragment.backend as WebGpuSpikeStage,
        layout: layout,
      ),
      name: '${vertex.name}+${fragment.name}',
    );
  }

  // ------------------------------------------------------------ the frame

  /// Nothing to rotate. WebGPU has no per-frame allocator ring here, because
  /// this spike writes every transient buffer through the queue and lets the
  /// browser own the lifetime.
  @override
  void beginFrame() {}

  @override
  void onFrameComplete(void Function() whenDone) {
    unawaited(
      gpuDevice.queue.onSubmittedWorkDone().toDart.then((_) {
        whenDone();
      }),
    );
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      WebGpuSpikeEncoder(this, descriptor);

  // ---------------------------------------------------------------- output

  @override
  Future<ByteData?> readPixels(TextureHandle texture) => readback(texture);

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    // The contract's own refusals, decided above every backend. Called first
    // and synchronously, because a refusal that arrives as a failed future is
    // a readback that was accepted.
    final rect = readbackRegionOf(texture, region);
    return _copyBack(texture, rect);
  }

  Future<ByteData> _copyBack(TextureHandle texture, ScreenRect rect) async {
    final stride = paddedBytesPerRow(texture.width);
    final staging = gpuDevice.createBuffer(
      GPUBufferDescriptor(
        size: stride * texture.height,
        usage: web.$GPUBufferUsage.COPY_DST | web.$GPUBufferUsage.MAP_READ,
      ),
    );
    final encoder = gpuDevice.createCommandEncoder()
      ..copyTextureToBuffer(
        GPUTexelCopyTextureInfo(
          texture: (texture.backend as WebGpuSpikeTexture).texture,
        ),
        GPUTexelCopyBufferInfo(
          buffer: staging,
          bytesPerRow: stride,
          rowsPerImage: texture.height,
        ),
        GPUExtent3DDict(
          width: texture.width,
          height: texture.height,
          depthOrArrayLayers: 1,
        ),
      );
    gpuDevice.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);

    await staging.mapAsync(web.$GPUMapMode.READ).toDart;
    final mapped = staging.getMappedRange().toDart.asUint8List();
    // Repacked, because the contract promises the region's own width times four
    // per row and WebGPU insisted on 256-byte rows to fill it.
    final out = Uint8List(rect.width * rect.height * 4);
    for (var row = 0; row < rect.height; row++) {
      final from = (rect.y + row) * stride + rect.x * 4;
      out.setRange(
        row * rect.width * 4,
        (row + 1) * rect.width * 4,
        mapped,
        from,
      );
    }
    staging
      ..unmap()
      ..destroy();
    return ByteData.sublistView(out);
  }

  // ------------------------------------------------- what a spike does not do

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) => throw UnimplementedError(
    'ordinary work this spike did not do: writeTexture with a 256-byte row '
    'stride, per level. Nothing about it is a question for the contract.',
  );

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => throw UnimplementedError(
    'ordinary work this spike did not do: six array layers, in the order the '
    'contract states, written one level at a time.',
  );

  @override
  TextureHandle? createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => throw UnimplementedError(
    'ordinary work this spike did not do: a six-layer texture whose faces are '
    'attached through views. WebGPU attaches an array layer the way it '
    'attaches a mip level, so nothing here needs the contract to change.',
  );

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async {
    final bundle = ShaderBundle.decode(bytes);
    throw ShaderBundleRefused(
      name: bundle.name,
      reason:
          'it carries no WebGPU section, and there is no constant naming one: '
          'ShaderBundle has impellerSection and webglSection. See '
          'webgpuContractGaps.',
    );
  }

  /// **Not implemented, and not a contract problem either.** WebGPU draws into a
  /// canvas through `GPUCanvasContext`, and a Flutter application shows a canvas
  /// the way the WebGL2 backend already does — a platform view the browser
  /// composites. What the contract asks for is a widget, which is exactly the
  /// shape that lets a backend answer that way; asking for a `ui.Image` is what
  /// would not have worked.
  ///
  /// The one wrinkle is timing rather than typing: the canvas texture is
  /// `getCurrentTexture()` and is only valid for the task it was asked in, so
  /// presenting is a copy from the engine's target into it. That is a submit
  /// inside `present`, which the contract permits and does not mention.
  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) => throw UnimplementedError(
    'ordinary work this spike did not do: a GPUCanvasContext behind an '
    'HtmlElementView, and a copy into getCurrentTexture() per frame.',
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pipelines.clear();
    gpuDevice.destroy();
  }
}
