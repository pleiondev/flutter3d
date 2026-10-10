/// What the passes of this backend share about buffers and queries: the
/// query results, the clock timestamps are read from, which buffers are
/// mapped, and the checks every use of a buffer makes.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapability;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_shader.dart';

/// The name every refusal on this backend gives it.
const String cpuBackendName = 'the software rasteriser';

/// Why there is no wireframe here — the reason every refusal of
/// `PolygonMode.line` gives.
///
/// Line *primitives* are drawn — debug geometry arrives as those.
/// Wireframe is a different request: it asks for triangles to be drawn as
/// their edges, which means clipping and joining edges this rasteriser has
/// no path for. Answering yes and filling them instead would be the silent
/// substitution the contract exists to forbid.
const String wireframeRefusal =
    'it draws line primitives but has no path that draws a triangle as its '
    'edges, and filling the triangles instead would be a picture nobody '
    'asked for';

/// The refusal of uniform blocks from laid-out bytes, on every encoder.
// TODO(cpu): uniform blocks from bytes — a Dart stage reads its members by
// name, so bytes would have to be split into named members first, which
// needs the block's layout; the `ShaderHandle.layouts` table compiled stages
// carry would unblock it once every stage here is held to one.
UnsupportedCapability uniformBytesRefusal() => UnsupportedCapability(
  DeviceFeature.uniformBytes,
  backend: cpuBackendName,
  reason:
      'a Dart stage reads uniform members by name, and laid-out bytes carry '
      'no names',
);

/// A query set's results, as `QuerySet.backend` holds them: one integer per
/// query, five per pipeline-statistics query.
final class CpuQueryResults {
  CpuQueryResults(QueryType type, int count)
    : values = List<int>.filled(
        type == QueryType.pipelineStatistics
            ? count * PipelineStatistic.values.length
            : count,
        0,
      );

  final List<int> values;
}

/// The results [querySet] keeps, after checking it is of [type] and that
/// [index] is one of its queries.
CpuQueryResults queryResultsOf(QuerySet querySet, QueryType type, int index) {
  if (querySet.type != type) {
    throw ArgumentError.value(
      querySet,
      'querySet',
      'is a ${querySet.type.name} set where a ${type.name} set is needed',
    );
  }
  if (index < 0 || index >= querySet.count) {
    throw RangeError.range(index, 0, querySet.count - 1, 'queryIndex');
  }
  return querySet.backend as CpuQueryResults;
}

/// The device's clock: nanoseconds since it was made.
///
/// **The rasteriser is the device**, so the time a pass takes on it is the
/// time the calling thread spends between opening the pass and submitting
/// it — every draw runs as it is recorded. That includes whatever the
/// caller did between two draws, which on a GPU would not be in the pass;
/// it is the one way this clock is not a GPU's, and it is said here rather
/// than hidden.
final class CpuClock {
  final Stopwatch _watch = Stopwatch()..start();

  int get nanoseconds => (_watch.elapsedTicks / _watch.frequency * 1e9).round();
}

/// Writes the timestamp [writes] asks for at [index] (beginning or end).
void writeTimestamp(PassTimestampWrites? writes, int? index, CpuClock clock) {
  if (writes == null || index == null) return;
  queryResultsOf(writes.querySet, QueryType.timestamp, index).values[index] =
      clock.nanoseconds;
}

/// Which buffers are mapped right now, and how — `GraphicsDevice.mapBuffer`.
///
/// An [Expando] rather than a field, because the buffer is the contract's
/// `StorageBuffer` and its backend object is the bytes themselves.
final Expando<MapMode> mappedBuffers = Expando<MapMode>('mapped');

/// Throws a [StateError] when [buffer] is mapped: a mapped buffer is the
/// host's until it is unmapped, and no pass may touch it.
void checkUnmapped(StorageBuffer buffer) {
  final mode = mappedBuffers[buffer];
  if (mode == null) return;
  throw StateError(
    'a buffer mapped for ${mode.name} is used by a pass. Unmap it first: '
    'while mapped, it belongs to the host.',
  );
}

/// The bytes a [StorageBuffer] on this device holds.
ByteData bytesOf(StorageBuffer buffer) => buffer.backend as ByteData;

/// The view of [buffer] from [offsetInBytes] for [sizeInBytes] (to the end
/// by default), after checking it lies inside — a [RangeError] otherwise —
/// and starts on a multiple of [alignment].
ByteData rangeOf(
  StorageBuffer buffer, {
  int offsetInBytes = 0,
  int? sizeInBytes,
  int alignment = 4,
}) {
  final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
  if (offsetInBytes < 0 ||
      size < 0 ||
      offsetInBytes + size > buffer.lengthInBytes) {
    throw RangeError(
      'a range of $size bytes from $offsetInBytes does not lie inside a '
      '${buffer.lengthInBytes}-byte buffer',
    );
  }
  if (offsetInBytes % alignment != 0) {
    throw ArgumentError.value(
      offsetInBytes,
      'offsetInBytes',
      'must be a multiple of $alignment',
    );
  }
  final bytes = bytesOf(buffer);
  return ByteData.sublistView(bytes, offsetInBytes, offsetInBytes + size);
}

/// Throws an [ArgumentError] unless [buffer] was made for [usage].
void requireBufferUsage(StorageBuffer buffer, BufferUsage usage, String why) {
  if (buffer.usage.contains(usage)) return;
  throw ArgumentError.value(
    buffer.usage,
    'buffer.usage',
    'lacks $usage, which $why needs',
  );
}

