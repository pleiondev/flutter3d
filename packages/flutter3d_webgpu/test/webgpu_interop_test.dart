/// Every declaration in `webgpu_interop.dart`, put in front of a real browser.
///
/// **A misspelt dictionary member is not a compile error on the JavaScript
/// side, and that is the whole reason this file is as long as it is.** The
/// object-literal constructors make a typo in *Dart* impossible; what they
/// cannot catch is a member this API never had, spelled consistently in both
/// places. `frontface` for `frontFace` builds a pipeline, draws a picture, and
/// gets the culling wrong. So each descriptor here is handed to the browser
/// that will refuse it.
///
/// **The draws are not about drawing.** Six of them ask the same question in
/// six ways: does the parameter the spike left at zero actually reach the
/// hardware. A vertex-buffer offset, an index-buffer offset, a first index, a
/// base vertex, a first instance and a first vertex are each a silent wrong
/// picture when they are dropped — a backend packing two meshes into one
/// allocation draws the other mesh and reports nothing. Each is asked against a
/// control that comes back the *other* colour, because a test that only checked
/// "green arrived" would pass just as happily on a backend that had stopped
/// reading the parameter and happened to be pointing at green.
///
/// **A browser with no `navigator.gpu` reports rather than fails.** A runner may
/// have none, and a red line about the machine is not a finding about the code.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_webgpu/flutter3d_webgpu.dart';
import 'package:flutter3d_webgpu/src/webgpu_interop.dart';
import 'package:flutter_test/flutter_test.dart';

/// An offscreen canvas, declared here and not in the library.
///
/// The library's [GpuCanvas] wraps whatever element an embedder already has,
/// because a backend's canvas comes from a platform view and never from a
/// constructor. A test has no platform view, so it makes the one kind of canvas
/// that needs no document — which is a fact about testing and not about WebGPU,
/// and so it lives here.
@JS('OffscreenCanvas')
extension type _OffscreenCanvas._(JSObject _) implements JSObject {
  external factory _OffscreenCanvas(int width, int height);
}

/// The colour of the palette's left texel, and of every draw that read the
/// wrong end of a buffer.
const List<int> _red = <int>[255, 0, 0, 255];

/// The colour of the palette's right texel, which every draw under test is
/// supposed to reach.
const List<int> _green = <int>[0, 255, 0, 255];

const String _shaderSource = '''
struct Tint {
  colour : vec4<f32>,
};

@group(0) @binding(0) var<uniform> tint : Tint;
@group(0) @binding(1) var paletteSampler : sampler;
@group(0) @binding(2) var palette : texture_2d<f32>;

struct Varyings {
  @builtin(position) position : vec4<f32>,
  @location(0) uv : vec2<f32>,
};

@vertex
fn spikeVertex(
  @location(0) position : vec3<f32>,
  @location(1) uv : vec2<f32>,
  @location(2) shift : f32,
) -> Varyings {
  var out : Varyings;
  out.position = vec4<f32>(position, 1.0);
  out.uv = vec2<f32>(uv.x + shift, uv.y);
  return out;
}

@fragment
fn spikeFragment(in : Varyings) -> @location(0) vec4<f32> {
  return textureSample(palette, paletteSampler, in.uv) * tint.colour;
}
''';

/// Everything the draws share, built once.
final class _Harness {
  _Harness._(this.gpu, this.device);

  /// Null where this browser has no WebGPU, which is a skip and not a failure.
  static Future<_Harness?> open() async {
    final gpu = gpuNavigator.gpu;
    if (gpu == null) return null;
    final adapter = await gpu
        .requestAdapter(
          GPURequestAdapterOptions(powerPreference: 'high-performance'),
        )
        .toDart;
    if (adapter == null) return null;
    final device = await adapter
        .requestDevice(GPUDeviceDescriptor(label: 'flutter3d interop test'))
        .toDart;
    return _Harness._(gpu, device).._build();
  }

  final GPU gpu;
  final GPUDevice device;

  late final GPUShaderModule module;
  late final GPUBindGroupLayout bindings;
  late final GPUPipelineLayout pipelineLayout;
  late final GPUSampler sampler;
  late final GPUTexture palette;
  late final GPUBuffer uniforms;
  late final GPUBuffer vertices;
  late final GPUBuffer instances;
  late final GPUBuffer indices;
  late final GPUBindGroup bindGroup;
  late final GPURenderPipeline pipeline;

  /// The stride of one vertex: a `vec3` of position and a `vec2` of texture
  /// coordinate.
  static const int vertexStride = 20;

  /// Where the second tint sits in the uniform buffer, and the alignment every
  /// device so far demands of a dynamic offset.
  static const int tintStride = 256;

