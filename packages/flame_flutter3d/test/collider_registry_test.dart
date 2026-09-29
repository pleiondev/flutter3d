/// Which Flame component a collider belongs to, forgotten on its own when
/// the component leaves the game.
library;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_physics/flutter3d_physics.dart';
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
