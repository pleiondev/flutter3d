/// Reuse of render targets, and the description that makes two interchangeable.
///
/// In `graphics/` rather than in `gpu/` since the pool stopped creating
/// textures itself. Everything here is arithmetic over [TextureHandle] and a
/// map lookup, and the one line that needed a device — `createTexture` — is now
/// [TextureAllocator], supplied from outside. That is what makes the pool
/// unit-testable, and being in this directory is what keeps it that way:
/// `test/graphics_is_backend_free_test.dart` fails on the first backend import.
library;

import 'formats.dart';
import 'texture.dart';

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

  /// The description a texture already carries, read back off it.
  ///
  /// The pool records what it lent out as handles and derives the spec from
  /// them rather than remembering it alongside. One fact in one place: a
  /// remembered spec that disagreed with the texture would put a target back in
  /// the wrong free list, and the next acquirer would be handed the wrong size
  /// with nothing to say so.
  factory RenderTargetSpec.of(TextureHandle texture) => RenderTargetSpec(
        width: texture.width,
        height: texture.height,
        format: texture.format,
        sampleCount: texture.sampleCount,
        storageMode: texture.storageMode,
      );

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

/// Makes a texture. The one thing a pool cannot do on its own.
///
/// Injected rather than imported so the pool holds no backend at all. There is
/// exactly one implementation that talks to a device — `GpuTextureAllocator` in
/// `gpu/gpu_texture.dart` — and any number of counting fakes in tests.
abstract interface class TextureAllocator {
  /// A brand-new texture matching [spec], with the single [TextureHandle] that
  /// will ever stand for it.
  TextureHandle createTexture(RenderTargetSpec spec);
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
  RenderTargetPool(this.allocator);

  final TextureAllocator allocator;

  final Map<RenderTargetSpec, List<TextureHandle>> _free =
      <RenderTargetSpec, List<TextureHandle>>{};

  /// What is currently out on loan, by identity.
  ///
  /// A [Set] and not a list, and identity is the whole reason it works:
  /// [TextureHandle] has no value equality, so two interchangeable targets —
  /// same size, same format, therefore equal descriptions — remain two entries.
  final Set<TextureHandle> _lent = <TextureHandle>{};

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
  TextureHandle acquire(RenderTargetSpec spec) {
    final free = _free[spec];
    if (free != null && free.isNotEmpty) {
      final texture = free.removeLast();
      _lent.add(texture);
      return texture;
    }

    final texture = allocator.createTexture(spec);
    _created++;
    _lent.add(texture);
    return texture;
  }

  /// Returns a texture for reuse.
  ///
  /// Releasing something the pool never lent out is a bug in the caller, not
  /// something to absorb: it means two owners think they hold the same target.
  void release(TextureHandle texture) {
    if (!_lent.remove(texture)) {
      throw StateError('Released a texture this pool does not own.');
    }
    (_free[RenderTargetSpec.of(texture)] ??= <TextureHandle>[]).add(texture);
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
