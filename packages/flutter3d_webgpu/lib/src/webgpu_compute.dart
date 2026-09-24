/// Compute on WebGPU: storage buffers, pipelines, passes and reading a buffer
/// back — `H6`.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_compute_stage.dart';
import 'webgpu_formats.dart' show gpuWritableBytes;
import 'webgpu_interop.dart';

/// A storage buffer: the GPU buffer and the length it was asked for, which
/// may be less than the buffer's own four-byte-rounded size.
final class WebGpuStorage {
  WebGpuStorage(this.buffer, this.length);

  final GPUBuffer buffer;
  final int length;
}

/// A compute pipeline and the one bind group layout per group it declares.
final class WebGpuComputePipeline {
  WebGpuComputePipeline(this.shader, this.pipeline, this.layouts);

  final WebGpuComputeShader shader;
  final GPUComputePipeline pipeline;
  final Map<int, GPUBindGroupLayout> layouts;
}

int _roundUp4(int n) => (n + 3) & ~3;

/// A buffer holding [bytes], usable as storage and as either end of a copy.
StorageBuffer webgpuCreateStorageBuffer(
  GPUDevice gpu,
  ByteData bytes, {
  required bool hostReadable,
}) {
  final size = _roundUp4(bytes.lengthInBytes < 4 ? 4 : bytes.lengthInBytes);
  final buffer = gpu.createBuffer(
    GPUBufferDescriptor(
      size: size,
      usage:
          GpuBufferUsage.storage |
          GpuBufferUsage.copyDst |
          GpuBufferUsage.copySrc,
      label: 'storage ${bytes.lengthInBytes}',
    ),
  );
  if (bytes.lengthInBytes > 0) {
    final padded = Uint8List(size)
      ..setRange(
        0,
        bytes.lengthInBytes,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    gpu.queue.writeBuffer(
      buffer,
      0,
      gpuWritableBytes(ByteData.sublistView(padded)).toJS,
    );
  }
  return StorageBuffer(
    backend: WebGpuStorage(buffer, bytes.lengthInBytes),
    lengthInBytes: bytes.lengthInBytes,
    hostReadable: hostReadable,
  );
}

/// A pipeline for [shader], with a bind group layout per group its storage
/// buffers and uniform blocks name, every entry visible to compute.
WebGpuComputePipeline webgpuCreateComputePipeline(
  GPUDevice gpu,
  WebGpuComputeShader shader,
) {
  final entries = <int, List<GPUBindGroupLayoutEntry>>{};
  for (final s in shader.stage.storage) {
    (entries[s.group] ??= <GPUBindGroupLayoutEntry>[]).add(
      GPUBindGroupLayoutEntry.buffer(
        binding: s.binding,
        visibility: GpuShaderStage.compute,
        buffer: GPUBufferBindingLayout(
          type: s.readOnly ? 'read-only-storage' : 'storage',
        ),
      ),
    );
  }
  for (final b in shader.stage.blocks) {
    (entries[b.group] ??= <GPUBindGroupLayoutEntry>[]).add(
      GPUBindGroupLayoutEntry.buffer(
        binding: b.binding,
        visibility: GpuShaderStage.compute,
        buffer: GPUBufferBindingLayout(type: 'uniform'),
      ),
    );
  }
  final groups = entries.keys.isEmpty
      ? 0
      : entries.keys.reduce((a, b) => a > b ? a : b) + 1;
  final layouts = <int, GPUBindGroupLayout>{
    for (var g = 0; g < groups; g++)
      g: gpu.createBindGroupLayout(
        GPUBindGroupLayoutDescriptor(
          entries: (entries[g] ?? <GPUBindGroupLayoutEntry>[]).toJS,
          label: '${shader.name} group $g',
        ),
      ),
  };
  final pipeline = gpu.createComputePipeline(
    GPUComputePipelineDescriptor(
      layout: gpu.createPipelineLayout(
        GPUPipelineLayoutDescriptor(
          bindGroupLayouts: <GPUBindGroupLayout>[
            for (var g = 0; g < groups; g++) layouts[g]!,
          ].toJS,
          label: shader.name,
        ),
      ),
      compute: GPUProgrammableStage(
        module: shader.module as GPUShaderModule,
        entryPoint: 'main',
      ),
      label: shader.name,
    ),
  );
  return WebGpuComputePipeline(shader, pipeline, layouts);
}

/// A compute pass: bindings gathered, each dispatch encoded as it comes, and
/// the whole pass handed to the queue at [submit].
final class WebGpuComputeEncoder implements ComputeEncoder {
  WebGpuComputeEncoder(this._gpu, {String? label})
    : _encoder = _gpu.createCommandEncoder() {
    _pass = _encoder.beginComputePass(
      GPUComputePassDescriptor(label: label ?? 'flutter3d compute'),
    );
  }

  final GPUDevice _gpu;
  final GPUCommandEncoder _encoder;
  late final GPUComputePassEncoder _pass;
  WebGpuComputePipeline? _pipeline;
  final Map<(int, int), GPUBufferBinding> _bound =
      <(int, int), GPUBufferBinding>{};

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    _pipeline = pipeline.backend as WebGpuComputePipeline;
    _bound.clear();
    _pass.setPipeline(_pipeline!.pipeline);
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer,
  ) {
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    final declared = pipeline.shader.stage.storage.where((s) => s.name == name);
    if (declared.isEmpty) return false;
    final s = declared.first;
    final storage = buffer.backend as WebGpuStorage;
    _bound[(s.group, s.binding)] = GPUBufferBinding(
      buffer: storage.buffer,
      offset: 0,
      size: storage.buffer.size,
    );
    return true;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) {
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    final declared = pipeline.shader.stage.blocks.where((b) => b.name == block);
    if (declared.isEmpty) return false;
    final b = declared.first;
    final data = Float32List(b.sizeInBytes ~/ 4);
    members.forEach((name, values) {
      final member = b.members.where((m) => m.name == name);
      if (member.isEmpty) {
        throw StateError(
          'uniform block "$block" has no member "$name" in compute stage '
          '"${pipeline.shader.name}"',
        );
      }
      data.setRange(
        member.first.offsetInBytes ~/ 4,
        member.first.offsetInBytes ~/ 4 + values.length,
        values,
      );
    });
    final buffer = _gpu.createBuffer(
      GPUBufferDescriptor(
        size: b.sizeInBytes,
        usage: GpuBufferUsage.uniform | GpuBufferUsage.copyDst,
        label: '$block for ${pipeline.shader.name}',
      ),
    );
    _gpu.queue.writeBuffer(
      buffer,
      0,
      gpuWritableBytes(ByteData.sublistView(data)).toJS,
    );
    _bound[(b.group, b.binding)] = GPUBufferBinding(
      buffer: buffer,
      offset: 0,
      size: b.sizeInBytes,
    );
    return true;
  }

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    for (final MapEntry(key: group, value: layout)
        in pipeline.layouts.entries) {
      _pass.setBindGroup(
        group,
        _gpu.createBindGroup(
          GPUBindGroupDescriptor(
            layout: layout,
            entries: <GPUBindGroupEntry>[
              for (final MapEntry(key: (g, binding), value: resource)
                  in _bound.entries)
                if (g == group)
                  GPUBindGroupEntry.buffer(
                    binding: binding,
                    resource: resource,
                  ),
            ].toJS,
          ),
        ),
      );
    }
    _pass.dispatchWorkgroups(x, y, z);
  }

  @override
  void submit() {
    _pass.end();
    _gpu.queue.submit(<GPUCommandBuffer>[_encoder.finish()].toJS);
  }
}

/// [buffer]'s bytes, once every pass submitted before this call is done with
/// it: a copy into a mappable staging buffer, a map, and a copy out.
Future<ByteData> webgpuReadBuffer(GPUDevice gpu, StorageBuffer buffer) async {
  if (!buffer.hostReadable) {
    throw ArgumentError.value(
      buffer,
      'buffer',
      'was not created hostReadable, so it cannot be read back',
    );
  }
  final storage = buffer.backend as WebGpuStorage;
  final size = storage.buffer.size;
  final staging = gpu.createBuffer(
    GPUBufferDescriptor(
      size: size,
      usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
      label: 'storage readback',
    ),
  );
  try {
    final encoder = gpu.createCommandEncoder()
      ..copyBufferToBuffer(storage.buffer, 0, staging, 0, size);
    gpu.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    await staging.mapAsync(GpuMapMode.read).toDart;
    final mapped = staging.getMappedRange().toDart.asUint8List();
    final out = Uint8List.fromList(mapped.sublist(0, storage.length));
    staging.unmap();
    return ByteData.sublistView(out);
  } finally {
    staging.destroy();
  }
}