/// Throws an [ArgumentError] unless [texture] was made for [usage].
void requireTextureUsage(
  TextureHandle texture,
  TextureUsage usage,
  String why,
) {
  if (texture.usage.contains(usage)) return;
  throw ArgumentError.value(
    texture.usage,
    'texture.usage',
    'lacks $usage, which $why needs',
  );
}

/// The five 32-bit words of one indexed indirect draw at [offsetInBytes] of
/// [arguments], checked: an indirect buffer, unmapped, the twenty bytes
/// inside it.
({
  int indexCount,
  int instanceCount,
  int firstIndex,
  int baseVertex,
  int firstInstance,
})
readIndirectDraw(StorageBuffer arguments, int offsetInBytes) {
  requireBufferUsage(arguments, BufferUsage.indirect, 'an indirect draw');
  checkUnmapped(arguments);
  final words = rangeOf(
    arguments,
    offsetInBytes: offsetInBytes,
    sizeInBytes: 20,
  );
  return (
    indexCount: words.getUint32(0, Endian.little),
    instanceCount: words.getUint32(4, Endian.little),
    firstIndex: words.getUint32(8, Endian.little),
    baseVertex: words.getInt32(12, Endian.little),
    firstInstance: words.getUint32(16, Endian.little),
  );
}

/// Refuses a sampler whose extended state names a feature [features] lacks:
/// a comparison, a level-of-detail clamp, a border colour.
void checkSampler(SamplerDescriptor? sampler, DeviceFeatures features) {
  if (sampler == null || !sampler.usesExtendedState) return;
  if (sampler.compare != null) {
    features.require(
      DeviceFeature.samplerCompare,
      backend: cpuBackendName,
      reason: 'the sampler names a compare function',
    );
  }
  if (sampler.lodMinClamp != 0 || sampler.lodMaxClamp != 32) {
    features.require(
      DeviceFeature.samplerLodClamp,
      backend: cpuBackendName,
      reason: 'the sampler clamps its level of detail',
    );
  }
  if (sampler.borderColor != null) {
    features.require(
      DeviceFeature.samplerBorderColor,
      backend: cpuBackendName,
      reason: 'the sampler names a border colour',
    );
  }
}

/// Refuses a blend [state] for [attachment] that needs a feature [features]
/// lacks — the constant, min and max, a dual-source factor — or that names
/// a dual-source factor for an attachment other than zero, which has no
/// second output to read.
void checkBlend(BlendState state, int attachment, DeviceFeatures features) {
  if (state.usesBlendColor) {
    features.require(
      DeviceFeature.blendConstant,
      backend: cpuBackendName,
      reason: 'the blend state reads the blend constant',
    );
  }
  if (state.usesMinMax) {
    features.require(
      DeviceFeature.minMaxBlend,
      backend: cpuBackendName,
      reason: 'the blend state names min or max',
    );
  }
  if (state.usesDualSource) {
    features.require(
      DeviceFeature.dualSourceBlending,
      backend: cpuBackendName,
      reason: 'the blend state reads a second fragment output',
    );
    if (attachment != 0) {
      throw ArgumentError.value(
        attachment,
        'attachment',
        'dual-source blending reads the second output of attachment zero '
            'only',
      );
    }
  }
}

/// Refuses a direct indexed draw whose base vertex or first instance needs
/// a feature [features] lacks.
void checkIndexedDraw(IndexedDraw draw, DeviceFeatures features) {
  if (!draw.usesBaseVertexOrInstance) return;
  features.require(
    DeviceFeature.baseVertexBaseInstance,
    backend: cpuBackendName,
    reason: 'the draw names a base vertex or a first instance',
  );
}

/// Whether [shader] declares the storage binding [name] — see
/// [CpuStorageReader]. A stage that declares nothing answers
/// [undeclared]: false for a render stage, true for a compute stage.
bool declaresStorage(
  ShaderHandle shader,
  String name, {
  required bool undeclared,
}) {
  final stage = shader.backend;
  final dart = stage is CpuStage
      ? (stage.vertex ?? stage.fragment ?? stage.compute)
      : null;
  return dart is CpuStorageReader
      ? dart.storageBindings.contains(name)
      : undeclared;
}

/// A storage buffer's bound range, checked as every binding of one is: made
/// for storage, not mapped, the range inside it.
ByteData storageRangeOf(
  StorageBuffer buffer, {
  required int offsetInBytes,
  int? sizeInBytes,
}) {
  requireBufferUsage(buffer, BufferUsage.storage, 'a storage binding');
  checkUnmapped(buffer);
  return rangeOf(
    buffer,
    offsetInBytes: offsetInBytes,
    sizeInBytes: sizeInBytes,
  );
}

/// What a pipeline-statistics query counts, kept running by a pass so that
/// a query is the difference between its end and its start.
final class CpuStatistics {
  final List<int> counts = List<int>.filled(PipelineStatistic.values.length, 0);

  void add(PipelineStatistic statistic, int n) => counts[statistic.index] += n;
}

/// An open pipeline-statistics query: where its five results go and what
/// the counters said when it began.
final class CpuOpenStatisticsQuery {
  CpuOpenStatisticsQuery(this.results, this.index, CpuStatistics statistics)
    : start = List<int>.of(statistics.counts);

  final CpuQueryResults results;
  final int index;
  final List<int> start;

  void end(CpuStatistics statistics) {
    final base = index * PipelineStatistic.values.length;
    for (var i = 0; i < start.length; i++) {
      results.values[base + i] = statistics.counts[i] - start[i];
    }
  }
}
