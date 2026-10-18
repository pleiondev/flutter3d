/// Compute on WebGPU: storage buffers, pipelines, passes and reading a buffer
/// back — `H6`.
///
/// Since 1.0 a pass also binds a range of a buffer, sampled and storage
/// textures, a uniform block from laid-out bytes, and dispatches a grid a
/// buffer holds. **The textures bind only where a stage declares them**, and
/// no stage the generator writes does yet — see
/// `WebGpuComputeStage.textures` — so on the engine's own table both texture
/// binds answer false, which is the contract's answer for an undeclared name.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart' show WebGpuSampler;
import 'webgpu_compute_stage.dart';
import 'webgpu_formats.dart'
    show gpuStorageTextureAccess, gpuTextureFormat, gpuWritableBytes;
import 'webgpu_interop.dart';
import 'webgpu_resources.dart' show WebGpuFrameArena;
import 'webgpu_types.dart'
    show WebGpuQueries, WebGpuTexture, gpuSamplerLayoutEntries;

/// A storage buffer: the GPU buffer and the length it was asked for, which
/// may be less than the buffer's own four-byte-rounded size.
final class WebGpuStorage {
  /// A storage of [length] bytes held in [buffer].
  WebGpuStorage(this.buffer, this.length);

  /// The GPU buffer, its size [length] rounded up to a multiple of four.
  final GPUBuffer buffer;

  /// The size the caller asked for, in bytes.
  final int length;
}

/// A compute pipeline and the one bind group layout per group it declares.
final class WebGpuComputePipeline {
  /// A pipeline built from [shader], with its [layouts].
  WebGpuComputePipeline(this.shader, this.pipeline, this.layouts);

  /// The shader the pipeline was built from, for its bindings by name.
  final WebGpuComputeShader shader;

  /// The browser's pipeline object.
  final GPUComputePipeline pipeline;

  /// The bind group layout of each group the stage declares, by group
  /// number.
  final Map<int, GPUBindGroupLayout> layouts;

  /// The bind groups each group was set with, by the storage ranges each
  /// was made of: a dispatch binding the same ranges again — a workload's
  /// kernel every frame — sets that one rather than making another. A bind
  /// group is a call into the browser and an object for it to collect, and
  /// a water's step dispatches tens of kernels a frame. The oldest go past
  /// [_kept] a group.
  final Map<int, Map<WebGpuGroupKey, GPUBindGroup>> groups =
      <int, Map<WebGpuGroupKey, GPUBindGroup>>{};

  static const int _kept = 32;

  /// The group made of [key], or null.
  GPUBindGroup? groupFor(int group, WebGpuGroupKey key) {
    final made = groups[group];
    final found = made?.remove(key);
    if (found != null) made![key] = found;
    return found;
  }

  /// Keeps [made] as group [group]'s made of [key].
  void keep(int group, WebGpuGroupKey key, GPUBindGroup made) {
    final kept = groups[group] ??= <WebGpuGroupKey, GPUBindGroup>{};
    kept[key] = made;
    if (kept.length > _kept) kept.remove(kept.keys.first);
  }
}

/// The storage ranges a bind group is made of, compared range by range.
final class WebGpuGroupKey {
  /// A key of [ranges], its hash computed once here.
  WebGpuGroupKey(this.ranges) : hashCode = Object.hashAll(ranges);

  /// One identity per bound entry, in binding order; two keys are equal
  /// when every range is.
  final List<Object> ranges;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! WebGpuGroupKey || other.ranges.length != ranges.length) {
      return false;
    }
    for (var i = 0; i < ranges.length; i++) {
      if (other.ranges[i] != ranges[i]) return false;
    }
    return true;
  }
}

int _roundUp4(int n) => (n + 3) & ~3;

/// What the backend calls the device in a refusal.
const String _backend = 'WebGPU';

/// A pipeline for [shader], with a bind group layout per group its storage
/// buffers, uniform blocks, textures and storage textures name, every entry
/// visible to compute.
WebGpuComputePipeline webgpuCreateComputePipeline(
  GPUDevice gpu,
  WebGpuComputeShader shader,
) {
  final (:descriptor, :layouts) = _computeDescriptor(gpu, shader);
  return WebGpuComputePipeline(
    shader,
    gpu.createComputePipeline(descriptor),
    layouts,
  );
}