  void _build() {
    module = device.createShaderModule(
      GPUShaderModuleDescriptor(code: _shaderSource, label: 'palette'),
    );

    bindings = device.createBindGroupLayout(
      GPUBindGroupLayoutDescriptor(
        label: 'palette bindings',
        entries: <GPUBindGroupLayoutEntry>[
          GPUBindGroupLayoutEntry.buffer(
            binding: 0,
            visibility: GpuShaderStage.vertex | GpuShaderStage.fragment,
            buffer: GPUBufferBindingLayout(
              type: 'uniform',
              hasDynamicOffset: true,
              minBindingSize: 16,
            ),
          ),
          GPUBindGroupLayoutEntry.sampler(
            binding: 1,
            visibility: GpuShaderStage.fragment,
            sampler: GPUSamplerBindingLayout(type: 'non-filtering'),
          ),
          GPUBindGroupLayoutEntry.texture(
            binding: 2,
            visibility: GpuShaderStage.fragment,
            texture: GPUTextureBindingLayout(
              sampleType: 'float',
              viewDimension: '2d',
              multisampled: false,
            ),
          ),
        ].toJS,
      ),
    );

    pipelineLayout = device.createPipelineLayout(
      GPUPipelineLayoutDescriptor(
        label: 'palette layout',
        bindGroupLayouts: <GPUBindGroupLayout>[bindings].toJS,
      ),
    );

    sampler = device.createSampler(
      GPUSamplerDescriptor(
        addressModeU: 'clamp-to-edge',
        addressModeV: 'clamp-to-edge',
        addressModeW: 'clamp-to-edge',
        magFilter: 'nearest',
        minFilter: 'nearest',
        mipmapFilter: 'nearest',
        lodMinClamp: 0.0,
        lodMaxClamp: 0.0,
        label: 'palette sampler',
      ),
    );

    // Two texels wide and one tall: red on the left, green on the right. Every
    // draw below picks one of the two by a texture coordinate, so the colour
    // that comes back names which end of a buffer was read.
    palette = device.createTexture(
      GPUTextureDescriptor(
        size: GPUExtent3DDict(width: 2, height: 1, depthOrArrayLayers: 1),
        format: 'rgba8unorm',
        usage: GpuTextureUsage.textureBinding | GpuTextureUsage.copyDst,
        sampleCount: 1,
        mipLevelCount: 1,
        dimension: '2d',
        label: 'palette',
      ),
    );
    device.queue.writeTexture(
      GPUTexelCopyTextureInfo(
        texture: palette,
        mipLevel: 0,
        origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
        aspect: 'all',
      ),
      Uint8List.fromList(<int>[..._red, ..._green]).toJS,
      GPUTexelCopyBufferLayout(offset: 0, bytesPerRow: 8, rowsPerImage: 1),
      GPUExtent3DDict(width: 2, height: 1, depthOrArrayLayers: 1),
    );

    // White at offset zero and blue at the dynamic offset, so a draw that
    // ignored the offset comes back the palette's own colour rather than the
    // product of the two.
    uniforms = device.createBuffer(
      GPUBufferDescriptor(
        size: tintStride + 16,
        usage: GpuBufferUsage.uniform | GpuBufferUsage.copyDst,
        label: 'tints',
      ),
    );
    device.queue.writeBuffer(
      uniforms,
      0,
      Float32List.fromList(<double>[1.0, 1.0, 1.0, 1.0]).toJS,
    );
    device.queue.writeBuffer(
      uniforms,
      tintStride,
      Float32List.fromList(<double>[0.0, 0.0, 1.0, 1.0]).toJS,
    );

    // Six vertices: one full-screen triangle reading the red texel, then the
    // same triangle reading the green one.
    vertices = device.createBuffer(
      GPUBufferDescriptor(
        size: 6 * vertexStride,
        usage: GpuBufferUsage.vertex | GpuBufferUsage.copyDst,
        label: 'two triangles in one allocation',
      ),
    );
    device.queue.writeBuffer(
      vertices,
      0,
      Float32List.fromList(<double>[
        for (final u in <double>[0.25, 0.75]) ...<double>[
          -1.0, -1.0, 0.0, u, 0.5, //
          3.0, -1.0, 0.0, u, 0.5, //
          -1.0, 3.0, 0.0, u, 0.5, //
        ],
      ]).toJS,
    );

    // One instance that shifts nothing and one that shifts half the palette.
    instances = device.createBuffer(
      GPUBufferDescriptor(
        size: 8,
        usage: GpuBufferUsage.vertex | GpuBufferUsage.copyDst,
        label: 'two instances',
      ),
    );
    device.queue.writeBuffer(
      instances,
      0,
      Float32List.fromList(<double>[0.0, 0.5]).toJS,
    );

    indices = device.createBuffer(
      GPUBufferDescriptor(
        size: 12,
        usage: GpuBufferUsage.index | GpuBufferUsage.copyDst,
        label: 'six indices',
      ),
    );
    device.queue.writeBuffer(
      indices,
      0,
      Uint16List.fromList(<int>[0, 1, 2, 3, 4, 5]).toJS,
    );

    bindGroup = device.createBindGroup(
      GPUBindGroupDescriptor(
        label: 'palette',
        layout: bindings,
        entries: <GPUBindGroupEntry>[
          GPUBindGroupEntry.buffer(
            binding: 0,
            resource: GPUBufferBinding(buffer: uniforms, offset: 0, size: 16),
          ),
          GPUBindGroupEntry.sampler(binding: 1, resource: sampler),
          GPUBindGroupEntry.textureView(
            binding: 2,
            resource: palette.createView(),
          ),
        ].toJS,
      ),
    );

    pipeline = device.createRenderPipeline(
      GPURenderPipelineDescriptor.withoutDepth(
        label: 'palette',
        layout: pipelineLayout,
        vertex: vertexState,
        fragment: GPUFragmentState(
          module: module,
          entryPoint: 'spikeFragment',
          targets: <GPUColorTargetState>[
            GPUColorTargetState.opaque(
              format: 'rgba8unorm',
              writeMask: GpuColorWrite.all,
            ),
          ].toJS,
        ),
        primitive: GPUPrimitiveState(
          topology: 'triangle-list',
          cullMode: 'none',
          frontFace: 'ccw',
        ),
        multisample: GPUMultisampleState(count: 1),
      ),
    );
  }

