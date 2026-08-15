/// What the game decides a coin looks like, without a renderer to draw it.
///
/// Written because the shrink-on-pickup animation shipped with every coin in
/// the level invisible: an uncollected coin says *never taken* by holding
/// `sinceTaken` at infinity, and "has it finished shrinking" asked of infinity
/// is yes. The playthrough tests could not see it — they read the simulation,
/// and the simulation was right. Only the picture was wrong, so this is a test
/// about the picture.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/looks.dart';
import 'package:vector_math/vector_math.dart';

/// Somebody with pockets, which is all a coin asks of whoever walks into it.
final class _Taker implements Gatherer {
  @override
  final Purse purse = Purse();
}

/// A coin in a world, with the machinery that makes it takeable.
({Fixture fixture, Collectible coin, void Function() take}) _coin() {
  final world = CollisionWorld();
  final mechanisms = MechanismWorld(world);
  final collider = world.add(
    Collider(
      shape: CollisionBox(Vector3.all(0.25)),
      position: Vector3(0.0, 0.8, 0.0),
      kind: ColliderKind.trigger,
      layer: CollisionLayers.pickup,
      mask: CollisionLayers.player,
    ),
  );
  final coin = mechanisms.add(
    Collectible(name: 'a coin', what: 'coin', collider: collider),
  );
  final taker = world.add(
    Collider(
      shape: CollisionBox(Vector3.all(0.45)),
      position: Vector3(0.0, 0.9, 0.0),
      layer: CollisionLayers.player,
    ),
  )..userData = _Taker();

  return (
    fixture: Fixture(
      entity: EntityDef(type: PlatformerEntities.collectible),
      size: Vector3.all(0.5),
      material: 'brass',
      collider: collider,
      mechanism: coin,
    ),
    coin: coin,
    take: () => coin.activate(mechanisms.activationBy(taker)),
  );
}

void main() {
  const looks = PlatformerLooks();

  test('a coin nobody has touched is drawn, at its full size', () {
    final it = _coin();

    expect(looks.isSpent(it.fixture), isFalse,
        reason: 'never taken is not the same as taken long ago');
    expect(looks.scaleOf(it.fixture), 1.0);
  });

  test('a coin just taken is still drawn, and smaller', () {
    final it = _coin();
    it.take();
    it.coin.step(0.15);

    expect(looks.isSpent(it.fixture), isFalse, reason: 'still shrinking');
    final scale = looks.scaleOf(it.fixture);
    expect(scale, lessThan(1.0));
    expect(scale, greaterThan(0.0));
  });

  test('a coin taken a third of a second ago has gone', () {
    final it = _coin();
    it.take();
    it.coin.step(0.4);

    expect(looks.isSpent(it.fixture), isTrue);
    expect(looks.scaleOf(it.fixture), 0.0);
  });
}