/// [webgpuCreateComputePipeline] through `createComputePipelineAsync`: the
/// browser compiles off the calling turn, and a pipeline it refuses rejects
/// the future instead of arriving later as a validation error.
Future<WebGpuComputePipeline> webgpuCreateComputePipelineAsync(
  GPUDevice gpu,
  WebGpuComputeShader shader,
) async {
  final (:descriptor, :layouts) = _computeDescriptor(gpu, shader);
  final pipeline = await gpu.createComputePipelineAsync(descriptor).toDart;
  return WebGpuComputePipeline(shader, pipeline, layouts);
}

({
  GPUComputePipelineDescriptor descriptor,
  Map<int, GPUBindGroupLayout> layouts,
})
_computeDescriptor(GPUDevice gpu, WebGpuComputeShader shader) {
  final stage = shader.stage;
  final entries = <int, List<GPUBindGroupLayoutEntry>>{};
  void add(int group, GPUBindGroupLayoutEntry entry) =>
      (entries[group] ??= <GPUBindGroupLayoutEntry>[]).add(entry);
  for (final s in stage.storage) {
    add(
      s.group,
      GPUBindGroupLayoutEntry.buffer(
        binding: s.binding,
        visibility: GpuShaderStage.compute,
        buffer: GPUBufferBindingLayout(
          type: s.readOnly ? 'read-only-storage' : 'storage',
        ),
      ),
    );
  }
  for (final b in stage.blocks) {
    add(
      b.group,
      GPUBindGroupLayoutEntry.buffer(
        binding: b.binding,
        visibility: GpuShaderStage.compute,
        buffer: GPUBufferBindingLayout(type: 'uniform'),
      ),
    );
  }
  for (final t in stage.textures) {
    for (final entry in gpuSamplerLayoutEntries(t, GpuShaderStage.compute)) {
      add(t.group, entry);
    }
  }
  // 1.0: a kernel's texture, read with `textureLoad` and no sampler. Any
  // float format may be loaded, filterable or not.
  for (final t in stage.loadedTextures) {
    add(
      t.group,
      GPUBindGroupLayoutEntry.texture(
        binding: t.binding,
        visibility: GpuShaderStage.compute,
        texture: GPUTextureBindingLayout(
          sampleType: 'unfilterable-float',
          viewDimension: '2d',
          multisampled: false,
        ),
      ),
    );
  }
  for (final t in stage.storageTextures) {
    add(
      t.group,
      GPUBindGroupLayoutEntry.storageTexture(
        binding: t.binding,
        visibility: GpuShaderStage.compute,
        storageTexture: GPUStorageTextureBindingLayout(
          access: gpuStorageTextureAccess(t.access),
          format: gpuTextureFormat(t.format)!,
          viewDimension: t.dimension.gpuName,
        ),
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
  return (
    descriptor: GPUComputePipelineDescriptor(
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
    layouts: layouts,
  );
}

/// [offset] and [size] bytes of [buffer] as a range a binding or an indirect
/// call may read, or a [RangeError] where the range leaves the buffer.
void webgpuCheckRange(
  StorageBuffer buffer,
  int offset,
  int size, {
  required String what,
}) {
  if (offset < 0 || size < 0 || offset + size > buffer.lengthInBytes) {
    throw RangeError(
      '$what reads $size bytes from $offset, past the '
      '${buffer.lengthInBytes} the buffer holds',
    );
  }
}

/// Refuses an indirect-argument buffer made without [BufferUsage.indirect],
/// which WebGPU would refuse as an invalid pass.
void webgpuCheckIndirect(StorageBuffer buffer, int offset, int size) {
  if (!buffer.usage.contains(BufferUsage.indirect)) {
    throw ArgumentError.value(
      buffer.usage,
      'arguments',
      'an indirect buffer is made with BufferUsage.indirect',
    );
  }
  if (offset % 4 != 0) {
    throw ArgumentError.value(
      offset,
      'offsetInBytes',
      'is not a multiple of 4',
    );
  }
  webgpuCheckRange(buffer, offset, size, what: 'an indirect call');
}

/// A compute pass: bindings gathered, each dispatch encoded as it comes, and
/// the whole pass handed to the queue at [submit].
final class WebGpuComputeEncoder extends ComputeEncoder {
  /// A pass on [_gpu], held to [_limits]. Uniform blocks are written into
  /// [_uniforms], the device's frame arena, when it is given — since
  /// 1.0.0-rc.1, rather than a buffer made and destroyed per bind.
  WebGpuComputeEncoder(
    this._gpu, {
    required this._features,
    required this._samplerFor,
    String? label,
    GPURenderPassTimestampWrites? timestampWrites,
    this._limits = DeviceLimits.webgpuDefaults,
    this._uniforms,
  }) : _encoder = _gpu.createCommandEncoder() {
    final descriptor = GPUComputePassDescriptor(
      label: label ?? 'flutter3d compute',
    );
    if (timestampWrites != null) descriptor.timestampWrites = timestampWrites;
    _pass = _encoder.beginComputePass(descriptor);
  }

  final GPUDevice _gpu;
  final DeviceFeatures _features;
  final GPUSampler Function(SamplerDescriptor) _samplerFor;
  final DeviceLimits _limits;
  final WebGpuFrameArena? _uniforms;
  final GPUCommandEncoder _encoder;
  late final GPUComputePassEncoder _pass;

  @override
  void pushDebugGroup(String label) => _pass.pushDebugGroup(label);

  @override
  void popDebugGroup() => _pass.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _pass.insertDebugMarker(label);
  WebGpuComputePipeline? _pipeline;

  /// What the next dispatch binds, by group and binding number — a buffer
  /// range, a texture view or a sampler, already in the shape a bind group
  /// entry takes.
  final Map<(int, int), GPUBindGroupEntry> _bound =
      <(int, int), GPUBindGroupEntry>{};

  /// What each binding in [_bound] is, where it is a storage range: the
  /// buffer, its offset and its size. A binding of anything else has none,
  /// and a group holding one is made afresh each dispatch.
  final Map<(int, int), Object> _keys = <(int, int), Object>{};

  /// Uniform buffers this pass made for its blocks, destroyed once the pass
  /// is submitted: WebGPU defers a destroy until the work using it is done.
  final List<GPUBuffer> _transient = <GPUBuffer>[];

  bool _submitted = false;

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    _pipeline = pipeline.backend as WebGpuComputePipeline;
    _bound.clear();
    _keys.clear();
    _pass.setPipeline(_pipeline!.pipeline);
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    final declared = pipeline.shader.stage.storage.where((s) => s.name == name);
    if (declared.isEmpty) return false;
    final s = declared.first;
    final storage = buffer.backend as WebGpuStorage;
    webgpuCheckRange(
      buffer,
      offsetInBytes,
      sizeInBytes ?? buffer.lengthInBytes - offsetInBytes,
      what: 'the storage binding "$name"',
    );
    checkStorageBinding(
      buffer,
      _limits,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    final rest = storage.buffer.size - offsetInBytes;
    // A storage binding is a whole number of words. The buffer itself was
    // rounded up to four when it was made, so rounding the range up never
    // leaves it.
    final size = sizeInBytes == null ? rest : _roundUp4(sizeInBytes);
    final bound = size > rest ? rest : size;
    _bound[(s.group, s.binding)] = GPUBindGroupEntry.buffer(
      binding: s.binding,
      resource: GPUBufferBinding(
        buffer: storage.buffer,
        offset: offsetInBytes,
        size: bound,
      ),
    );
    _keys[(s.group, s.binding)] = (storage, offsetInBytes, bound);
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    webgpuCheckSampler(_features, sampler);
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    // A kernel's texture has no sampler slot: the view alone is bound.
    for (final loaded in pipeline.shader.stage.loadedTextures) {
      if (loaded.name != name) continue;
      _keys.remove((loaded.group, loaded.binding));
      _bound[(loaded.group, loaded.binding)] = GPUBindGroupEntry.textureView(
        binding: loaded.binding,
        resource: (texture.backend as WebGpuTexture).sampledView,
      );
      return true;
    }
    final declared = pipeline.shader.stage.textures.where(
      (WebGpuSampler t) => t.name == name,
    );
    if (declared.isEmpty) return false;
    final slot = declared.first;
    final options = webgpuSamplerForSlot(slot, sampler);
    final backend = texture.backend as WebGpuTexture;
    _keys.remove((slot.group, slot.textureBinding));
    _bound[(slot.group, slot.textureBinding)] = GPUBindGroupEntry.textureView(
      binding: slot.textureBinding,
      resource: backend.sampledView,
    );
    _keys.remove((slot.group, slot.samplerBinding));
    _bound[(slot.group, slot.samplerBinding)] = GPUBindGroupEntry.sampler(
      binding: slot.samplerBinding,
      resource: _samplerFor(options),
    );
    return true;
  }

  @override
  bool bindStorageTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _features.require(
      DeviceFeature.storageTextures,
      backend: _backend,
      reason: 'storage textures are core WebGPU; this device was built without',
    );
    if (access == StorageTextureAccess.readWrite) {
      _features.require(
        DeviceFeature.readWriteStorageTextures,
        backend: _backend,
      );
    }
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    final declared = pipeline.shader.stage.storageTextures.where(
      (WebGpuStorageTextureBinding t) => t.name == name,
    );
    if (declared.isEmpty) return false;
    final slot = declared.first;
    webgpuCheckStorageTexture(
      texture,
      name: name,
      access: access,
      mipLevel: mipLevel,
      declaredAccess: slot.access,
      declaredFormat: slot.format,
    );
    _keys.remove((slot.group, slot.binding));
    _bound[(slot.group, slot.binding)] = GPUBindGroupEntry.textureView(
      binding: slot.binding,
      resource: (texture.backend as WebGpuTexture).storageView(mipLevel),
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
    _bindBlockBytes(pipeline, b.group, b.binding, ByteData.sublistView(data));
    return true;
  }

  @override
  bool bindUniformBytes(ShaderHandle stage, String block, ByteData bytes) {
    _features.require(DeviceFeature.uniformBytes, backend: _backend);
    final pipeline = _pipeline;
    if (pipeline == null) return false;
    final declared = pipeline.shader.stage.blocks.where((b) => b.name == block);
    if (declared.isEmpty) return false;
    final b = declared.first;
    if (bytes.lengthInBytes > b.sizeInBytes) {
      throw ArgumentError.value(
        bytes.lengthInBytes,
        'bytes',
        'is longer than the ${b.sizeInBytes}-byte block "$block"',
      );
    }
    // Zero-padded to the block's size, which is the binding's minimum.
    final padded = Uint8List(b.sizeInBytes)
      ..setRange(
        0,
        bytes.lengthInBytes,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    _bindBlockBytes(pipeline, b.group, b.binding, ByteData.sublistView(padded));
    return true;
  }

  void _bindBlockBytes(
    WebGpuComputePipeline pipeline,
    int group,
    int binding,
    ByteData data,
  ) {
    _keys.remove((group, binding));
    final arena = _uniforms;
    if (arena != null) {
      // The device's ring of uniforms, reset at the top of each frame: a
      // slice of one buffer, where a block bound a dispatch used to cost a
      // buffer made and destroyed.
      final slice = arena.write(data);
      _bound[(group, binding)] = GPUBindGroupEntry.buffer(
        binding: binding,
        resource: GPUBufferBinding(
          buffer: slice.buffer,
          offset: slice.offset,
          size: slice.length,
        ),
      );
      return;
    }
    final buffer = _gpu.createBuffer(
      GPUBufferDescriptor(
        size: _roundUp4(data.lengthInBytes),
        usage: GpuBufferUsage.uniform | GpuBufferUsage.copyDst,
        label: 'block $group/$binding for ${pipeline.shader.name}',
      ),
    );
    _transient.add(buffer);
    _gpu.queue.writeBuffer(buffer, 0, gpuWritableBytes(data).toJS);
    _bound[(group, binding)] = GPUBindGroupEntry.buffer(
      binding: binding,
      resource: GPUBufferBinding(
        buffer: buffer,
        offset: 0,
        size: data.lengthInBytes,
      ),
    );
  }

  /// Sets every group the bound pipeline declares from what is bound, ahead
  /// of a dispatch of either kind.
  WebGpuComputePipeline _setGroups() {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    for (final MapEntry(key: group, value: layout)
        in pipeline.layouts.entries) {
      final inGroup = <(int, int)>[
        for (final key in _bound.keys)
          if (key.$1 == group) key,
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      final keys = <Object>[for (final key in inGroup) ?_keys[key]];
      final cacheable = keys.length == inGroup.length;
      final key = cacheable ? WebGpuGroupKey(keys) : null;
      if (key != null) {
        if (pipeline.groupFor(group, key) case final kept?) {
          _pass.setBindGroup(group, kept);
          continue;
        }
      }
      final made = _gpu.createBindGroup(
        GPUBindGroupDescriptor(
          layout: layout,
          entries: <GPUBindGroupEntry>[
            for (final key in inGroup) _bound[key]!,
          ].toJS,
        ),
      );
      if (key != null) pipeline.keep(group, key, made);
      _pass.setBindGroup(group, made);
    }
    return pipeline;
  }

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    checkDispatch(_limits, x, y, z);
    _setGroups();
    _pass.dispatchWorkgroups(x, y, z);
  }

  @override
  void dispatchIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _features.require(DeviceFeature.indirectDispatch, backend: _backend);
    webgpuCheckIndirect(arguments, offsetInBytes, 12);
    _setGroups();
    _pass.dispatchWorkgroupsIndirect(
      (arguments.backend as WebGpuStorage).buffer,
      offsetInBytes,
    );
  }

  // TODO(webgpu): pipeline statistics queries — absent from the WebGPU
  // specification (the proposal was dropped before 1.0); a granted feature
  // and a `"pipeline-statistics"` query type would unblock them.
  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _features.require(
        DeviceFeature.pipelineStatisticsQuery,
        backend: _backend,
        reason: 'WebGPU has no pipeline statistics queries',
      );

  @override
  void endPipelineStatisticsQuery() => _features.require(
    DeviceFeature.pipelineStatisticsQuery,
    backend: _backend,
    reason: 'WebGPU has no pipeline statistics queries',
  );

  @override
  void submit() {
    if (_submitted) throw StateError('this pass has already been submitted');
    _submitted = true;
    _pass.end();
    _gpu.queue.submit(<GPUCommandBuffer>[_encoder.finish()].toJS);
    for (final buffer in _transient) {
      buffer.destroy();
    }
    _transient.clear();
  }
}

/// Refuses the sampler state [features] does not have, before anything looks
/// at the slot it is bound to — a refusal is the device's answer about the
/// sampler, and a slot nobody declared must not turn it into a `false`.
///
/// An axis clamped to the border is the one WebGPU refuses:
/// `GPUSamplerDescriptor` has no border, and `"clamp-to-edge"` is the only
/// clamp it offers. A border colour no axis uses is not a border.
void webgpuCheckSampler(DeviceFeatures features, SamplerDescriptor? sampler) {
  if (sampler == null || !sampler.usesExtendedState) return;
  if (sampler.clampsToBorder) {
    // TODO(webgpu): border colours — absent from the WebGPU API (no
    // `"clamp-to-border"` address mode, no border field); a future
    // specification feature adding them would unblock this.
    features.require(
      DeviceFeature.samplerBorderColor,
      backend: _backend,
      reason: 'WebGPU samplers have no border colour',
    );
  }
  // The rest by the feature each field names, as the sampler answers it.
  sampler.checkFeatures(features, backend: _backend);
}

/// The sampler a [slot] gets for [requested], or an [ArgumentError] where a
/// comparison slot is handed an ordinary sampler or the other way round —
/// the layout fixes which one the slot takes, and the browser would refuse
/// the bind group for the mismatch. Null is `SamplerDescriptor.linearRepeat`, as
/// the contract says, which only an ordinary slot can take.
SamplerDescriptor webgpuSamplerForSlot(
  WebGpuSampler slot,
  SamplerDescriptor? requested,
) {
  final options = requested ?? SamplerDescriptor.linearRepeat;
  if ((options.compare != null) != slot.comparison) {
    throw ArgumentError.value(
      options,
      'sampler',
      slot.comparison
          ? '"${slot.name}" is a comparison slot; pass SamplerOptions with a '
                'compare function'
          : '"${slot.name}" is an ordinary sampler slot and takes no compare '
                'function',
    );
  }
  return options;
}

/// The format, access, level and usage rules of a storage texture bind, as
/// [ArgumentError]s naming what disagrees. The features were asked first.
void webgpuCheckStorageTexture(
  TextureHandle texture, {
  required String name,
  required StorageTextureAccess access,
  required int mipLevel,
  required StorageTextureAccess declaredAccess,
  required TextureFormat declaredFormat,
}) {
  if (access != declaredAccess) {
    throw ArgumentError.value(
      access,
      'access',
      '"$name" is declared ${declaredAccess.name}',
    );
  }
  if (texture.format != declaredFormat) {
    throw ArgumentError.value(
      texture.format,
      'texture',
      '"$name" is declared ${declaredFormat.name}',
    );
  }
  final gpu = (texture.backend as WebGpuTexture).texture;
  if (gpu.usage & GpuTextureUsage.storageBinding == 0) {
    throw ArgumentError.value(
      texture,
      'texture',
      'was not made with TextureUsage.storage',
    );
  }
  if (mipLevel < 0 || mipLevel >= gpu.mipLevelCount) {
    throw ArgumentError.value(
      mipLevel,
      'mipLevel',
      'the texture has ${gpu.mipLevelCount} level(s)',
    );
  }
}

/// [buffer]'s bytes, once every pass submitted before this call is done with
/// it: a copy into a mappable staging buffer, a map, and a copy out — or,
/// for a buffer that is itself mappable for reading, the map alone.
Future<ByteData> webgpuReadBuffer(
  GPUDevice gpu,
  StorageBuffer buffer, {
  WebGpuStagingPool? staging,
}) async {
  if (!buffer.hostReadable) {
    throw ArgumentError.value(
      buffer,
      'buffer',
      'was not created hostReadable, so it cannot be read back',
    );
  }
  final mapped = await webgpuMapRead(
    gpu,
    buffer,
    0,
    buffer.lengthInBytes,
    staging: staging,
  );
  try {
    return ByteData.sublistView(Uint8List.fromList(mapped.bytes));
  } finally {
    mapped.release();
  }
}

/// [size] bytes of [buffer] from [offset], mapped for reading, and what
/// hands them back: the buffer's own mapping where it was made `MAP_READ`,
/// a staging copy otherwise.
Future<({Uint8List bytes, void Function() release})> webgpuMapRead(
  GPUDevice gpu,
  StorageBuffer buffer,
  int offset,
  int size, {
  WebGpuStagingPool? staging,
}) async {
  final storage = buffer.backend as WebGpuStorage;
  if (storage.buffer.usage & GpuBufferUsage.mapRead != 0) {
    // A mapped range starts on eight bytes and is a whole number of four.
    final start = offset & ~7;
    final end = _roundUp4(offset + size);
    await storage.buffer.mapAsync(GpuMapMode.read, start, end - start).toDart;
    final range = storage.buffer
        .getMappedRange(start, end - start)
        .toDart
        .asUint8List(offset - start, size);
    // A closure and not a tear-off: the web compilers refuse a tear-off of
    // an external interop member.
    return (bytes: range, release: () => storage.buffer.unmap());
  }
  final start = offset & ~3;
  final length = _roundUp4(offset + size) - start;
  final pool = staging;
  final copy =
      pool?.take(length) ??
      gpu.createBuffer(
        GPUBufferDescriptor(
          size: length < 4 ? 4 : length,
          usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
          label: 'storage readback',
        ),
      );
  void giveBack() {
    if (pool != null) {
      pool.give(copy);
    } else {
      copy.destroy();
    }
  }

  try {
    final encoder = gpu.createCommandEncoder()
      ..copyBufferToBuffer(storage.buffer, start, copy, 0, length);
    gpu.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    await copy.mapAsync(GpuMapMode.read, 0, length).toDart;
  } on Object {
    copy.destroy();
    rethrow;
  }
  final range = copy
      .getMappedRange(0, length)
      .toDart
      .asUint8List(offset - start, size);
  return (
    bytes: range,
    release: () {
      copy.unmap();
      giveBack();
    },
  );
}

/// The staging buffers a device reads back through, kept between reads
/// rather than made per read — since 1.0.0-rc.1: a simulation that reads
/// its state every frame reuses the same few. Owned by the device and
/// destroyed with it.
final class WebGpuStagingPool {
  /// A pool on [_gpu] keeping at most [keep] buffers free.
  WebGpuStagingPool(this._gpu, {this.keep = 8});

  final GPUDevice _gpu;

  /// How many free buffers it keeps; one given back past that is destroyed.
  final int keep;

  final List<GPUBuffer> _free = <GPUBuffer>[];

  /// A mappable buffer of at least [bytes]: the smallest free one that is
  /// big enough, or a new one rounded up to a power of two.
  GPUBuffer take(int bytes) {
    GPUBuffer? best;
    for (final b in _free) {
      if (b.size >= bytes && (best == null || b.size < best.size)) best = b;
    }
    if (best != null) {
      _free.remove(best);
      return best;
    }
    var size = 4096;
    while (size < bytes) {
      size *= 2;
    }
    return _gpu.createBuffer(
      GPUBufferDescriptor(
        size: size,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
        label: 'storage readback',
      ),
    );
  }

  /// [buffer] back, unmapped, for the next read.
  void give(GPUBuffer buffer) {
    if (_free.length >= keep) {
      buffer.destroy();
      return;
    }
    _free.add(buffer);
  }

  /// How many free buffers it holds, for a test.
  int get freeCount => _free.length;

  /// Destroys every free buffer.
  void dispose() {
    for (final b in _free) {
      b.destroy();
    }
    _free.clear();
  }
}

/// What `GraphicsDevice.mapBuffer` hands back.
final class WebGpuMappedBuffer extends MappedBuffer {
  /// A mapping over the host bytes `_bytes`, calling `_release` once on
  /// [unmap].
  WebGpuMappedBuffer(this._bytes, this._release);

  final Uint8List _bytes;
  final void Function() _release;
  bool _unmapped = false;

  @override
  ByteData get bytes {
    if (_unmapped) throw StateError('this range has been unmapped');
    return ByteData.sublistView(_bytes);
  }

  @override
  void unmap() {
    if (_unmapped) throw StateError('this range has already been unmapped');
    _unmapped = true;
    _release();
  }
}

/// [size] bytes of [buffer] from [offset], mapped for writing: the buffer's
/// own mapping where it was made `MAP_WRITE`, and otherwise host bytes —
/// zeroed, since nothing is read back — written through the queue at
/// [MappedBuffer.unmap].
Future<MappedBuffer> webgpuMapWrite(
  GPUDevice gpu,
  StorageBuffer buffer,
  int offset,
  int size,
) async {
  final storage = buffer.backend as WebGpuStorage;
  if (storage.buffer.usage & GpuBufferUsage.mapWrite != 0) {
    final start = offset & ~7;
    final end = _roundUp4(offset + size);
    await storage.buffer.mapAsync(GpuMapMode.write, start, end - start).toDart;
    final range = storage.buffer
        .getMappedRange(start, end - start)
        .toDart
        .asUint8List(offset - start, size);
    return WebGpuMappedBuffer(range, () => storage.buffer.unmap());
  }
  if (offset % 4 != 0) {
    throw ArgumentError.value(
      offset,
      'offsetInBytes',
      'a buffer written through the queue is written from a multiple of 4',
    );
  }
  final host = Uint8List(size);
  return WebGpuMappedBuffer(
    host,
    () => gpu.queue.writeBuffer(
      storage.buffer,
      offset,
      gpuWritableBytes(ByteData.sublistView(host)).toJS,
    ),
  );
}

/// The results of [count] queries of [set] from [first], as 64-bit counts
/// read in two halves — `getUint64` is not there when this is compiled to
/// JavaScript, and a double holds any count or difference of timestamps a
/// frame can produce exactly.
Future<List<int>> webgpuReadQueries(
  GPUDevice gpu,
  QuerySet set,
  int first,
  int count,
) async {
  if (count == 0) return const <int>[];
  final queries = set.backend as WebGpuQueries;
  final bytes = count * 8;
  final resolved = gpu.createBuffer(
    GPUBufferDescriptor(
      size: bytes,
      usage: GpuBufferUsage.queryResolve | GpuBufferUsage.copySrc,
      label: 'query results',
    ),
  );
  final staging = gpu.createBuffer(
    GPUBufferDescriptor(
      size: bytes,
      usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
      label: 'query results read',
    ),
  );
  try {
    final encoder = gpu.createCommandEncoder()
      ..resolveQuerySet(queries.set, first, count, resolved, 0)
      ..copyBufferToBuffer(resolved, 0, staging, 0, bytes);
    gpu.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
    await staging.mapAsync(GpuMapMode.read).toDart;
    final data = ByteData.sublistView(
      Uint8List.fromList(staging.getMappedRange().toDart.asUint8List()),
    );
    staging.unmap();
    return <int>[
      for (var i = 0; i < count; i++)
        (data.getUint32(i * 8 + 4, Endian.little) * 4294967296.0 +
                data.getUint32(i * 8, Endian.little))
            .toInt(),
    ];
  } finally {
    resolved.destroy();
    staging.destroy();
  }
}
