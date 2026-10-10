// A cache that knows what it holds against a budget, loads what matters
// first, lets a load be called off, and lets a holder say how much it
// still matters.
import 'dart:async';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

/// A load that finishes when the test says, one completer per key.
final class _Loads {
  final Map<String, Completer<int>> pending = <String, Completer<int>>{};
  final List<String> started = <String>[];

  Future<int> call(String key) {
    started.add(key);
    return (pending[key] = Completer<int>()).future;
  }

  void finish(String key, int value) => pending[key]!.complete(value);
}

void main() {
  group('MemoryBudget', () {
    test('says when a category crosses its limit, once each way', () {
      final budget = MemoryBudget(
        limits: <MemoryCategory, int>{MemoryCategory.textures: 100},
      );
      final crossings = <MemoryBudgetCrossing>[];
      budget.onCrossed(crossings.add);

      budget.charge(MemoryCategory.textures, 60);
      expect(crossings, isEmpty);
      budget.charge(MemoryCategory.textures, 60);
      // Mutation: report every charge while over, and there are two here.
      budget.charge(MemoryCategory.textures, 10);
      expect(crossings, hasLength(1));
      expect(crossings.single.category, MemoryCategory.textures);
      expect(crossings.single.isOver, isTrue);
      expect(crossings.single.used, 120);
      expect(crossings.single.limit, 100);
      expect(budget.isOver(MemoryCategory.textures), isTrue);

      budget.refund(MemoryCategory.textures, 50);
      expect(crossings, hasLength(2));
      expect(crossings.last.isOver, isFalse);
      expect(budget.usedOf(MemoryCategory.textures), 80);
    });

    test('a total limit is crossed by the categories together', () {
      final budget = MemoryBudget(total: 100);
      final crossings = <MemoryBudgetCrossing>[];
      budget.onCrossed(crossings.add);
      budget
        ..charge(MemoryCategory.textures, 60)
        ..charge(MemoryCategory.meshes, 50);
      expect(crossings.single.category, isNull);
      expect(budget.used, 110);
      expect(budget.isOver(), isTrue);
    });

    test('a cancelled registration hears nothing more', () {
      final budget = MemoryBudget(total: 10);
      var heard = 0;
      budget.onCrossed((_) => heard++).cancel();
      budget.charge(MemoryCategory.buffers, 20);
      expect(heard, 0);
    });
  });

  group('ResourceCache against a budget', () {
    test('a loaded value is charged, and refunded when it leaves', () async {
      final budget = MemoryBudget();
      final cache = ResourceCache<String, int>(
        load: (key) async => key.length,
        budget: budget,
        sizeOf: (value) => value * 10,
        categoryOf: (_) => MemoryCategory.meshes,
      );
      final handle = await cache.acquire('abcd');
      expect(budget.usedOf(MemoryCategory.meshes), 40);
      handle.release();
      cache.evictUnused();
      expect(budget.usedOf(MemoryCategory.meshes), 0);
    });

    test('over the budget, the least wanted unheld entry goes first', () async {
      final budget = MemoryBudget(
        limits: <MemoryCategory, int>{MemoryCategory.textures: 30},
      );
      final disposed = <int>[];
      final cache = ResourceCache<String, int>(
        load: (key) async => int.parse(key),
        dispose: disposed.add,
        budget: budget,
        sizeOf: (_) => 10,
        categoryOf: (_) => MemoryCategory.textures,
      );
      final background = await cache.acquire(
        '1',
        priority: ResourcePriority.background,
      );
      final visible = await cache.acquire(
        '2',
        priority: ResourcePriority.visible,
      );
      final normal = await cache.acquire('3');
      background.release();
      visible.release();
      normal.release();

      // A fourth puts the textures over: the background one goes, the
      // visible one, wanted more, stays. Mutation: evict in the order the
      // entries were made, and '1' and '2' both go before '3'.
      final held = await cache.acquire('4');
      expect(disposed, <int>[1]);
      expect(cache.contains('2'), isTrue);
      expect(cache.contains('3'), isTrue);
      expect(budget.isOver(MemoryCategory.textures), isFalse);

      // Never what is still held, however little it is wanted.
      held.priority = ResourcePriority.background;
      await cache.acquire('5');
      expect(cache.contains('4'), isTrue);
      expect(disposed, <int>[1, 3]);
    });
  });

  group('ResourceCache loads by priority', () {
    test('with one load at a time, the most wanted starts next', () async {
      final loads = _Loads();
      final cache = ResourceCache<String, int>(
        load: loads.call,
        maxConcurrentLoads: 1,
      );
      final first = cache.request('first');
      cache.request('later', priority: ResourcePriority.background);
      cache.request('urgent', priority: ResourcePriority.blocking);
      expect(loads.started, <String>['first']);

      loads.finish('first', 1);
      await first.handle;
      // Mutation: start the queue in the order it was asked, and 'later'
      // starts here.
      expect(loads.started, <String>['first', 'urgent']);
    });

    test('raising a waiting request moves it up the queue', () async {
      final loads = _Loads();
      final cache = ResourceCache<String, int>(
        load: loads.call,
        maxConcurrentLoads: 1,
      );
      final first = cache.request('first');
      cache.request('a');
      final b = cache.request('b');
      b.priority = ResourcePriority.visible;
      loads.finish('first', 1);
      await first.handle;
      expect(loads.started.last, 'b');
    });

    test('a waiting request called off never loads', () async {
      final loads = _Loads();
      final cache = ResourceCache<String, int>(
        load: loads.call,
        maxConcurrentLoads: 1,
      );
      final first = cache.request('first');
      final doomed = cache.request('doomed');
      doomed.cancel();
      await expectLater(doomed.handle, throwsA(isA<ResourceLoadCancelled>()));
      expect(cache.contains('doomed'), isFalse);
      expect(doomed.isCancelled, isTrue);

      loads.finish('first', 1);
      await first.handle;
      await Future<void>.delayed(Duration.zero);
      expect(loads.started, <String>['first']);
    });

    test('a load called off midway is kept, held by nobody', () async {
      final loads = _Loads();
      final cache = ResourceCache<String, int>(load: loads.call);
      final request = cache.request('k');
      expect(cache.referenceCount('k'), 1);
      request.cancel();
      expect(cache.referenceCount('k'), 0);
      await expectLater(request.handle, throwsA(isA<ResourceLoadCancelled>()));
      loads.finish('k', 9);
      await Future<void>.delayed(Duration.zero);
      expect(cache.isLoaded('k'), isTrue);
      expect(cache.evictUnused(), 1);
    });

    test('one of two requests for a key called off leaves the other', () async {
      final loads = _Loads();
      final cache = ResourceCache<String, int>(load: loads.call);
      final kept = cache.request('k');
      cache.request('k').cancel();
      loads.finish('k', 3);
      expect((await kept.handle).value, 3);
      expect(cache.referenceCount('k'), 1);
      expect(loads.started, <String>['k']);
    });
  });
}