  /// The vertex stage and the two buffers it reads, shared by every pipeline
  /// built here.
  GPUVertexState get vertexState => GPUVertexState(
    module: module,
    entryPoint: 'spikeVertex',
    buffers: <GPUVertexBufferLayout>[
      GPUVertexBufferLayout(
        arrayStride: vertexStride,
        stepMode: 'vertex',
        attributes: <GPUVertexAttribute>[
          GPUVertexAttribute(format: 'float32x3', offset: 0, shaderLocation: 0),
          GPUVertexAttribute(
            format: 'float32x2',
            offset: 12,
            shaderLocation: 1,
          ),
        ].toJS,
      ),
      GPUVertexBufferLayout(
        arrayStride: 4,
        stepMode: 'instance',
        attributes: <GPUVertexAttribute>[
          GPUVertexAttribute(format: 'float32', offset: 0, shaderLocation: 2),
        ].toJS,
      ),
    ].toJS,
  );

  GPUTexture colorTarget({
    int size = 4,
    int sampleCount = 1,
    int mipLevelCount = 1,
    int layers = 1,
  }) => device.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: size,
        height: size,
        depthOrArrayLayers: layers,
      ),
      format: 'rgba8unorm',
      usage:
          GpuTextureUsage.renderAttachment |
          GpuTextureUsage.copySrc |
          GpuTextureUsage.copyDst,
      sampleCount: sampleCount,
      mipLevelCount: mipLevelCount,
      dimension: '2d',
    ),
  );

  /// One texel of [texture], out of the level and layer named.
  ///
  /// The row stride is `paddedBytesPerRow`'s, because WebGPU will not copy into
  /// a buffer whose rows are packed tighter than 256 bytes — the same rounding
  /// the readback in a backend has to undo.
  Future<List<int>> readTexel(
    GPUTexture texture, {
    required int width,
    required int height,
    int mipLevel = 0,
    int layer = 0,
    int x = 0,
    int y = 0,
  }) async {
    final stride = paddedBytesPerRow(width);
    final staging = device.createBuffer(
      GPUBufferDescriptor(
        size: stride * height,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
      ),
    );
    final encoder = device.createCommandEncoder()
      ..copyTextureToBuffer(
        GPUTexelCopyTextureInfo(
          texture: texture,
          mipLevel: mipLevel,
          origin: GPUOrigin3DDict(x: 0, y: 0, z: layer),
          aspect: 'all',
        ),
        GPUTexelCopyBufferInfo(
          buffer: staging,
          offset: 0,
          bytesPerRow: stride,
          rowsPerImage: height,
        ),
        GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      );
    device.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    await staging.mapAsync(GpuMapMode.read).toDart;
    final mapped = staging.getMappedRange().toDart.asUint8List();
    final texel = mapped.sublist(y * stride + x * 4, y * stride + x * 4 + 4);
    staging
      ..unmap()
      ..destroy();
    return texel.toList();
  }

  /// Draws once into a fresh four-by-four target and returns its centre texel.
  ///
  /// [record] is where each test says which of the six offsets it is asking
  /// about; everything around it is the same every time.
  Future<List<int>> drawCentre(
    void Function(GPURenderPassEncoder pass) record, {
    int dynamicOffset = 0,
  }) async {
    final target = colorTarget();
    final encoder = device.createCommandEncoder();
    final pass = encoder.beginRenderPass(
      GPURenderPassDescriptor(
        label: 'one draw',
        colorAttachments: <GPURenderPassColorAttachment>[
          GPURenderPassColorAttachment(
            view: target.createView(),
            clearValue: GPUColorDict(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
            loadOp: 'clear',
            storeOp: 'store',
          ),
        ].toJS,
      ),
    )..setPipeline(pipeline);
    pass
      ..setBindGroup(0, bindGroup, <JSNumber>[dynamicOffset.toJS].toJS)
      ..setViewport(0.0, 0.0, 4.0, 4.0, 0.0, 1.0)
      ..setScissorRect(0, 0, 4, 4);
    record(pass);
    pass.end();
    device.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    final texel = await readTexel(target, width: 4, height: 4, x: 2, y: 2);
    target.destroy();
    return texel;
  }
}

