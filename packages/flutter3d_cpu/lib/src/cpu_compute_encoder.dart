/// A compute pass on the software rasteriser: bindings, and dispatches run
/// in order when the pass is submitted.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_resources.dart';
import 'cpu_shader.dart';

/// Records one compute pass — `GraphicsDevice.beginComputePass`.
///
/// **Queue semantics, as a GPU's** (since 1.0.0-rc.1): a dispatch is
/// checked when it is recorded and run, with what was bound for it, when
/// the pass is [submit]ted, so a `writeBuffer` made while the pass is open
/// lands before its dispatches, as WebGPU's queue puts it. [submit] then
/// writes the pass's end timestamp.
final class CpuComputeEncoder extends ComputeEncoder {
  /// Opens a compute pass over the device's [_features], format support, clock
  /// and limits, and writes the beginning timestamp when [timestampWrites]
  /// names one.
  ///
  /// Throws when [timestampWrites] is given and the device lacks
  /// `DeviceFeature.timestampQuery`.
  CpuComputeEncoder({
    required this._features,
    required this._support,
    required this._clock,
    required this._limits,
    PassTimestampWrites? timestampWrites,
  }) : _timestamps = timestampWrites {
    if (timestampWrites != null) {
      _features.require(
        DeviceFeature.timestampQuery,
        backend: cpuBackendName,
        reason: 'this compute pass names timestamp writes',
      );
    }
    writeTimestamp(_timestamps, _timestamps?.beginningOfPassIndex, _clock);
  }

  final DeviceFeatures _features;
  final TextureFormatSupport Function(TextureFormat) _support;
  final CpuClock _clock;
  final DeviceLimits _limits;

  /// What [submit] runs, in the order it was recorded.
  final List<void Function()> _recorded = <void Function()>[];
  final PassTimestampWrites? _timestamps;
  final CpuStatistics _statistics = CpuStatistics();
  CpuOpenStatisticsQuery? _query;

  CpuComputeShader? _shader;
  final Map<String, ByteData> _storage = <String, ByteData>{};
  final Map<String, Map<String, Float32List>> _blocks =
      <String, Map<String, Float32List>>{};
  final Map<String, BoundTexture> _textures = <String, BoundTexture>{};
  final Map<String, CpuStorageTexture> _storageTextures =
      <String, CpuStorageTexture>{};

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    _shader = pipeline.backend as CpuComputeShader;
    _storage.clear();
    _blocks.clear();
    _textures.clear();
    _storageTextures.clear();
  }

  /// True for a stage that declares nothing — see [CpuStorageReader] — and
  /// for a name one declares. The range is honoured: the stage is handed
  /// exactly those bytes, still the buffer's own.
  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    checkStorageBinding(
      buffer,
      _limits,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    final range = storageRangeOf(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    if (!declaresStorage(stage, name, undeclared: true)) return false;
    _storage[name] = range;
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    checkSampler(sampler, _features);
    _textures[name] = BoundTexture(
      texture.backend as CpuTexture,
      sampler ?? SamplerDescriptor.linearRepeat,
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
    final bound = CpuStorageTexture.bind(
      texture,
      mipLevel: mipLevel,
      access: access,
      features: _features,
      support: _support(texture.format),
      backend: cpuBackendName,
    );
    if (!declaresStorage(stage, name, undeclared: true)) return false;
    _storageTextures[name] = bound;
    return true;
  }

  /// Refused — see `uniformBytesRefusal` for what would unblock it.
  @override
  bool bindUniformBytes(ShaderHandle stage, String block, ByteData bytes) =>
      throw uniformBytesRefusal();

  @override
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) {
    _blocks[block] = members;
    return true;
  }

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    final shader = _shader;
    if (shader == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    checkDispatch(_limits, x, y, z);
    final bindings = CpuComputeBindings(
      Map<String, ByteData>.of(_storage),
      <String, Map<String, Float32List>>{
        for (final MapEntry(:key, :value) in _blocks.entries)
          key: Map<String, Float32List>.of(value),
      },
      textures: Map<String, BoundTexture>.of(_textures),
      storageTextures: Map<String, CpuStorageTexture>.of(_storageTextures),
    );
    _recorded.add(() => _run(shader, bindings, x, y, z));
  }

  void _run(
    CpuComputeShader shader,
    CpuComputeBindings bindings,
    int x,
    int y,
    int z,
  ) {
    for (var gz = 0; gz < z; gz++) {
      for (var gy = 0; gy < y; gy++) {
        for (var gx = 0; gx < x; gx++) {
          shader.runWorkgroup((gx, gy, gz), bindings);
        }
      }
    }
    _statistics.add(
      PipelineStatistic.computeShaderInvocations,
      x * y * z * shader.workgroupSize.invocations,
    );
  }

  /// Reads the twelve bytes when the pass runs, as a GPU reads them, and
  /// dispatches them: an earlier dispatch of the same pass may have written
  /// them.
  @override
  void dispatchIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _features.require(DeviceFeature.indirectDispatch, backend: cpuBackendName);
    requireBufferUsage(arguments, BufferUsage.indirect, 'an indirect dispatch');
    checkUnmapped(arguments);
    final grid = rangeOf(
      arguments,
      offsetInBytes: offsetInBytes,
      sizeInBytes: 12,
    );
    final shader = _shader;
    if (shader == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    final bindings = CpuComputeBindings(
      Map<String, ByteData>.of(_storage),
      <String, Map<String, Float32List>>{
        for (final MapEntry(:key, :value) in _blocks.entries)
          key: Map<String, Float32List>.of(value),
      },
      textures: Map<String, BoundTexture>.of(_textures),
      storageTextures: Map<String, CpuStorageTexture>.of(_storageTextures),
    );
    _recorded.add(() {
      final (x, y, z) = (
        grid.getUint32(0, Endian.little),
        grid.getUint32(4, Endian.little),
        grid.getUint32(8, Endian.little),
      );
      checkDispatch(_limits, x, y, z);
      _run(shader, bindings, x, y, z);
    });
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _features.require(
      DeviceFeature.pipelineStatisticsQuery,
      backend: cpuBackendName,
    );
    if (_open) {
      throw StateError('a pipeline-statistics query is already open');
    }
    _open = true;
    final results = queryResultsOf(
      querySet,
      QueryType.pipelineStatistics,
      queryIndex,
    );
    _recorded.add(
      () => _query = CpuOpenStatisticsQuery(results, queryIndex, _statistics),
    );
  }

  /// Whether a query is open as recorded, ahead of [submit] running it.
  bool _open = false;

  @override
  void endPipelineStatisticsQuery() {
    if (!_open) {
      throw StateError('no pipeline-statistics query is open');
    }
    _open = false;
    _recorded.add(() {
      _query?.end(_statistics);
      _query = null;
    });
  }

  @override
  void submit() {
    final recorded = List<void Function()>.of(_recorded);
    _recorded.clear();
    for (final run in recorded) {
      run();
    }
    writeTimestamp(_timestamps, _timestamps?.endOfPassIndex, _clock);
  }
}
