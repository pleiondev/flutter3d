/// What a restore has to rebuild, not just refill.
///
///     flutter test test/rebuild_after_restore_test.dart
///
/// A snapshot fills in a world that already exists. Two things in it do not
/// survive that on their own: an actor born after the level loaded, which a
/// fresh world does not have, and a trigger a taking removed, which a rollback
/// to before the taking needs back.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Coin extends Takeable {
  _Coin({required super.collider}) : super(name: 'coin');

  @override
  bool offerTo(Object? taker) => true;
}

ActorSystem _system() => ActorSystem(
  world: CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
    ..update(),
  random: GameRandom(1),
);

Actor _walker(ActorSystem system, double x, {Entity? entity}) => system.spawn(
  body: CharacterController(
    world: system.world,
    position: Vector3(x, 0.9, 0.0),
  ),
  health: Health(10.0),
  entity: entity,
);

void main() {
  group('an actor born during play', () {
    test('is built again under its own entity, and takes its numbers', () {
      final first = _system();
      _walker(first, 1.0);
      final gone = _walker(first, 2.0);
      final born = _walker(first, 3.0);
      first.remove(gone);
      born.body!.position.x = 7.5;
      born.health!.damage(4.0);
      final saved = first.entities.save();

      final fresh = _system()..entities.restore(saved);
      final entity = born.entity;
      expect(fresh.entities.vacant(entity), isTrue);
      final rebuilt = _walker(fresh, 0.0, entity: entity);
      fresh.entities.restore(saved);

      expect(rebuilt.entity, entity);
      expect(rebuilt.position!.x, 7.5);
      expect(rebuilt.health!.current, 6.0);
    });

    test('cannot be built over an entity somebody is using', () {
      final system = _system();
      final there = _walker(system, 1.0);

      expect(system.entities.vacant(there.entity), isFalse);
      expect(
        () => _walker(system, 2.0, entity: there.entity),
        throwsArgumentError,
      );
    });

    test('nor under one the allocation does not have', () {
      final system = _system();

      expect(system.entities.vacant(const Entity.of(4, 0)), isFalse);
    });
  });

  test('a rollback to before a taking puts the trigger back', () {
    final world = CollisionWorld();
    final mechanisms = MechanismWorld(world);
    final coin = mechanisms.add(
      _Coin(
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3.all(0.3)),
            position: Vector3.zero(),
          ),
        ),
      ),
    );
    final before = mechanisms.save();

    coin.activate(mechanisms.activationBy(null));
    world.update();
    expect(coin.collider.world, isNull, reason: 'taken, and out of the world');

    mechanisms.restore(before);
    expect(coin.isTaken, isFalse);
    expect(coin.collider.world, same(world));
  });
}
