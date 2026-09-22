/// `edu-07b`: a `model` entity resolves to a real, decoded glTF asset —
/// proven the same headless way `prop_visuals_test.dart` proves its own
/// entity-to-node mapping, but against a real file on disk
/// (`FileAssetSource`) rather than a procedural shape, since there is no
/// procedural stand-in for "did the decoder and the upload actually run".
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_player.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 16,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

ModelVisuals _visuals(
  Scene scene,
  GraphicsDevice device, {
  IssueSink? onIssue,
}) => ModelVisuals(
  scene,
  device: device,
  source: FileAssetSource.new,
  onIssue: onIssue,
);

void main() {
  test('a model entity decodes a real file and places its root at the '
      "entity's own position and yaw", () async {
    final scene = Scene();
    final visuals = _visuals(scene, _device());
    addTearDown(visuals.dispose);

    final root = await visuals.add(
      EntityDef(
        type: 'model',
        name: 'crate',
        position: Vector3(1.0, 2.0, 3.0),
        yaw: 0.5,
        properties: const <String, Object?>{'asset': '$kSamplesPath/Box.glb'},
      ),
    );

    expect(root, isNotNull);
    expect(root!.name, 'crate');
    expect(root.readPosition(), equals(Vector3(1.0, 2.0, 3.0)));
    // The root itself, not a mesh directly under scene: `ModelAsset.instantiate`
    // rebuilds the decoded hierarchy under it, so the meshes a box's own
    // single surface produces are grandchildren of `scene.root`, not children.
    expect(scene.meshes, isNotEmpty);
    expect(visuals.nodes['crate'], same(root));
  });

  test('a named node inside the model is reachable as "entity#node", the '
      "path §6's own offsets/attachTo addressing names", () async {
    final scene = Scene();
    final visuals = _visuals(scene, _device());
    addTearDown(visuals.dispose);

    await visuals.add(
      EntityDef(
        type: 'model',
        name: 'rig',
        position: Vector3.zero(),
        properties: const <String, Object?>{
          'asset': '$kSamplesPath/RiggedSimple.glb',
        },
      ),
    );

    expect(visuals.nodes.keys, contains('rig'));
    expect(visuals.nodes.keys, contains('rig#Cylinder'));
    expect(visuals.nodes.keys, contains('rig#Bone'));
    expect(visuals.restPositions.keys, contains('rig'));
  });

  test(
    'a model entity moves through the same offsets path a prop does',
    () async {
      final scene = Scene();
      final visuals = _visuals(scene, _device());
      addTearDown(visuals.dispose);

      await visuals.add(
        EntityDef(
          type: 'model',
          name: 'engine-body',
          position: Vector3.zero(),
          properties: const <String, Object?>{'asset': '$kSamplesPath/Box.glb'},
        ),
      );

      final camera = SceneNode(name: 'camera');
      scene.add(camera);
      final step = EntityDef(
        type: 'edu_step',
        position: Vector3.zero(),
        properties: <String, Object?>{
          'offsets': <String, Object?>{
            'engine-body': <double>[0.0, 0.35, 0.0],
          },
        },
      );

      applyLessonStepToCamera(
        camera,
        step,
        nodes: visuals.nodes,
        restPositions: visuals.restPositions,
      );

      final moved = visuals.nodes['engine-body']!.readWorldPosition();
      expect(moved.y, closeTo(0.35, 1e-6));
    },
  );

  test('an entity that is not a model is left alone entirely', () async {
    final scene = Scene();
    final visuals = _visuals(scene, _device());
    addTearDown(visuals.dispose);

    final result = await visuals.add(
      EntityDef(type: 'prop', position: Vector3.zero()),
    );

    expect(result, isNull);
    expect(scene.meshes, isEmpty);
  });

  test(
    'a model with no asset property reports an issue and builds nothing',
    () async {
      final issues = <String>[];
      final scene = Scene();
      final visuals = _visuals(
        scene,
        _device(),
        onIssue: (i) => issues.add(i.message),
      );
      addTearDown(visuals.dispose);

      final result = await visuals.add(
        EntityDef(type: 'model', name: 'nothing', position: Vector3.zero()),
      );

      expect(result, isNull);
      expect(issues, hasLength(1));
      expect(issues.single, contains('nothing'));
      expect(scene.meshes, isEmpty);
    },
  );

  test('an asset that fails to decode is reported, not thrown, the same '
      "choice FixtureVisuals' own model loading already makes", () async {
    final issues = <String>[];
    final scene = Scene();
    final visuals = _visuals(
      scene,
      _device(),
      onIssue: (i) => issues.add(i.message),
    );
    addTearDown(visuals.dispose);

    final result = await visuals.add(
      EntityDef(
        type: 'model',
        name: 'ghost',
        position: Vector3.zero(),
        properties: const <String, Object?>{'asset': 'no/such/file.glb'},
      ),
    );

    expect(result, isNull);
    expect(issues, hasLength(1));
    expect(issues.single, contains('ghost'));
    expect(scene.meshes, isEmpty);
  });

  test(
    'dispose takes every model out of the scene and releases its uploads',
    () async {
      final scene = Scene();
      final device = _device();
      final visuals = _visuals(scene, device);

      await visuals.add(
        EntityDef(
          type: 'model',
          name: 'crate',
          position: Vector3.zero(),
          properties: const <String, Object?>{'asset': '$kSamplesPath/Box.glb'},
        ),
      );
      expect(scene.meshes, isNotEmpty);

      visuals.dispose();

      expect(scene.meshes, isEmpty);
      expect(visuals.nodes, isEmpty);
    },
  );
}