void main() {
  late final _Harness? harness;

  setUpAll(() async {
    harness = await _Harness.open();
  });

  /// The harness, or a skip. Every test that touches a device begins here.
  _Harness? ready() {
    if (harness == null) {
      markTestSkipped('no WebGPU in this browser');
      return null;
    }
    return harness;
  }

  test('an adapter and a device arrive carrying what they were asked', () async {
    final gpu = gpuNavigator.gpu;
    if (gpu == null) {
      markTestSkipped('no WebGPU in this browser');
      return;
    }
    final adapter = await gpu
        .requestAdapter(
          GPURequestAdapterOptions(
            powerPreference: 'low-power',
            forceFallbackAdapter: false,
          ),
        )
        .toDart;
    expect(
      adapter,
      isNotNull,
      reason:
          'a browser with navigator.gpu and no '
          'adapter at all is a machine problem, not a binding problem',
    );

    final info = adapter!.info;
    // Every one of the four is a string on every implementation, and three of
    // them are routinely empty — a browser is allowed to say nothing about the
    // machine. So this asks that they are there, not that they say anything.
    expect(<String>[
      info.vendor,
      info.architecture,
      info.device,
      info.description,
    ], everyElement(isA<String>()));

    // The baseline every WebGPU implementation promises. A number smaller than
    // this is a `limits` that came back as the wrong object.
    final limits = adapter.limits;
    expect(limits.maxTextureDimension2D, greaterThanOrEqualTo(8192));
    expect(limits.maxTextureArrayLayers, greaterThanOrEqualTo(256));
    expect(limits.maxBindGroups, greaterThanOrEqualTo(4));
    expect(limits.maxSamplersPerShaderStage, greaterThanOrEqualTo(16));
    expect(limits.maxSampledTexturesPerShaderStage, greaterThanOrEqualTo(16));
    expect(limits.maxUniformBufferBindingSize, greaterThanOrEqualTo(65536));
    expect(limits.maxBufferSize, greaterThanOrEqualTo(268435456));
    expect(limits.maxVertexBuffers, greaterThanOrEqualTo(8));
    expect(limits.maxVertexAttributes, greaterThanOrEqualTo(16));
    expect(limits.maxColorAttachments, greaterThanOrEqualTo(4));
    expect(limits.minUniformBufferOffsetAlignment, _Harness.tintStride);

    // Whether this machine has block compression is not the point; that the
    // question can be asked at all is, because it is the only honest source of
    // an answer for `supportsTextureFormat`.
    expect(adapter.features.has(GpuFeature.textureCompressionBc), isA<bool>());

    final device = await adapter
        .requestDevice(
          GPUDeviceDescriptor(
            label: 'a device that asked for something',
            requiredFeatures: gpuStrings(const <String>[]),
            requiredLimits: gpuRequiredLimits(const <String, int>{
              'maxTextureDimension2D': 4096,
            }),
          ),
        )
        .toDart;
    expect(device.limits.maxTextureDimension2D, greaterThanOrEqualTo(4096));
    expect(device.features.has(GpuFeature.float32Filterable), isA<bool>());
    expect(device.lost, isNotNull);
    device.destroy();
  });

  test('every window into a buffer reaches the hardware', () async {
    final gpu = ready();
    if (gpu == null) return;

    // The control, and the reason the other six mean anything: with every
    // offset left at zero the draw reads the first triangle and comes back red.
    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16')
          ..drawIndexed(3),
      ),
      _red,
      reason:
          'with nothing skipped the draw must read the first triangle. If '
          'this is green the palette or the geometry is the wrong way round '
          'and every other expectation here is meaningless',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16')
          ..drawIndexed(3, 1, 3),
      ),
      _green,
      reason: 'firstIndex did not reach the draw',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16')
          ..drawIndexed(3, 1, 0, 3),
      ),
      _green,
      reason: 'baseVertex did not reach the draw',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(
            0,
            gpu.vertices,
            3 * _Harness.vertexStride,
            3 * _Harness.vertexStride,
          )
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16')
          ..drawIndexed(3),
      ),
      _green,
      reason:
          'the vertex buffer offset did not reach the draw — which is the '
          'bug that makes a backend packing two meshes into one allocation '
          'draw the other mesh and report nothing',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16', 6, 6)
          ..drawIndexed(3),
      ),
      _green,
      reason: 'the index buffer offset did not reach the draw',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..setIndexBuffer(gpu.indices, 'uint16')
          ..drawIndexed(3, 1, 0, 0, 1),
      ),
      _green,
      reason:
          'firstInstance did not reach the draw, so the second instance '
          'never shifted the texture coordinate',
    );

    expect(
      await gpu.drawCentre(
        (GPURenderPassEncoder pass) => pass
          ..setVertexBuffer(0, gpu.vertices)
          ..setVertexBuffer(1, gpu.instances)
          ..draw(3, 1, 3),
      ),
      _green,
      reason: 'firstVertex did not reach the unindexed draw',
    );
  });

  test('a dynamic offset chooses which uniform block a draw reads', () async {
    final gpu = ready();
    if (gpu == null) return;

    void record(GPURenderPassEncoder pass) => pass
      ..setVertexBuffer(0, gpu.vertices)
      ..setVertexBuffer(1, gpu.instances)
      ..setIndexBuffer(gpu.indices, 'uint16')
      ..drawIndexed(3, 1, 3);

    expect(await gpu.drawCentre(record), _green);
    // The second tint is blue, and green times blue is black — so the offset
    // was read. A dropped offset would come back green.
    expect(
      await gpu.drawCentre(record, dynamicOffset: _Harness.tintStride),
      <int>[0, 0, 0, 255],
      reason: 'the dynamic offset did not reach setBindGroup',
    );
  });

  test('a view of one level of one layer is an ordinary attachment', () async {
    final gpu = ready();
    if (gpu == null) return;

    // Four by four, two levels, two layers. Level one is two by two, and the
    // draw goes into layer one of it — the shape a cube face at a mip level
    // has, which is what `createCubeRenderTarget` asks a backend for.
    final target = gpu.colorTarget(size: 4, mipLevelCount: 2, layers: 2);
    final depth = gpu.device.createTexture(
      GPUTextureDescriptor(
        size: GPUExtent3DDict(width: 2, height: 2, depthOrArrayLayers: 1),
        format: 'depth32float',
        usage: GpuTextureUsage.renderAttachment,
        sampleCount: 1,
        mipLevelCount: 1,
        dimension: '2d',
      ),
    );
    final pipeline = gpu.device.createRenderPipeline(
      GPURenderPipelineDescriptor(
        label: 'into a level',
        layout: gpu.pipelineLayout,
        vertex: gpu.vertexState,
        fragment: GPUFragmentState(
          module: gpu.module,
          entryPoint: 'spikeFragment',
          targets: <GPUColorTargetState>[
            GPUColorTargetState.opaque(format: 'rgba8unorm'),
          ].toJS,
        ),
        primitive: GPUPrimitiveState(
          topology: 'triangle-list',
          cullMode: 'none',
          frontFace: 'ccw',
        ),
        depthStencil: GPUDepthStencilState(
          format: 'depth32float',
          depthWriteEnabled: true,
          depthCompare: 'always',
        ),
        multisample: GPUMultisampleState(count: 1),
      ),
    );

    // The neighbouring layer is filled with the red triangle first, so that a
    // baseArrayLayer nobody read would be caught: it would come back green.
    for (final (int layer, int firstIndex) in <(int, int)>[(0, 0), (1, 3)]) {
      final encoder = gpu.device.createCommandEncoder();
      final pass = encoder.beginRenderPass(
        GPURenderPassDescriptor.withDepth(
          colorAttachments: <GPURenderPassColorAttachment>[
            GPURenderPassColorAttachment(
              view: target.createView(
                GPUTextureViewDescriptor(
                  dimension: '2d',
                  aspect: 'all',
                  baseMipLevel: 1,
                  mipLevelCount: 1,
                  baseArrayLayer: layer,
                  arrayLayerCount: 1,
                  label: 'level one of layer $layer',
                ),
              ),
              clearValue: GPUColorDict(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
              loadOp: 'clear',
              storeOp: 'store',
            ),
          ].toJS,
          depthStencilAttachment: GPURenderPassDepthStencilAttachment.depthOnly(
            view: depth.createView(),
            depthClearValue: 1.0,
            depthLoadOp: 'clear',
            depthStoreOp: 'discard',
          ),
        ),
      )..setPipeline(pipeline);
      pass
        ..setBindGroup(0, gpu.bindGroup, <JSNumber>[0.toJS].toJS)
        ..setVertexBuffer(0, gpu.vertices)
        ..setVertexBuffer(1, gpu.instances)
        ..setIndexBuffer(gpu.indices, 'uint16')
        ..drawIndexed(3, 1, firstIndex)
        ..end();
      gpu.device.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    }

    expect(
      await gpu.readTexel(target, width: 2, height: 2, mipLevel: 1, layer: 1),
      _green,
      reason: 'the draw did not land in level one of layer one',
    );
    expect(
      await gpu.readTexel(target, width: 2, height: 2, mipLevel: 1),
      _red,
      reason: 'the two layers were drawn into as if they were one',
    );
    target.destroy();
    depth.destroy();
  });

  test('a multisampled pass resolves into the texture it names', () async {
    final gpu = ready();
    if (gpu == null) return;

    final multisampled = gpu.colorTarget(sampleCount: 4);
    final resolved = gpu.colorTarget();
    final depth = gpu.device.createTexture(
      GPUTextureDescriptor(
        size: GPUExtent3DDict(width: 4, height: 4, depthOrArrayLayers: 1),
        format: 'depth24plus-stencil8',
        usage: GpuTextureUsage.renderAttachment,
        sampleCount: 4,
        mipLevelCount: 1,
        dimension: '2d',
      ),
    );

    // Blending on, and a stencil that always passes: neither changes the
    // picture, and both are descriptors nothing else here hands to a browser.
    final stencil = GPUStencilFaceState(
      compare: 'always',
      failOp: 'keep',
      depthFailOp: 'keep',
      passOp: 'replace',
    );
    final pipeline = gpu.device.createRenderPipeline(
      GPURenderPipelineDescriptor(
        label: 'four samples',
        layout: gpu.pipelineLayout,
        vertex: gpu.vertexState,
        fragment: GPUFragmentState(
          module: gpu.module,
          entryPoint: 'spikeFragment',
          targets: <GPUColorTargetState>[
            GPUColorTargetState(
              format: 'rgba8unorm',
              blend: GPUBlendState(
                color: GPUBlendComponent(
                  operation: 'add',
                  srcFactor: 'src-alpha',
                  dstFactor: 'one-minus-src-alpha',
                ),
                alpha: GPUBlendComponent(
                  operation: 'add',
                  srcFactor: 'one',
                  dstFactor: 'one-minus-src-alpha',
                ),
              ),
              writeMask:
                  GpuColorWrite.red |
                  GpuColorWrite.green |
                  GpuColorWrite.blue |
                  GpuColorWrite.alpha,
            ),
          ].toJS,
        ),
        primitive: GPUPrimitiveState(
          topology: 'triangle-list',
          cullMode: 'none',
          frontFace: 'ccw',
        ),
        depthStencil: GPUDepthStencilState(
          format: 'depth24plus-stencil8',
          depthWriteEnabled: true,
          depthCompare: 'always',
          stencilFront: stencil,
          stencilBack: stencil,
          stencilReadMask: 0xFF,
          stencilWriteMask: 0xFF,
          depthBias: 0,
          depthBiasSlopeScale: 0.0,
          depthBiasClamp: 0.0,
        ),
        multisample: GPUMultisampleState(
          count: 4,
          mask: 0xFFFFFFFF,
          alphaToCoverageEnabled: false,
        ),
      ),
    );

    final encoder = gpu.device.createCommandEncoder();
    final pass = encoder.beginRenderPass(
      GPURenderPassDescriptor.withDepth(
        colorAttachments: <GPURenderPassColorAttachment>[
          GPURenderPassColorAttachment.resolving(
            view: multisampled.createView(),
            resolveTarget: resolved.createView(),
            clearValue: GPUColorDict(r: 0.0, g: 0.0, b: 0.0, a: 1.0),
            loadOp: 'clear',
            // Discarded and resolved, which is what
            // `StoreAction.multisampleResolve` translates to.
            storeOp: 'discard',
          ),
        ].toJS,
        depthStencilAttachment: GPURenderPassDepthStencilAttachment(
          view: depth.createView(),
          depthClearValue: 1.0,
          depthLoadOp: 'clear',
          depthStoreOp: 'discard',
          stencilClearValue: 0,
          stencilLoadOp: 'clear',
          stencilStoreOp: 'discard',
        ),
      ),
    )..setPipeline(pipeline);
    pass
      ..setStencilReference(1)
      ..setBindGroup(0, gpu.bindGroup, <JSNumber>[0.toJS].toJS)
      ..setVertexBuffer(0, gpu.vertices)
      ..setVertexBuffer(1, gpu.instances)
      ..setIndexBuffer(gpu.indices, 'uint16')
      ..drawIndexed(3, 1, 3)
      ..end();
    gpu.device.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);

    expect(
      await gpu.readTexel(resolved, width: 4, height: 4, x: 2, y: 2),
      _green,
      reason: 'the resolve target did not receive the pass',
    );
    multisampled.destroy();
    resolved.destroy();
    depth.destroy();
  });

  test('copies move bytes without a pass', () async {
    final gpu = ready();
    if (gpu == null) return;

    final source = gpu.colorTarget();
    final destination = gpu.colorTarget();
    final encoder = gpu.device.createCommandEncoder();
    final pass = encoder.beginRenderPass(
      GPURenderPassDescriptor(
        colorAttachments: <GPURenderPassColorAttachment>[
          GPURenderPassColorAttachment(
            view: source.createView(),
            clearValue: GPUColorDict(r: 0.0, g: 1.0, b: 0.0, a: 1.0),
            loadOp: 'clear',
            storeOp: 'store',
          ),
        ].toJS,
      ),
    )..end();
    expect(pass, isNotNull);
    encoder.copyTextureToTexture(
      GPUTexelCopyTextureInfo(
        texture: source,
        mipLevel: 0,
        origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
      ),
      GPUTexelCopyTextureInfo(
        texture: destination,
        mipLevel: 0,
        origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
      ),
      GPUExtent3DDict(width: 4, height: 4, depthOrArrayLayers: 1),
    );
    gpu.device.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    expect(await gpu.readTexel(destination, width: 4, height: 4), _green);

    // And the buffer-to-buffer half, which a staged upload uses and no draw
    // does.
    final staged = gpu.device.createBuffer(
      GPUBufferDescriptor(
        size: 8,
        usage: GpuBufferUsage.copySrc | GpuBufferUsage.copyDst,
      ),
    );
    final landed = gpu.device.createBuffer(
      GPUBufferDescriptor(
        size: 8,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
      ),
    );
    expect(staged.size, 8);
    gpu.device.queue.writeBuffer(
      staged,
      0,
      Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]).toJS,
    );
    final copier = gpu.device.createCommandEncoder()
      ..copyBufferToBuffer(staged, 4, landed, 0, 4);
    gpu.device.queue.submit(<GPUCommandBuffer>[copier.finish()].toJS);
    await landed.mapAsync(GpuMapMode.read, 0, 4).toDart;
    expect(landed.getMappedRange(0, 4).toDart.asUint8List().toList(), <int>[
      5,
      6,
      7,
      8,
    ], reason: 'the source offset of a buffer copy was dropped');
    landed
      ..unmap()
      ..destroy();
    staged.destroy();
    source.destroy();
    destination.destroy();

    // The frame's own promise, which is what `onFrameComplete` is made of.
    await gpu.device.queue.onSubmittedWorkDone().toDart;
  });

  test('a canvas takes a device and hands a texture back', () async {
    final gpu = ready();
    if (gpu == null) return;

    final context = GpuCanvas(_OffscreenCanvas(8, 8)).getContext('webgpu');
    expect(
      context,
      isNotNull,
      reason:
          'an OffscreenCanvas refused a WebGPU '
          'context in a browser that has WebGPU',
    );
    final format = gpu.gpu.getPreferredCanvasFormat();
    expect(format, anyOf('bgra8unorm', 'rgba8unorm'));
    context!.configure(
      GPUCanvasConfiguration(
        device: gpu.device,
        format: format,
        usage: GpuTextureUsage.renderAttachment | GpuTextureUsage.copyDst,
        alphaMode: 'opaque',
      ),
    );
    final frame = context.getCurrentTexture();
    expect(frame.width, 8);
    expect(frame.height, 8);
    expect(frame.depthOrArrayLayers, 1);
    expect(frame.mipLevelCount, 1);
    expect(frame.sampleCount, 1);
    expect(frame.format, format);
    context.unconfigure();
  });

  test('an error the browser catches reaches Dart', () async {
    final gpu = ready();
    if (gpu == null) return;

    // Valid work comes back with its result and nothing thrown.
    final fine = await gpuChecked(
      gpu.device,
      'a buffer',
      () => gpu.device.createBuffer(
        GPUBufferDescriptor(size: 16, usage: GpuBufferUsage.uniform),
      ),
    );
    expect(fine.size, 16);
    fine.destroy();

    // MAP_READ with MAP_WRITE is the one usage pair this API refuses outright,
    // and it is refused asynchronously — without the scope it would be a line
    // in the browser console and a test that passed.
    Object? caught;
    try {
      await gpuChecked(
        gpu.device,
        'a buffer mapped both ways',
        () => gpu.device.createBuffer(
          GPUBufferDescriptor(
            size: 16,
            usage: GpuBufferUsage.mapRead | GpuBufferUsage.mapWrite,
          ),
        ),
      );
    } on GpuDeviceError catch (error) {
      caught = error;
      expect(error.what, 'a buffer mapped both ways');
      expect(error.message, isNotEmpty);
      expect(error.toString(), contains('a buffer mapped both ways'));
    }
    expect(
      caught,
      isNotNull,
      reason:
          'the validation scope let the browser keep the complaint, which '
          'is the whole failure mode gpuChecked exists to close',
    );
  });

  test('the descriptors nothing else here draws with are still refused '
      'or accepted', () async {
    final gpu = ready();
    if (gpu == null) return;

    // A strip pipeline, which has to state the index format the pipeline will
    // be drawn with.
    final strip = await gpuChecked(
      gpu.device,
      'a strip pipeline',
      () => gpu.device.createRenderPipeline(
        GPURenderPipelineDescriptor.withoutDepth(
          layout: gpu.pipelineLayout,
          vertex: gpu.vertexState,
          fragment: GPUFragmentState(
            module: gpu.module,
            entryPoint: 'spikeFragment',
            targets: <GPUColorTargetState>[
              GPUColorTargetState.opaque(format: 'rgba8unorm'),
            ].toJS,
          ),
          primitive: GPUPrimitiveState.strip(
            topology: 'triangle-strip',
            cullMode: 'back',
            frontFace: 'ccw',
            stripIndexFormat: 'uint16',
          ),
        ),
      ),
    );
    // Built from a stated layout, and it still answers for group zero — which
    // is the call a pipeline built with `"auto"` has no alternative to.
    expect(strip.getBindGroupLayout(0), isNotNull);

    // A comparison sampler and the binding layout that will take it. Neither
    // is interchangeable with the filtering pair the harness built.
    final shadow = await gpuChecked(
      gpu.device,
      'a comparison sampler',
      () => gpu.device.createSampler(
        GPUSamplerDescriptor.comparison(
          addressModeU: 'clamp-to-edge',
          addressModeV: 'clamp-to-edge',
          addressModeW: 'clamp-to-edge',
          magFilter: 'linear',
          minFilter: 'linear',
          mipmapFilter: 'nearest',
          compare: 'less-equal',
          label: 'shadow',
        ),
      ),
    );
    final shadowBindings = await gpuChecked(
      gpu.device,
      'a comparison binding',
      () => gpu.device.createBindGroupLayout(
        GPUBindGroupLayoutDescriptor(
          entries: <GPUBindGroupLayoutEntry>[
            GPUBindGroupLayoutEntry.sampler(
              binding: 0,
              visibility: GpuShaderStage.fragment,
              sampler: GPUSamplerBindingLayout(type: 'comparison'),
            ),
          ].toJS,
        ),
      ),
    );
    await gpuChecked(
      gpu.device,
      'a comparison bind group',
      () => gpu.device.createBindGroup(
        GPUBindGroupDescriptor(
          layout: shadowBindings,
          entries: <GPUBindGroupEntry>[
            GPUBindGroupEntry.sampler(binding: 0, resource: shadow),
          ].toJS,
        ),
      ),
    );
  });

  test('a module says what it thought of the WGSL', () async {
    final gpu = ready();
    if (gpu == null) return;

    final info = await gpu.module.getCompilationInfo().toDart;
    final complaints = <String>[
      for (final message in info.messages.toDart)
        if (message.type == 'error')
          '${message.lineNum}:${message.linePos} ${message.message}',
    ];
    expect(
      complaints,
      isEmpty,
      reason:
          'the shared shader module did not compile, so every draw in this '
          'file is asking a question of a pipeline that was never built',
    );
  });

  test("the usage bits are the specification's own numbers", () {
    // Copied by hand from the IDL, because `package:web` carries them and this
    // package does not depend on it. A wrong bit is a buffer created for the
    // wrong purpose, which fails at the bind and not at the allocation.
    expect(
      <int>[
        GpuBufferUsage.mapRead,
        GpuBufferUsage.mapWrite,
        GpuBufferUsage.copySrc,
        GpuBufferUsage.copyDst,
        GpuBufferUsage.index,
        GpuBufferUsage.vertex,
        GpuBufferUsage.uniform,
        GpuBufferUsage.storage,
        GpuBufferUsage.indirect,
        GpuBufferUsage.queryResolve,
      ],
      <int>[1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
    );

    expect(
      <int>[
        GpuTextureUsage.copySrc,
        GpuTextureUsage.copyDst,
        GpuTextureUsage.textureBinding,
        GpuTextureUsage.storageBinding,
        GpuTextureUsage.renderAttachment,
      ],
      <int>[1, 2, 4, 8, 16],
    );

    expect(
      <int>[
        GpuShaderStage.vertex,
        GpuShaderStage.fragment,
        GpuShaderStage.compute,
      ],
      <int>[1, 2, 4],
    );

    expect(
      <int>[
        GpuColorWrite.red,
        GpuColorWrite.green,
        GpuColorWrite.blue,
        GpuColorWrite.alpha,
        GpuColorWrite.all,
      ],
      <int>[1, 2, 4, 8, 15],
    );

    expect(<int>[GpuMapMode.read, GpuMapMode.write], <int>[1, 2]);
  });

  test('the names asked of an adapter are spelled as the specification '
      'spells them', () {
    // A feature name this API does not know answers false rather than failing,
    // so a typo here is a backend reporting that a machine cannot sample BC7 —
    // on a machine that can.
    expect(
      <String>[
        GpuFeature.textureCompressionBc,
        GpuFeature.textureCompressionEtc2,
        GpuFeature.textureCompressionAstc,
        GpuFeature.depth32FloatStencil8,
        GpuFeature.float32Filterable,
      ],
      <String>[
        'texture-compression-bc',
        'texture-compression-etc2',
        'texture-compression-astc',
        'depth32float-stencil8',
        'float32-filterable',
      ],
    );

    expect(
      <String>[
        GpuErrorFilter.validation,
        GpuErrorFilter.outOfMemory,
        GpuErrorFilter.internal,
      ],
      <String>['validation', 'out-of-memory', 'internal'],
    );
  });
}
