import 'package:flutter_gpu/gpu.dart' as gpu;

import '../graphics/formats.dart';
import 'gpu_formats.dart';

/// What makes two render targets interchangeable.
///
/// A value type so it can be a map key: the pool's whole job is to answer "have
/// I already got one of these", and that question is exactly this tuple.
final class RenderTargetSpec {
  const RenderTargetSpec({
    required this.width,
    required this.height,
    required this.format,
    this.sampleCount = 1,
    this.storageMode = StorageMode.devicePrivate,
  });

  final int width;
  final int height;
  final TextureFormat format;
  final int sampleCount;

  /// `deviceTransient` is tile memory: cheaper, but cannot be sampled or loaded
  /// from, which rules it out for anything the next pass reads.
  final StorageMode storageMode;

  RenderTargetSpec scaled(int divisor) => RenderTargetSpec(
        // Never below one pixel: a bloom chain taken far enough would otherwise
        // ask for a zero-sized texture, and the failure is a driver error
        // rather than an exception.
        width: width ~/ divisor < 1 ? 1 : width ~/ divisor,
        height: height ~/ divisor < 1 ? 1 : height ~/ divisor,
        format: format,
        sampleCount: sampleCount,
        storageMode: storageMode,
      );

  @override
  bool operator ==(Object other) =>
      other is RenderTargetSpec &&
      other.width == width &&
      other.height == height &&
      other.format == format &&
      other.sampleCount == sampleCount &&
      other.storageMode == storageMode;

  @override
  int get hashCode =>
      Object.hash(width, height, format, sampleCount, storageMode);

  @override
  String toString() => 'RenderTargetSpec(${width}x$height, ${format.name}, '
      'x$sampleCount, ${storageMode.name})';
}

/// Reuses textures across frames, keyed by what makes them interchangeable.
///
/// Without this a bloom chain allocates a texture per level per frame — five or
/// six of them at 60 Hz — and flutter_gpu has no explicit release, so they pile
/// up until the collector notices. On mobile that is the difference between a
/// frame's worth of memory and a second's.
///
/// Deliberately not a general resource manager. Targets are acquired and
/// released within a frame, so the pool only has to track which of the textures
/// it already owns are currently lent out.
final class RenderTargetPool {
  final Map<RenderTargetSpec, List<gpu.Texture>> _free =
      <RenderTargetSpec, List<gpu.Texture>>{};
  final Map<gpu.Texture, RenderTargetSpec> _lent =
      <gpu.Texture, RenderTargetSpec>{};

  int _created = 0;

  /// Textures ever created, so a leak shows up as a number that keeps climbing.
  int get createdCount => _created;

  int get lentCount => _lent.length;

  int get pooledCount {
    var total = 0;
    for (final list in _free.values) {
      total += list.length;
    }
    return total;
  }

  /// A texture matching [spec], reused when one is free.
  gpu.Texture acquire(RenderTargetSpec spec) {
    final free = _free[spec];
    if (free != null && free.isNotEmpty) {
      final texture = free.removeLast();
      _lent[texture] = spec;
      return texture;
    }

    final texture = gpu.gpuContext.createTexture(
      spec.storageMode.toGpu(),
      spec.width,
      spec.height,
      format: spec.format.toGpu(),
      sampleCount: spec.sampleCount,
      enableRenderTargetUsage: true,
      // Transient textures live in tile memory and cannot be sampled, so asking
      // for shader read on one is a contradiction the driver would have to
      // resolve for us.
      enableShaderReadUsage: spec.storageMode != StorageMode.deviceTransient,
    );
    _created++;
    _lent[texture] = spec;
    return texture;
  }

  /// Returns a texture for reuse.
  ///
  /// Releasing something the pool never lent out is a bug in the caller, not
  /// something to absorb: it means two owners think they hold the same target.
  void release(gpu.Texture texture) {
    final spec = _lent.remove(texture);
    if (spec == null) {
      throw StateError('Released a texture this pool does not own.');
    }
    (_free[spec] ??= <gpu.Texture>[]).add(texture);
  }

  /// Drops every pooled texture, keeping the ones still lent out.
  ///
  /// Called on a resize: every spec has changed, so nothing in the pool will
  /// ever match again and holding it is pure waste.
  void trim() => _free.clear();

  @override
  String toString() => 'RenderTargetPool($pooledCount free, ${_lent.length} '
      'in use, $_created created)';
}
