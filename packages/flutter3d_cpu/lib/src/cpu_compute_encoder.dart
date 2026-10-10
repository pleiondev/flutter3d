/// A compute pass on the software rasteriser: bindings, and dispatches that
/// run before they return.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_resources.dart';
import 'cpu_shader.dart';

/// Records one compute pass — `GraphicsDevice.beginComputePass`.
///
/// A dispatch runs its workgroups before it returns, which is as
/// synchronous as every draw on this backend; [submit] has nothing left to
/// flush and writes the pass's end timestamp.
final class CpuComputeEncoder extends ComputeEncoder {
  CpuComputeEncoder({
    required this._features,
    required this._support,
    required this._clock,
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
    final bindings = CpuComputeBindings(
      _storage,
      _blocks,
      textures: _textures,
      storageTextures: _storageTextures,
    );
    for (var gz = 0; gz < z; gz++) {
      for (var gy = 0; gy < y; gy++) {
        for (var gx = 0; gx < x; gx++) {
          shader.runWorkgroup((gx, gy, gz), bindings);
        }
      }
    }
    final (sx, sy, sz) = shader.workgroupSize;
    _statistics.add(
      PipelineStatistic.computeShaderInvocations,
      x * y * z * sx * sy * sz,
    );
  }

  /// Reads the twelve bytes and dispatches them: nothing here waits for a
  /// GPU to have written them, because the pass that did ran to its end
  /// before this one opened.
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
    dispatch(
      grid.getUint32(0, Endian.little),
      grid.getUint32(4, Endian.little),
      grid.getUint32(8, Endian.little),
    );
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _features.require(
      DeviceFeature.pipelineStatisticsQuery,
      backend: cpuBackendName,
    );
    if (_query != null) {
      throw StateError('a pipeline-statistics query is already open');
    }
    _query = CpuOpenStatisticsQuery(
      queryResultsOf(querySet, QueryType.pipelineStatistics, queryIndex),
      queryIndex,
      _statistics,
    );
  }

  @override
  void endPipelineStatisticsQuery() {
    final query = _query;
    if (query == null) {
      throw StateError('no pipeline-statistics query is open');
    }
    query.end(_statistics);
    _query = null;
  }

  @override
  void submit() =>
      writeTimestamp(_timestamps, _timestamps?.endOfPassIndex, _clock);
}
