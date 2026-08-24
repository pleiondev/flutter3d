/// [RenderTargetPool] on its own, driven by a fake allocator.
///
/// Split out of `frame_resources_test.dart`: everything else in that file
/// tests [FrameResources] and the frame graph's read/write/keeps bookkeeping
/// through a compiled graph, while this exercises the pool underneath it
/// directly — lending, reuse, resizing and the double-release guard — with no
/// graph or node in sight.
library;

import 'package:flutter3d/src/engine/render/frame_resources.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [TextureAllocator] that makes handles over nothing.
///
/// This is the whole trick. The pool's job is bookkeeping; the only line in it
/// that ever needed a device was `createTexture`, and with that injected the
/// real pool runs in a unit test unchanged.
final class _FakeAllocator implements TextureAllocator {
  int created = 0;

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => fakeTexture(
        'created ${created++}',
        width: spec.width,
        height: spec.height,
        format: spec.format,
        sampleCount: spec.sampleCount,
        storageMode: spec.storageMode,
      );
}

/// A texture handle over an ordinary object.
///
/// [label] is only ever read by a failing expectation. Nothing off-device looks
/// inside a handle, which is the point of `backend` being an `Object`.
TextureHandle fakeTexture(
  String label, {
  int width = 640,
  int height = 480,
  TextureFormat format = TextureFormat.r16g16b16a16Float,
  int sampleCount = 1,
  StorageMode storageMode = StorageMode.devicePrivate,
}) =>
    TextureHandle(
      backend: label,
      width: width,
      height: height,
      format: format,
      sampleCount: sampleCount,
      storageMode: storageMode,
    );

void main() {
  group('the pool, now that it can be run without a device', () {
    test('two targets of one shape are two textures', () {
      // The property everything above rests on. Interchangeable targets have
      // equal descriptions by definition, so a handle with value equality would
      // make the pool believe it had lent one texture twice.
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final first = pool.acquire(spec);
      final second = pool.acquire(spec);
      expect(identical(first, second), isFalse);
      expect(pool.lentCount, 2);
      expect(pool.createdCount, 2);
    });

    test('a released target is the next one lent out', () {
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final first = pool.acquire(spec);
      pool.release(first);
      expect(pool.acquire(spec), same(first));
      expect(pool.createdCount, 1);
    });

    test('a target goes back into the list its own description names', () {
      // The spec is read off the texture rather than remembered beside it, so
      // there is no second copy to disagree with the first. A mismatch here
      // hands the next acquirer the wrong size with nothing to say so.
      final pool = RenderTargetPool(_FakeAllocator());
      const big = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );
      const small = RenderTargetSpec(
        width: 320,
        height: 240,
        format: TextureFormat.r16g16b16a16Float,
      );

      pool.release(pool.acquire(big));
      final reused = pool.acquire(small);
      expect(reused.width, 320);
      expect(pool.createdCount, 2, reason: 'the 640x480 one does not fit');
    });

    test('handing back something it never lent is an error, not a shrug', () {
      final pool = RenderTargetPool(_FakeAllocator());
      expect(
        () => pool.release(fakeTexture('somebody else’s')),
        throwsStateError,
      );
    });

    test('a resize drops what is free and keeps what is out', () {
      final pool = RenderTargetPool(_FakeAllocator());
      const spec = RenderTargetSpec(
        width: 640,
        height: 480,
        format: TextureFormat.r16g16b16a16Float,
      );

      final lent = pool.acquire(spec);
      pool.release(pool.acquire(spec));
      pool.trim();

      expect(pool.pooledCount, 0);
      expect(pool.lentCount, 1);
      // Still returnable: trimming forgets the free list, not the loans.
      pool.release(lent);
      expect(pool.pooledCount, 1);
    });
  });
}
