/// The rest of Flame's transform crossing into the scene: after the effects
/// that move it, from wherever in Flame's tree the component sits, off the
/// plane, scaled, shown or hidden, and with a node under it the bridge leaves
/// alone. Run in a mounted game, because effects and parents are what is
/// being tested and neither does anything outside one.
library;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';

Object3dComponent _bridged(
  Scene scene, {
  Vector2? position,
  BridgePlane? plane,
  double elevation = 0.0,
}) => Object3dComponent(
  node: SceneNode(name: 'bridged'),
  scene: scene,
  plane: plane ?? BridgePlane.ground(),
  direction: SyncDirection.flameToScene,
  elevation: elevation,
  position: position,
);

void main() {
  testWithGame<FlameGame>(
    'an effect\'s move reaches the scene in the frame it happens',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final component = _bridged(scene)
        ..add(
          MoveEffect.by(Vector2(10.0, 0.0), EffectController(duration: 1.0)),
        );
      await game.add(component);
      await game.ready();

      game.update(0.5);
      // Synced in `update`, before the effect ran, this read 0.
      expect(component.position.x, closeTo(5.0, 1e-6));
      expect(component.node.readPosition().x, closeTo(5.0, 1e-6));
    },
  );

  testWithGame<FlameGame>(
    'a component nested in another lands where Flame draws it',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final log = PositionComponent(position: Vector2(10.0, 4.0));
      final frog = _bridged(scene, position: Vector2(1.0, 0.0));
      await game.add(log);
      await log.add(frog);
      await game.ready();

      game.update(0.0);
      expect(frog.node.readPosition(), Vector3(11.0, 0.0, 4.0));

      log.position.x = 20.0;
      game.update(0.0);
      expect(frog.node.readPosition().x, closeTo(21.0, 1e-6));
    },
  );

  testWithGame<FlameGame>(
    'flowing the other way, a nested component reads its parent\'s space',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final holder = PositionComponent(position: Vector2(10.0, 0.0));
      final node = SceneNode()..setPosition(12.0, 0.0, 3.0);
      final body = Object3dComponent(
        node: node,
        scene: scene,
        plane: BridgePlane.ground(),
      );
      await game.add(holder);
      await holder.add(body);
      await game.ready();

      game.update(0.0);
      expect(body.position, Vector2(2.0, 3.0));
      expect(body.absolutePosition, Vector2(12.0, 3.0));
    },
  );

  testWithGame<FlameGame>(
    'elevation lifts the node off the plane, and scenePosition says where',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final jet = _bridged(
        scene,
        position: Vector2(2.0, -5.0),
        plane: BridgePlane.ground(height: 0.5),
        elevation: 1.2,
      );
      await game.add(jet);
      await game.ready();

      game.update(0.0);
      expect(jet.node.readPosition().y, closeTo(1.7, 1e-6));
      expect(jet.scenePosition, jet.node.readPosition());

      jet.elevation = 0.0;
      game.update(0.0);
      expect(jet.node.readPosition().y, closeTo(0.5, 1e-6));
    },
  );

  testWithGame<FlameGame>(
    'Flame\'s scale scales the node, the normal by the mean of the two',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final rock = _bridged(scene)..scale = Vector2(2.0, 3.0);
      final sign = _bridged(scene, plane: BridgePlane.backdrop())
        ..scale = Vector2(2.0, 4.0);
      await game.addAll(<Component>[rock, sign]);
      await game.ready();

      game.update(0.0);
      expect(rock.node.readScale(), Vector3(2.0, 2.5, 3.0));
      expect(sign.node.readScale(), Vector3(2.0, 4.0, 3.0));
    },
  );

  testWithGame<FlameGame>(
    'Flame\'s visibility is written when it changes, and only then',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final ship = _bridged(scene);
      await game.add(ship);
      await game.ready();

      ship.isVisible = false;
      game.update(0.0);
      expect(ship.node.visible, isFalse);

      ship.isVisible = true;
      game.update(0.0);
      expect(ship.node.visible, isTrue);

      // Blinking the node by hand, as a hit flash does, is left alone.
      ship.node.visible = false;
      game.update(0.0);
      expect(ship.node.visible, isFalse);
    },
  );

  testWithGame<FlameGame>(
    'a component let go stops being drawn at once',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final shot = _bridged(scene);
      await game.add(shot);
      await game.ready();
      game.update(0.0);
      expect(shot.node.visible, isTrue);

      shot.removeFromParent();
      // Before Flame has processed the removal: already hidden.
      expect(shot.node.visible, isFalse);
      await game.ready();
      expect(shot.node.parent, isNull);
    },
  );

  testWithGame<FlameGame>(
    'the visual node is made on demand, under the node, and left alone',
    FlameGame.new,
    (game) async {
      final scene = Scene();
      final craft = _bridged(scene)..angle = 0.7;
      await game.add(craft);
      await game.ready();

      final visual = craft.visual;
      expect(craft.visual, same(visual));
      expect(visual.parent, same(craft.node));

      final bank = Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), 0.4);
      visual.setRotation(bank);
      game.update(0.1);
      expect(visual.readRotation().z, closeTo(bank.z, 1e-6));
      expect(craft.node.readRotation().z, isNot(closeTo(bank.z, 1e-6)));
    },
  );
}
