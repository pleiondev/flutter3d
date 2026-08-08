import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d/src/engine/assets/resource_cache.dart';

void main() {
  group('loading', () {
    test('loads once and reuses the value', () async {
      var loads = 0;
      final cache = ResourceCache<String, int>(
        load: (key) async {
          loads++;
          return key.length;
        },
      );

      final a = await cache.acquire('teapot');
      final b = await cache.acquire('teapot');

      expect(loads, 1, reason: 'a cached key must not reload');
      expect(a.value, 6);
      expect(b.value, 6);
      expect(cache.referenceCount('teapot'), 2);
    });

    test('deduplicates concurrent loads of the same key', () async {
      // The case that actually happens: clicking a model twice before the first
      // load finishes. Without dedup it decodes and uploads twice.
      var loads = 0;
      final gate = Completer<void>();
      final cache = ResourceCache<String, String>(
        load: (key) async {
          loads++;
          await gate.future;
          return key.toUpperCase();
        },
      );

      final first = cache.acquire('box');
      final second = cache.acquire('box');
      gate.complete();

      final handles = await Future.wait(<Future<ResourceHandle<String>>>[
        first,
        second,
      ]);
      expect(loads, 1);
      expect(handles[0].value, 'BOX');
      expect(handles[1].value, 'BOX');
      expect(cache.referenceCount('box'), 2);
    });

    test('different keys load independently', () async {
      final cache = ResourceCache<String, int>(load: (k) async => k.length);
      await cache.acquire('a');
      await cache.acquire('bb');
      expect(cache.length, 2);
      expect(cache.keys.toSet(), <String>{'a', 'bb'});
    });
  });

  group('failures', () {
    test('a failed load is not cached, so the next attempt retries', () async {
      var attempts = 0;
      final cache = ResourceCache<String, String>(
        load: (key) async {
          attempts++;
          if (attempts == 1) throw StateError('boom');
          return 'ok';
        },
      );

      await expectLater(cache.acquire('x'), throwsStateError);
      expect(cache.contains('x'), isFalse, reason: 'the failure is forgotten');

      final handle = await cache.acquire('x');
      expect(handle.value, 'ok');
      expect(attempts, 2);
    });

    test('a failed load leaves no dangling reference', () async {
      final cache = ResourceCache<String, String>(
        load: (_) async => throw StateError('boom'),
      );
      await expectLater(cache.acquire('x'), throwsStateError);
      expect(cache.referenceCount('x'), 0);
    });
  });

  group('reference counting', () {
    test('release decrements', () async {
      final cache = ResourceCache<String, int>(load: (k) async => 1);
      final a = await cache.acquire('k');
      final b = await cache.acquire('k');
      expect(cache.referenceCount('k'), 2);

      a.release();
      expect(cache.referenceCount('k'), 1);
      b.release();
      expect(cache.referenceCount('k'), 0);
    });

    test('releasing twice throws instead of corrupting the count', () async {
      // A double release would drop somebody else's reference and evict a resource
      // still in use, failing somewhere unrelated. Better to fail at the mistake.
      final cache = ResourceCache<String, int>(load: (k) async => 1);
      final handle = await cache.acquire('k');
      handle.release();
      expect(handle.release, throwsStateError);
      expect(cache.referenceCount('k'), 0);
    });

    test('isReleased reports the state', () async {
      final cache = ResourceCache<String, int>(load: (k) async => 1);
      final handle = await cache.acquire('k');
      expect(handle.isReleased, isFalse);
      handle.release();
      expect(handle.isReleased, isTrue);
    });
  });

  group('eviction', () {
    test('keeps unreferenced entries until asked to evict', () async {
      // Deliberate policy: flipping back to a previously viewed model should be
      // free, so a zero count is not eviction on its own.
      final cache = ResourceCache<String, int>(load: (k) async => 1);
      (await cache.acquire('k')).release();

      expect(cache.contains('k'), isTrue);
      expect(cache.evictUnused(), 1);
      expect(cache.contains('k'), isFalse);
    });

    test('never evicts something still held', () async {
      final cache = ResourceCache<String, int>(load: (k) async => 1);
      final held = await cache.acquire('held');
      (await cache.acquire('free')).release();

      expect(cache.evictUnused(), 1);
      expect(cache.contains('held'), isTrue);
      expect(cache.contains('free'), isFalse);
      expect(held.value, 1);
    });

    test('dispose runs on eviction, once per entry', () async {
      final disposed = <int>[];
      final cache = ResourceCache<String, int>(
        load: (k) async => k.length,
        dispose: disposed.add,
      );
      (await cache.acquire('abc')).release();
      (await cache.acquire('de')).release();

      cache.evictUnused();
      expect(disposed..sort(), <int>[2, 3]);

      cache.evictUnused();
      expect(disposed, hasLength(2), reason: 'no double dispose');
    });

    test('clear drops held entries too, and handles keep working', () async {
      final cache = ResourceCache<String, int>(load: (k) async => 7);
      final handle = await cache.acquire('k');
      cache.clear();

      expect(cache.length, 0);
      // The value is a live Dart object; only the cache forgot about it.
      expect(handle.value, 7);
    });

    test('an in-flight entry is not evicted', () async {
      final gate = Completer<int>();
      final cache = ResourceCache<String, int>(load: (_) => gate.future);

      final pending = cache.acquire('k');
      expect(cache.referenceCount('k'), 1, reason: 'counted before awaiting');
      expect(cache.evictUnused(), 0);

      gate.complete(5);
      expect((await pending).value, 5);
    });
  });
}
