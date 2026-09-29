/// A world whose edges meet: positions wrap, a craft by an edge is drawn on
/// the other side too, and it can be hit across the seam.
library;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter_test/flutter_test.dart';

final class _Game extends FlameGame with HasCollisionDetection {}

final class _Rock extends Object3dComponent with CollisionCallbacks {
  _Rock(Scene scene, Vector2 at)
    : super(
        node: MeshNode(
          CpuMesh(CuboidShape(size: Vector3.all(1.0)).build()),
          engine.Material(),
        ),
        scene: scene,
        plane: BridgePlane.ground(),
        direction: SyncDirection.flameToScene,
        position: at,
        size: Vector2.all(1.0),
        anchor: Anchor.center,
        children: <Component>[RectangleHitbox()],
      );

  PositionComponent? hitBy;

  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    hitBy = other;
  }
}

WrapSpace _space(Scene scene) => WrapSpace(
  min: Vector2(-10.0, -10.0),
  max: Vector2(10.0, 10.0),
  scene: scene,
);

void main() {
  testWithGame<_Game>(
    'what leaves by one edge comes back by the other',
    _Game.new,
    (game) async {
      final scene = Scene();
      final space = _space(scene);
      final rock = _Rock(scene, Vector2(10.5, -3.0));
      space.add(rock);
      await game.add(space);
      await game.ready();
      game.update(1 / 60);
      expect(rock.position.x, closeTo(-9.5, 1e-9));
      expect(
        space.shortestWay(Vector2(9.0, 0.0), Vector2(-9.0, 0.0)).x,
        closeTo(2.0, 1e-9),
      );
    },
  );

  testWithGame<_Game>(
    'a rock by the edge is drawn on the other side as well',
    _Game.new,
    (game) async {
      // Mutation: draw no ghost; the rock blinks from side to side.
      final scene = Scene();
      final space = _space(scene);
      final rock = _Rock(scene, Vector2(9.7, 0.0));
      space.add(rock);
      await game.add(space);
      await game.ready();
      game.update(1 / 60);

      final xs = <double>[
        for (final node in scene.root.childrenView) node.readPosition().x,
      ]..sort();
      expect(xs.first, closeTo(9.7 - 20.0, 1e-4), reason: 'the ghost');
      expect(xs.last, closeTo(9.7, 1e-4), reason: 'the rock');
    },
  );

  testWithGame<_Game>(
    'a shot on one side hits a rock on the other, across the seam',
    _Game.new,
    (game) async {
      // Mutation: give the ghosts no hitboxes.
      final scene = Scene();
      final space = _space(scene);
      final rock = _Rock(scene, Vector2(9.8, 0.0));
      final shot = _Rock(scene, Vector2(-9.9, 0.0));
      await space.addAll(<Component>[rock, shot]);
      await game.add(space);
      await game.ready();
      for (var i = 0; i < 3; i++) {
        game.update(1 / 60);
        await game.ready();
      }
      expect(rock.hitBy, same(shot));
    },
  );
}
