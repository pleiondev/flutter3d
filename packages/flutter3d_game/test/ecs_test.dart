/// Entities, components, and the reason the whole thing was accepted:
/// everything in the world can be written down without anybody enumerating
/// what "everything" is.
///
/// Each test was written by breaking the thing it covers. The mutation is
/// named in the test.
library;

import 'dart:convert';

import 'package:flutter3d_game/src/ecs/ecs_world.dart';
import 'package:flutter3d_game/src/ecs/entity.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Position {
  _Position(this.x, this.y);
  double x;
  double y;
}

final class _Name {
  _Name(this.value);
  final String value;
}

/// Something a renderer would own: a handle to a mesh that means nothing
/// outside the process that made it.
final class _Visual {
  _Visual(this.handle);
  final Object handle;
}

EcsWorld _world() {
  return EcsWorld()
    ..register<_Position>(
      'position',
      encode: (_Position p) => <double>[p.x, p.y],
      decode: (Object? data) {
        final row = data! as List;
        return _Position(
          (row[0] as num).toDouble(),
          (row[1] as num).toDouble(),
        );
      },
    )
    ..register<_Name>(
      'name',
      encode: (_Name n) => n.value,
      decode: (Object? data) => _Name(data! as String),
    );
}

void main() {
  group('handles', () {
    test('a handle to a despawned entity does not become the next one', () {
      // The bug a generation exists to prevent, and it does not throw when it
      // happens: the stale handle reads a perfectly valid component off an
      // entity that is not the one you meant, and the symptom turns up three
      // systems away.
      //
      // Mutation: make `Entity.of` ignore the generation. `alive` says true,
      // the name comes back as 'second', and this fails twice.
      final world = _world();
      final first = world.spawn();
      world.set(first, _Name('first'));

      world.despawn(first);
      final second = world.spawn();
      world.set(second, _Name('second'));

      expect(
        second.index,
        first.index,
        reason:
            'the index was reused, which '
            'is the whole point of the danger',
      );
      expect(world.alive(first), isFalse);
      expect(world.get<_Name>(first), isNull);
      expect(world.get<_Name>(second)!.value, 'second');
    });

    test('an entity is alive until it is not', () {
      final world = _world();
      final entity = world.spawn();
      expect(world.alive(entity), isTrue);
      expect(world.length, 1);
      world.despawn(entity);
      expect(world.alive(entity), isFalse);
      expect(world.length, 0);
    });

    test('despawning twice is not an error and does not lose count', () {
      final world = _world();
      final entity = world.spawn();
      world
        ..despawn(entity)
        ..despawn(entity);
      expect(world.length, 0);
      world.spawn();
      expect(world.length, 1);
    });

    test('nothing is not an entity', () {
      expect(_world().alive(Entity.none), isFalse);
    });

    test('despawning takes the components with it', () {
      final world = _world();
      final entity = world.spawn();
      world.set(entity, _Position(1.0, 2.0));
      world.despawn(entity);

      final reused = world.spawn();
      expect(reused.index, entity.index);
      expect(
        world.get<_Position>(reused),
        isNull,
        reason: 'the new entity inherited the old one\'s body',
      );
    });
  });

  group('components', () {
    test('what goes on comes off', () {
      final world = _world();
      final entity = world.spawn();
      expect(world.has<_Position>(entity), isFalse);

      world.set(entity, _Position(3.0, 4.0));
      expect(world.has<_Position>(entity), isTrue);
      expect(world.get<_Position>(entity)!.x, 3.0);

      world.remove<_Position>(entity);
      expect(world.has<_Position>(entity), isFalse);
    });

    test(
      'setting on a dead entity does nothing rather than resurrecting it',
      () {
        final world = _world();
        final entity = world.spawn();
        world
          ..despawn(entity)
          ..set(entity, _Position(1.0, 1.0));
        expect(world.length, 0);
        expect(world.get<_Position>(entity), isNull);
      },
    );
  });

  group('queries', () {
    test('finds what carries both and nothing else', () {
      final world = _world();
      final both = world.spawn();
      final onlyPosition = world.spawn();
      final onlyName = world.spawn();
      world
        ..set(both, _Position(0.0, 0.0))
        ..set(both, _Name('both'))
        ..set(onlyPosition, _Position(1.0, 1.0))
        ..set(onlyName, _Name('name'));

      expect(world.query2<_Position, _Name>().toList(), <Entity>[both]);
      expect(world.query<_Position>().length, 2);
    });

    test('a query survives the loop despawning what it is walking', () {
      // The commonest way to write a system: walk everything, and remove the
      // ones that died. An iteration straight over the live keys throws a
      // concurrent-modification error the first time anybody does it.
      final world = _world();
      for (var i = 0; i < 6; i++) {
        world.set(world.spawn(), _Position(i.toDouble(), 0.0));
      }

      for (final entity in world.query<_Position>()) {
        if (world.get<_Position>(entity)!.x % 2 == 0) world.despawn(entity);
      }

      expect(world.length, 3);
    });

    test('a query over a type nothing has is empty, not an error', () {
      expect(_world().query<_Visual>(), isEmpty);
    });
  });

  group('writing it down', () {
    test('a world round-trips through text', () {
      final world = _world();
      final a = world.spawn();
      final b = world.spawn();
      world
        ..set(a, _Position(1.5, -2.5))
        ..set(a, _Name('a'))
        ..set(b, _Position(0.0, 9.0));
      world.despawn(world.spawn());

      final written = jsonEncode(world.save());
      final read = _world()
        ..restore(jsonDecode(written) as Map<String, Object?>);

      expect(read.length, world.length);
      expect(read.get<_Name>(a)!.value, 'a');
      expect(read.get<_Position>(b)!.y, 9.0);
      expect(read.query2<_Position, _Name>().toList(), <Entity>[a]);
      expect(jsonEncode(read.save()), written);
    });

    test('handles keep meaning the same thing across a restore', () {
      // The property that makes a snapshot usable at all: an entity written on
      // one side and read on the other is the same entity, so anything holding
      // a handle across the restore is not holding a different monster.
      final world = _world();
      world.spawn();
      final kept = world.spawn();
      world
        ..set(kept, _Name('kept'))
        ..despawn(kept);
      final recycled = world.spawn();
      world.set(recycled, _Name('recycled'));

      final read = _world()..restore(world.save());
      expect(
        read.alive(kept),
        isFalse,
        reason: 'a handle that was stale before the save is stale after it',
      );
      expect(read.get<_Name>(recycled)!.value, 'recycled');
    });

    test('a component with no codec stops the save rather than vanishing', () {
      // The rule this file exists to enforce. A save that quietly leaves out a
      // component is a bug that appears hours later as a game that is subtly
      // wrong, and the moment to hear about it is while writing the save.
      //
      // Mutation: skip unregistered stores instead of throwing. The save
      // succeeds, the component is gone, and nothing anywhere says so.
      final world = _world();
      world.set(world.spawn(), _Visual(Object()));

      expect(
        world.save,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('_Visual'), contains('exclude')),
          ),
        ),
      );
    });

    test('a component excluded on purpose is skipped in silence', () {
      final world = _world()
        ..exclude<_Visual>('a mesh handle means nothing in another process');
      world.set(world.spawn(), _Visual(Object()));

      final saved = world.save();
      expect((saved['components']! as Map).containsKey('_Visual'), isFalse);
      expect(() => jsonEncode(saved), returnsNormally);
    });

    test('two components cannot share a name', () {
      // They would overwrite each other in every save file ever written, and
      // the first sign of it would be a load that produced the wrong world.
      final world = _world();
      expect(
        () => world.register<_Visual>(
          'name',
          encode: (_Visual v) => '',
          decode: (Object? data) => _Visual(Object()),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a component this build has never heard of is skipped, not fatal', () {
      // An older build reading a newer save has already been refused by the
      // version; a newer build reading an older save simply finds less. What
      // must not happen is a crash on a name nobody recognises.
      final world = _world();
      final saved = world.save();
      (saved['components']! as Map)['ghost'] = <String, Object?>{'0': 1};
      expect(() => _world().restore(saved), returnsNormally);
    });
  });

  test('a snapshot with rubbish in its free list still restores', () {
    // **`(value! as num).toInt()`, in a method whose own comments explain that
    // a save from another build is expected and survivable.** A null or a
    // string in either list — a truncated write, a hand edit — threw out of the
    // restore instead. A row it cannot read is dropped, which is the answer
    // this loop already gives a component type it has never heard of.
    final world = EcsWorld();

    expect(
      () => world.restore(<String, Object?>{
        'generations': <Object?>[1, null, 'two', 3],
        'free': <Object?>['none'],
        'components': <String, Object?>{},
      }),
      returnsNormally,
    );
  });

  test('an index recycled past 255 still answers for the handle it gave', () {
    // The index and the generation share one integer. Packed with
    // `generation << 24`, the generation leaves 32 bits at 256 — and on the
    // web, where an `int` is a double and a bitwise operation is done in 32
    // bits, it wraps to zero. The handle the world just returned then reads
    // back a generation the world does not have, and `alive` calls a live
    // entity dead.
    //
    // Mutation: put the shift back and run this file under `-p chrome`. The
    // expectation below fails at the 256th recycle.
    final world = EcsWorld();
    var handle = world.spawn();
    for (var i = 0; i < 256; i++) {
      world.despawn(handle);
      handle = world.spawn();
    }

    expect(world.alive(handle), isTrue);
    expect(handle.generation, 256, reason: 'one per recycle of the index');
    expect(handle.index, 0, reason: 'the freed index is the one reused');
  });

  test('two generations of one index are two different handles', () {
    // The same packing from the other side: a stale handle must not compare
    // equal to the handle that took its index over. `final` rather than
    // `const` deliberately — two const expressions of the same value are
    // canonicalised into one object, which would make this pass for a reason
    // that has nothing to do with the packing.
    final fresh = Entity.of(7, 300);
    final stale = Entity.of(7, 44);

    expect(fresh, isNot(stale));
    expect(fresh.generation, 300);
    expect(stale.generation, 44);
  });
}
