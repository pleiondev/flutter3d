/// `edu-07`: a `prop` entity as one individually addressable [MeshNode],
/// not batched the way a brush is — proven the same headless way
/// `widget_surface_visuals_test.dart` proves its own entity-to-node mapping.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 16,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test(
    'a prop entity becomes its own named MeshNode, drawn but not batched',
    () {
      final scene = Scene();
      final device = _device();
      final level = Level(
        materials: <String, LevelMaterial>{
          'valve-red': LevelMaterial(baseColor: Vector4(0.8, 0.1, 0.1, 1.0)),
        },
      );
      final visuals = PropVisuals(scene, device: device, level: level);
      addTearDown(visuals.dispose);

      final entity = EntityDef(
        type: 'prop',
        name: 'valve-cover',
        position: Vector3(1.0, 2.0, 3.0),
        yaw: 0.5,
        properties: const <String, Object?>{'material': 'valve-red'},
      );

      final node = visuals.add(entity);

      expect(node, isNotNull);
      expect(node!.name, 'valve-cover');
      expect(scene.meshes, contains(node));
      expect(node.readPosition(), equals(Vector3(1.0, 2.0, 3.0)));
      expect(node.material.baseColor, equals(Vector4(0.8, 0.1, 0.1, 1.0)));
    },
  );

  test('an entity that is not a prop is left alone entirely', () {
    final scene = Scene();
    final visuals = PropVisuals(scene, device: _device(), level: Level());
    addTearDown(visuals.dispose);

    final result = visuals.add(
      EntityDef(type: 'player_spawn', position: Vector3.zero()),
    );

    expect(result, isNull);
    expect(scene.meshes, isEmpty);
  });

  test('the built node is reachable by name for visible/hidden/offsets', () {
    final scene = Scene();
    final visuals = PropVisuals(scene, device: _device(), level: Level());
    addTearDown(visuals.dispose);

    visuals.add(
      EntityDef(
        type: 'prop',
        name: 'engine-body#valve_cover',
        position: Vector3(0.2, 0.5, -0.1),
      ),
    );

    expect(visuals.nodes.keys, contains('engine-body#valve_cover'));
    expect(
      visuals.restPositions['engine-body#valve_cover'],
      equals(Vector3(0.2, 0.5, -0.1)),
    );

    final camera = SceneNode(name: 'camera');
    scene.add(camera);
    final step = EntityDef(
      type: 'edu_step',
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
      nodes: visuals.nodes,
      restPositions: visuals.restPositions,
    );

    final moved = visuals.nodes['engine-body#valve_cover']!.readWorldPosition();
    expect(moved.y, closeTo(0.85, 1e-6), reason: 'rest 0.5 + offset 0.35');
  });

  test('an unnamed prop is drawn but absent from the addressable maps', () {
    final scene = Scene();
    final visuals = PropVisuals(scene, device: _device(), level: Level());
    addTearDown(visuals.dispose);

    final node = visuals.add(
      EntityDef(type: 'prop', position: Vector3(1.0, 1.0, 1.0)),
    );

    expect(node, isNotNull);
    expect(scene.meshes, contains(node));
    expect(visuals.nodes, isEmpty);
    expect(visuals.restPositions, isEmpty);
  });

  group('shapes', () {
    test('defaults to a box the size the entity names', () {
      final scene = Scene();
      final visuals = PropVisuals(scene, device: _device(), level: Level());
      addTearDown(visuals.dispose);

      final node = visuals.add(
        EntityDef(
          type: 'prop',
          name: 'box',
          position: Vector3.zero(),
          properties: <String, Object?>{
            'size': <double>[2.0, 1.0, 2.0],
          },
        ),
      );

      // A box built at the named size has bounds half that size in every
      // direction from its own local origin.
      final bounds = node!.mesh.bounds;
      expect(bounds.max.x - bounds.min.x, closeTo(2.0, 1e-6));
      expect(bounds.max.y - bounds.min.y, closeTo(1.0, 1e-6));
    });

    test('a sphere reads its own radius', () {
      final scene = Scene();
      final visuals = PropVisuals(scene, device: _device(), level: Level());
      addTearDown(visuals.dispose);

      final node = visuals.add(
        EntityDef(
          type: 'prop',
          name: 'ball',
          position: Vector3.zero(),
          properties: const <String, Object?>{'shape': 'sphere', 'radius': 0.5},
        ),
      );

      final bounds = node!.mesh.bounds;
      expect(bounds.max.x - bounds.min.x, closeTo(1.0, 1e-3));
    });
  });

  group('setMaterial — ls-i-01\'s retint', () {
    test('swaps a named prop\'s material to another named in the level', () {
      final scene = Scene();
      final level = Level(
        materials: <String, LevelMaterial>{
          'red': LevelMaterial(baseColor: Vector4(0.8, 0.1, 0.1, 1.0)),
          'blue': LevelMaterial(baseColor: Vector4(0.1, 0.1, 0.8, 1.0)),
        },
      );
      final visuals = PropVisuals(scene, device: _device(), level: level);
      addTearDown(visuals.dispose);
      visuals.add(
        EntityDef(
          type: 'prop',
          name: 'product',
          position: Vector3.zero(),
          properties: const <String, Object?>{'material': 'red'},
        ),
      );

      visuals.setMaterial('product', 'blue');

      expect(
        (visuals.nodes['product']! as MeshNode).material.baseColor,
        equals(Vector4(0.1, 0.1, 0.8, 1.0)),
      );
    });

    test('does nothing for a prop name this never built', () {
      final scene = Scene();
      final visuals = PropVisuals(
        scene,
        device: _device(),
        level: Level(
          materials: <String, LevelMaterial>{'blue': LevelMaterial()},
        ),
      );
      addTearDown(visuals.dispose);

      expect(
        () => visuals.setMaterial('nothing-here', 'blue'),
        returnsNormally,
      );
    });

    test('does nothing for a material the level does not have', () {
      final scene = Scene();
      final visuals = PropVisuals(scene, device: _device(), level: Level());
      addTearDown(visuals.dispose);
      visuals.add(
        EntityDef(type: 'prop', name: 'product', position: Vector3.zero()),
      );
      final before = (visuals.nodes['product']! as MeshNode).material;

      visuals.setMaterial('product', 'not-a-real-material');

      expect((visuals.nodes['product']! as MeshNode).material, same(before));
    });
  });

  test('dispose removes every prop from the scene, named or not', () {
    final scene = Scene();
    final visuals = PropVisuals(scene, device: _device(), level: Level());

    visuals.add(EntityDef(type: 'prop', name: 'a', position: Vector3.zero()));
    visuals.add(EntityDef(type: 'prop', position: Vector3.zero()));
    expect(scene.meshes.length, 2);

    visuals.dispose();

    expect(scene.meshes, isEmpty);
    expect(visuals.nodes, isEmpty);
  });
}
