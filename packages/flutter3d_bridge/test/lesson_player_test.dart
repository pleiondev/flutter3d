/// `edu-02`: the same `edu-00` lesson `edu-06`'s stereo test proves against a
/// [StereoRig], proven here against a plain [SceneNode] camera — read world
/// positions off the node rather than rendering a frame.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

List<EntityDef> _teardownSteps() => <EntityDef>[
  EntityDef(
    type: 'edu_step',
    name: 'step-1',
    position: Vector3(0.0, 1.6, 3.0),
    yaw: 0.0,
    properties: <String, Object?>{
      'caption': 'Whole engine',
      'visible': <String>['cover'],
    },
  ),
  EntityDef(
    type: 'edu_step',
    name: 'step-2',
    position: Vector3(1.0, 1.6, 2.0),
    yaw: 1.2,
    properties: <String, Object?>{
      'caption': 'Cover removed',
      'hidden': <String>['cover'],
      'visible': <String>['block'],
    },
  ),
  EntityDef(
    type: 'edu_step',
    name: 'step-3',
    position: Vector3(2.0, 1.6, 1.0),
    yaw: 2.4,
    properties: <String, Object?>{'caption': 'Block exposed'},
  ),
];

void main() {
  group('applyLessonStepToCamera', () {
    test('moves the camera to the step\'s own position and yaw', () {
      final scene = Scene();
      final camera = SceneNode(name: 'camera');
      scene.add(camera);
      final steps = _teardownSteps();

      applyLessonStepToCamera(camera, steps[1]);

      final world = camera.readWorldPosition();
      expect(world.x, closeTo(1.0, 1e-9));
      expect(world.z, closeTo(2.0, 1e-9));
    });

    test('shows names in "visible" and hides names in "hidden", leaving '
        'names the step never mentions untouched', () {
      final scene = Scene();
      final camera = SceneNode(name: 'camera');
      scene.add(camera);
      final cover = SceneNode(name: 'cover');
      final block = SceneNode(name: 'block');
      final untouched = SceneNode(name: 'untouched')..visible = false;
      final nodes = <String, SceneNode>{
        'cover': cover,
        'block': block,
        'untouched': untouched,
      };
      final steps = _teardownSteps();

      applyLessonStepToCamera(camera, steps[0], nodes: nodes);
      expect(cover.visible, isTrue);

      applyLessonStepToCamera(camera, steps[1], nodes: nodes);
      expect(cover.visible, isFalse, reason: 'step-2 hides it');
      expect(block.visible, isTrue, reason: 'step-2 shows it');
      expect(untouched.visible, isFalse, reason: 'step-2 never names it');
    });
  });

  group('LessonPlayer', () {
    test('starts on the first step and clamps at both ends', () {
      final player = LessonPlayer(_teardownSteps());
      expect(player.current!.name, 'step-1');
      expect(player.isFirst, isTrue);
      expect(player.isLast, isFalse);

      player.previous();
      expect(player.current!.name, 'step-1', reason: 'clamped, not wrapped');

      player.next();
      player.next();
      expect(player.current!.name, 'step-3');
      expect(player.isLast, isTrue);

      player.next();
      expect(player.current!.name, 'step-3', reason: 'clamped, not wrapped');
    });

    test('an empty lesson has no current step and applies as a no-op', () {
      final player = LessonPlayer(const <EntityDef>[]);
      expect(player.current, isNull);
      expect(player.isFirst, isTrue);
      expect(player.isLast, isTrue);

      final scene = Scene();
      final camera = SceneNode(name: 'camera');
      scene.add(camera);
      player.applyCurrent(camera); // must not throw
    });

    test('applyCurrent moves the camera to each step in turn', () {
      final scene = Scene();
      final camera = SceneNode(name: 'camera');
      scene.add(camera);
      final player = LessonPlayer(_teardownSteps());

      player.applyCurrent(camera);
      expect(camera.readWorldPosition().x, closeTo(0.0, 1e-9));

      player.next();
      player.applyCurrent(camera);
      expect(camera.readWorldPosition().x, closeTo(1.0, 1e-9));

      player.next();
      player.applyCurrent(camera);
      expect(camera.readWorldPosition().x, closeTo(2.0, 1e-9));
    });
  });
}
