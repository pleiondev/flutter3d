/// `edu-02`: the same `edu-00` lesson `edu-06`'s stereo test proves against a
/// [StereoRig], proven here against a plain [SceneNode] camera — read world
/// positions off the node rather than rendering a frame.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

MeshNode _meshNode(GraphicsDevice device, {String? name}) {
  final mesh = DeviceMesh.upload(device, CuboidShape().build());
  return MeshNode(mesh, Material(), name: name);
}

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

    group('offsets — edu-00 §6\'s layered teardown', () {
      test(
        'a node named in offsets moves to rest position plus the offset',
        () {
          final scene = Scene();
          final camera = SceneNode(name: 'camera');
          scene.add(camera);
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

          applyLessonStepToCamera(
            camera,
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
        final camera = SceneNode(name: 'camera');
        scene.add(camera);
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

        applyLessonStepToCamera(
          camera,
          disassembled,
          nodes: nodes,
          restPositions: restPositions,
        );
        expect(
          valveCover.readWorldPosition().y,
          closeTo(0.85, 1e-6),
          reason: 'disassembled',
        );

        applyLessonStepToCamera(
          camera,
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

      test('a node with no entry in restPositions is left alone entirely', () {
        final scene = Scene();
        final camera = SceneNode(name: 'camera');
        scene.add(camera);
        final untouched = SceneNode(name: 'untouched')
          ..setPosition(9.0, 9.0, 9.0);
        final step = EntityDef(
          type: 'edu_step',
          name: 'step-2',
          position: Vector3.zero(),
          properties: const <String, Object?>{
            'offsets': <String, Object?>{
              'engine-body#valve_cover': <double>[0.0, 0.35, 0.0],
            },
          },
        );

        applyLessonStepToCamera(
          camera,
          step,
          nodes: <String, SceneNode>{'untouched': untouched},
          restPositions: const <String, Vector3>{},
        );

        expect(untouched.readWorldPosition(), equals(Vector3(9.0, 9.0, 9.0)));
      });

      test('offsets absent from the document entirely is not an error', () {
        final scene = Scene();
        final camera = SceneNode(name: 'camera');
        scene.add(camera);
        final valveCover = SceneNode(name: 'valve_cover');
        final step = EntityDef(
          type: 'edu_step',
          name: 'step-1',
          position: Vector3.zero(),
          properties: const <String, Object?>{'caption': 'Whole engine'},
        );

        applyLessonStepToCamera(
          camera,
          step,
          nodes: <String, SceneNode>{'engine-body#valve_cover': valveCover},
          restPositions: <String, Vector3>{
            'engine-body#valve_cover': Vector3(0.2, 0.5, -0.1),
          },
        );

        expect(valveCover.readWorldPosition(), equals(Vector3(0.2, 0.5, -0.1)));
      });
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

  group('applyLessonStepBindings — edu-00 §9\'s live data', () {
    DataSourceRegistry sources(Object? Function(int step) sample) =>
        DataSourceRegistry(<String, EduDataSource>{
          'spindle-temp': SamplerDataSource(
            (step) => <String, Object?>{'value': sample(step)},
          ),
        });

    EntityDef bindingStep(String target) => EntityDef(
      type: 'edu_step',
      name: 'reading',
      position: Vector3.zero(),
      properties: <String, Object?>{
        'bindings': <Object?>[
          <String, Object?>{
            'source': 'spindle-temp',
            'path': 'value',
            'target': target,
          },
        ],
      },
    );

    test('"entity.at" writes a real position onto the named node', () {
      final node = SceneNode(name: 'gauge');
      applyLessonStepBindings(
        bindingStep('gauge.at'),
        10,
        sources((_) => <double>[1.0, 2.0, 3.0]),
        nodes: <String, SceneNode>{'gauge': node},
      );

      expect(node.readPosition(), equals(Vector3(1.0, 2.0, 3.0)));
    });

    test('"entity.yaw" turns the named node about Y', () {
      final node = SceneNode(name: 'needle');
      applyLessonStepBindings(
        bindingStep('needle.yaw'),
        10,
        sources((_) => 1.2),
        nodes: <String, SceneNode>{'needle': node},
      );

      final expected = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 1.2);
      final actual = node.readRotation();
      expect(actual.x, closeTo(expected.x, 1e-9));
      expect(actual.y, closeTo(expected.y, 1e-9));
      expect(actual.z, closeTo(expected.z, 1e-9));
      expect(actual.w, closeTo(expected.w, 1e-9));
    });

    test('"entity.material.emissiveStrength" writes a real material field', () {
      final device = _device();
      final node = _meshNode(device, name: 'lathe-body');
      applyLessonStepBindings(
        bindingStep('lathe-body.material.emissiveStrength'),
        10,
        sources((_) => 4.5),
        nodes: <String, SceneNode>{'lathe-body': node},
      );

      expect(node.material.emissiveStrength, 4.5);
    });

    test('"entity.material.emissiveColor" writes a 3-vector into emissive', () {
      final device = _device();
      final node = _meshNode(device, name: 'lathe-body');
      applyLessonStepBindings(
        bindingStep('lathe-body.material.emissiveColor'),
        10,
        sources((_) => <double>[1.0, 0.2, 0.0]),
        nodes: <String, SceneNode>{'lathe-body': node},
      );

      expect(node.material.emissive, equals(Vector3(1.0, 0.2, 0.0)));
    });

    test('a target naming a node this document has none for is skipped, '
        'not thrown', () {
      expect(
        () => applyLessonStepBindings(
          bindingStep('no-such-node.material.emissiveStrength'),
          10,
          sources((_) => 4.5),
        ),
        returnsNormally,
      );
    });

    test('a material target on a non-mesh node is skipped, not thrown', () {
      final node = SceneNode(name: 'not-a-mesh');
      expect(
        () => applyLessonStepBindings(
          bindingStep('not-a-mesh.material.emissiveStrength'),
          10,
          sources((_) => 4.5),
          nodes: <String, SceneNode>{'not-a-mesh': node},
        ),
        returnsNormally,
      );
    });

    test('the sample changes at a different step, so the write does too', () {
      final device = _device();
      final node = _meshNode(device, name: 'lathe-body');
      final step = bindingStep('lathe-body.material.emissiveStrength');
      final registry = sources((s) => 60.0 + s.toDouble());

      applyLessonStepBindings(
        step,
        10,
        registry,
        nodes: <String, SceneNode>{'lathe-body': node},
      );
      expect(node.material.emissiveStrength, 70.0);

      applyLessonStepBindings(
        step,
        20,
        registry,
        nodes: <String, SceneNode>{'lathe-body': node},
      );
      expect(node.material.emissiveStrength, 80.0);
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
