/// The pool's trim against its loans — the case that used to leak.
///
/// The broader pool suite lives with the engine, in
/// `packages/flutter3d/test/render_target_pool_test.dart`, from before this
/// package could be tested on its own. This file covers the interaction that
/// suite was written without: a texture lent out when [RenderTargetPool.trim]
/// runs. Trim means every spec has changed — it is called on resize — so that
/// loan carries a spec no future acquire will ever name, and refiling it on
/// release parked it in a dead free list until the *next* resize. Now the trim
/// retires the loan, and its release hands it to the allocator instead.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [TextureAllocator] over nothing, counting what comes back.
final class _FakeAllocator implements TextureAllocator {
  int created = 0;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => TextureHandle(
    backend: 'created ${created++}',
    width: spec.width,
    height: spec.height,
    format: spec.format,
    sampleCount: spec.sampleCount,
    storageMode: spec.storageMode,
  );

  final List<TextureHandle> released = <TextureHandle>[];

  @override
  void releaseTexture(TextureHandle texture) => released.add(texture);
}

const RenderTargetSpec _spec = RenderTargetSpec(
  width: 640,
  height: 480,
  format: TextureFormat.r16g16b16a16Float,
);

void main() {
  group('a loan that outlives a trim', () {
    test('goes to the allocator on release, not into a free list', () {
      // The leak this file exists for. The released texture matched nothing —
      // acquires after a resize ask for the new size — so it sat in `_free`
      // holding a full-screen target until the next resize swept it.
      final allocator = _FakeAllocator();
      final pool = RenderTargetPool(allocator);

      final lent = pool.acquire(_spec);
      pool.trim();
      pool.release(lent);

      expect(allocator.released, <TextureHandle>[lent]);
      expect(pool.pooledCount, 0, reason: 'its spec is a pre-trim one');
      expect(pool.lentCount, 0);
    });

    test('is not confused with a loan taken out after the trim', () {
      // Same spec value, different loan: acquired *after* the trim, so its
      // spec is current and it must pool as usual. Identity is what keeps the
      // two apart, the same way it keeps `_lent` honest.
      final allocator = _FakeAllocator();
      final pool = RenderTargetPool(allocator);

      final stale = pool.acquire(_spec);
      pool.trim();
      final fresh = pool.acquire(_spec);
      pool.release(stale);
      pool.release(fresh);

      expect(allocator.released, <TextureHandle>[stale]);
      expect(pool.pooledCount, 1, reason: 'the fresh one is reusable');
      expect(pool.acquire(_spec), same(fresh));
    });

    test('still cannot be released twice', () {
      // The retirement path must not soften the double-release guard: the
      // first release spends the handle whichever list it leaves through.
      final pool = RenderTargetPool(_FakeAllocator());

      final lent = pool.acquire(_spec);
      pool.trim();
      pool.release(lent);

      expect(() => pool.release(lent), throwsStateError);
    });

    test('outliving two trims is still one hand-back', () {
      // A loan marked retired by one trim and still out when the next runs is
      // in the retired set once — releasing it must reach the allocator once.
      final allocator = _FakeAllocator();
      final pool = RenderTargetPool(allocator);

      final lent = pool.acquire(_spec);
      pool.trim();
      pool.trim();
      pool.release(lent);

      expect(allocator.released, <TextureHandle>[lent]);
    });
  });
}
