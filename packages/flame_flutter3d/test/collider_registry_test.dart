/// Which Flame component a collider belongs to, forgotten on its own when
/// the component leaves the game.
library;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show ActorSystem, GameRandom;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWithGame<FlameGame>(
    'a collider is found while its component is in the game, and not after',
    FlameGame.new,
    (game) async {
      // Mutation: keep the entry until it is unregistered by hand.
      final registry = ColliderRegistry();
      final collider = Collider(shape: CollisionBox(Vector3.all(0.5)));
      final bot = PositionComponent();
      await game.add(bot);
      await game.ready();
      registry.register(collider, bot);
      expect(registry.componentFor(collider), same(bot));

      bot.removeFromParent();
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(registry.componentFor(collider), isNull);
    },
  );

  testWithGame<FlameGame>(
    'moved to another parent it is still found, and added again it is '
    'found again',
    FlameGame.new,
    (game) async {
      // Flame moves a component by removing and mounting it, and the
      // removal dropped the entry for good; a pooled ship added back was
      // never found either.
      //
      // Mutation: drop the entry on the first removal and never re-arm.
      final registry = ColliderRegistry();
      final collider = Collider(shape: CollisionBox(Vector3.all(0.5)));
      final bot = PositionComponent();
      final squad = PositionComponent();
      await game.addAll(<Component>[bot, squad]);
      await game.ready();
      registry.register(collider, bot);

      bot.parent = squad;
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(registry.componentFor(collider), same(bot), reason: 'moved');

      bot.removeFromParent();
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(registry.componentFor(collider), isNull);

      await game.add(bot);
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(registry.componentFor(collider), same(bot), reason: 'back');

      registry.unregister(collider);
      bot.removeFromParent();
      await game.ready();
      await game.add(bot);
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(
        registry.componentFor(collider),
        isNull,
        reason: 'unregistered stays unregistered',
      );
    },
  );

  testWithGame<FlameGame>(
    'a partner removed mid-contact ends the contact on this side',
    FlameGame.new,
    (game) async {
      // Flame's hitboxes end both sides when one goes; the world said
      // nothing, and the ship went on colliding with a bot long gone.
      //
      // Mutation: end a contact only when the world reports it.
      final world = CollisionWorld();
      final registry = ColliderRegistry();
      final body = RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3.zero(),
        mass: 1.0,
      );
      final ship = _Ship(body, (_) {});
      final marker = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3(0.2, 0.0, 0.0),
        ),
      );
      final bot = PositionComponent();
      await game.addAll(<Component>[ship, bot]);
      await game.ready();
      registry
        ..register(marker, bot)
        ..bridge(collider: body.collider, component: ship);

      world.update();
      expect(ship.activeCollisions, contains(bot));

      bot.removeFromParent();
      await game.ready();
      await Future<void>.delayed(Duration.zero);
      expect(ship.activeCollisions, isNot(contains(bot)));
      expect(ship.isColliding, isFalse);
    },
  );

  testWithGame<FlameGame>(
    'a bridge made through it hands over the other side of a contact',
    FlameGame.new,
    (game) async {
      final world = CollisionWorld();
      final registry = ColliderRegistry();
      final body = RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3.zero(),
        mass: 1.0,
      );
      PositionComponent? touched;
      final ship = _Ship(body, (other) => touched = other);
      final marker = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3(0.2, 0.0, 0.0),
        ),
      );
      final bot = PositionComponent();
      await game.addAll(<Component>[ship, bot]);
      await game.ready();
      registry
        ..register(marker, bot)
        ..bridge(collider: body.collider, component: ship);

      world.update();
      expect(touched, same(bot));
    },
  );

  testWithGame<FlameGame>(
    'an actor is told what its body touched, as a crate is',
    FlameGame.new,
    (game) async {
      // Mutation: accept only a RigidBodyComponent as the bridged side.
      final world = CollisionWorld();
      final system = ActorSystem(world: world, random: GameRandom(1));
      final body = CharacterController(world: world, position: Vector3.zero());
      PositionComponent? touched;
      final bot = ActorComponent(
        actor: system.spawn(body: body),
        node: SceneNode(),
        scene: Scene(),
        plane: BridgePlane.ground(),
      )..onCollisionStartCallback = (_, other) => touched = other;
      final ship = PositionComponent();
      final hull = world.add(
        Collider(
          shape: CollisionBox(Vector3.all(0.5)),
          position: Vector3(0.2, 0.0, 0.0),
        ),
      );
      await game.addAll(<Component>[bot, ship]);
      await game.ready();
      ColliderRegistry()
        ..register(hull, ship)
        ..bridge(collider: body.collider, component: bot);

      world.update();
      expect(touched, same(ship));
    },
  );
}

final class _Ship extends RigidBodyComponent {
  _Ship(RigidBody body, this.onTouch)
    : super(
        body: body,
        node: SceneNode(),
        scene: Scene(),
        plane: BridgePlane.ground(),
      );

  final void Function(PositionComponent other) onTouch;

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    onTouch(other);
  }
}
