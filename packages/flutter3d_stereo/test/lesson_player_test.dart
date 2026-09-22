/// `edu-06`: the same `edu-00` lesson a step panel authors, played back
/// through a [StereoRig] and a button — proven the same way `stereo_rig_test.dart`
/// already proves the rig itself, by reading world positions off the eyes
/// rather than by rendering a frame.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
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
  group('applyLessonStep', () {
    test('moves the stage to the step\'s own position and yaw', () {
      final scene = Scene();
      final rig = StereoRig();
      scene.add(rig.stage);
      final steps = _teardownSteps();

      applyLessonStep(rig, steps[1]);

      final world = rig.stage.readWorldPosition();
      expect(world.x, closeTo(1.0, 1e-9));
      expect(world.z, closeTo(2.0, 1e-9));
    });

    test('shows names in "visible" and hides names in "hidden", leaving '
        'names the step never mentions untouched', () {
      final scene = Scene();
      final rig = StereoRig();
      scene.add(rig.stage);
      final cover = SceneNode(name: 'cover');
      final block = SceneNode(name: 'block');
      final untouched = SceneNode(name: 'untouched')..visible = false;
      final nodes = <String, SceneNode>{
        'cover': cover,
        'block': block,
        'untouched': untouched,
      };
      final steps = _teardownSteps();

      applyLessonStep(rig, steps[0], nodes: nodes);
      expect(cover.visible, isTrue);

      applyLessonStep(rig, steps[1], nodes: nodes);
      expect(cover.visible, isFalse, reason: 'step-2 hides it');
      expect(block.visible, isTrue, reason: 'step-2 shows it');
      expect(untouched.visible, isFalse, reason: 'step-2 never names it');
    });

    group('offsets — edu-00 §6\'s layered teardown', () {
      test(
        'a node named in offsets moves to rest position plus the offset',
        () {
          final scene = Scene();
          final rig = StereoRig();
          scene.add(rig.stage);
          final valveCover = SceneNode(name: 'valve_cover')
            ..setPosition(0.2, 0.5, -0.1);
          final nodes = <String, SceneNode>{
            'engine-body#valve_cover': valveCover,
          };
          final restPositions = <String, Vector3>{
            'engine-body#valve_cover': Vector3(0.2, 0.5, -0.1),
          };
          final step = EntityDef(
            type: 'edu_step',
            name: 'step-2',
            position: Vector3.zero(),
            properties: <String, Object?>{
              'offsets': <String, Object?>{
                'engine-body#valve_cover': <double>[0.0, 0.35, 0.0],
              },
            },
          );

          applyLessonStep(
            rig,
            step,
            nodes: nodes,
            restPositions: restPositions,
          );

          final world = valveCover.readWorldPosition();
          expect(world.x, closeTo(0.2, 1e-6));
          expect(
            world.y,
            closeTo(0.85, 1e-6),
            reason: 'rest 0.5 + offset 0.35',
          );
          expect(world.z, closeTo(-0.1, 1e-6));
        },
      );

      test('a node with no record in this step\'s offsets returns to rest — '
          'offsets is full state, not a diff', () {
        final scene = Scene();
        final rig = StereoRig();
        scene.add(rig.stage);
        final valveCover = SceneNode(name: 'valve_cover');
        final nodes = <String, SceneNode>{
          'engine-body#valve_cover': valveCover,
        };
        final restPositions = <String, Vector3>{
          'engine-body#valve_cover': Vector3(0.2, 0.5, -0.1),
        };
        final disassembled = EntityDef(
          type: 'edu_step',
          name: 'step-2',
          position: Vector3.zero(),
          properties: <String, Object?>{
            'offsets': <String, Object?>{
              'engine-body#valve_cover': <double>[0.0, 0.35, 0.0],
            },
          },
        );
        final reassembled = EntityDef(
          type: 'edu_step',
          name: 'step-3',
          position: Vector3.zero(),
          properties: const <String, Object?>{'caption': 'Back together'},
        );

        applyLessonStep(
          rig,
          disassembled,
          nodes: nodes,
          restPositions: restPositions,
        );
        expect(
          valveCover.readWorldPosition().y,
          closeTo(0.85, 1e-6),
          reason: 'disassembled',
        );

        applyLessonStep(
          rig,
          reassembled,
          nodes: nodes,
          restPositions: restPositions,
        );
        expect(
          valveCover.readWorldPosition(),
          equals(Vector3(0.2, 0.5, -0.1)),
          reason: 'step-3 names no offset for it, so it is back at rest',
        );
      });
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
      final rig = StereoRig();
      scene.add(rig.stage);
      player.applyCurrent(rig); // must not throw
    });

    test('applyCurrent moves both eyes with the stage, the same way '
        'stereo_rig_test.dart already proves for a manual setPosition', () {
      final scene = Scene();
      final rig = StereoRig(interpupillaryDistance: 0.064);
      scene.add(rig.stage);
      // Same yaw on both steps, so the stage's move is the only thing that
      // can shift the eyes — a differing yaw also turns the ±0.032 inter-eye
      // offset, which the "shifts by exactly the stage's move" test below is
      // deliberately not about.
      final steps = <EntityDef>[
        EntityDef(
          type: 'edu_step',
          name: 'a',
          position: Vector3(0.0, 1.6, 3.0),
        ),
        EntityDef(
          type: 'edu_step',
          name: 'b',
          position: Vector3(1.0, 1.6, 3.0),
        ),
      ];
      final player = LessonPlayer(steps);

      player.applyCurrent(rig);
      final firstLeftX = rig.camera(Eye.left).readWorldPosition().x;

      player.next();
      player.applyCurrent(rig);
      final secondLeftX = rig.camera(Eye.left).readWorldPosition().x;

      // The stage moved from x=0 to x=1; the inter-eye offset (±0.032) rides
      // along with it unchanged, so both eyes' world positions shift by
      // exactly that.
      expect(secondLeftX - firstLeftX, closeTo(1.0, 1e-6));
    });

    test('a yaw change on the step turns the head, which also turns the '
        'inter-eye offset — a real effect this player does not paper over', () {
      final scene = Scene();
      final rig = StereoRig(interpupillaryDistance: 0.064);
      scene.add(rig.stage);
      final player = LessonPlayer(_teardownSteps());

      player.applyCurrent(rig);
      final firstLeftX = rig.camera(Eye.left).readWorldPosition().x;

      player.next(); // step-2 also turns yaw from 0.0 to 1.2
      player.applyCurrent(rig);
      final secondLeftX = rig.camera(Eye.left).readWorldPosition().x;

      // Not exactly the 1.0 metre the stage itself moved — the turned head
      // also swings the eye offset, so the two effects add up to something
      // else, and that something else is what a real rig would show too.
      expect(secondLeftX - firstLeftX, isNot(closeTo(1.0, 1e-6)));
    });
  });
}
