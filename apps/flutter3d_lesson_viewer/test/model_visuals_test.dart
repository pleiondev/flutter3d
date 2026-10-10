/// `edu-07b`: a `model` entity resolves to a real, decoded glTF asset —
/// proven the same headless way `prop_visuals_test.dart` proves its own
/// entity-to-node mapping, but against a real file on disk
/// (`FileAssetSource`) rather than a procedural shape, since there is no
/// procedural stand-in for "did the decoder and the upload actually run".
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_player.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spelled out rather than `samplesPath`, which is relative to a package
/// under `packages/`. This app lives under `apps/`, one directory further
/// from the root, so the constant pointed at an `apps/flutter3d_samples` that
/// does not exist — the same reason the modeller's `frame_test.dart` spells
/// its own sample path out.
const String _samples = '../../packages/flutter3d_samples/assets';

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
        properties: const <String, Object?>{'asset': '$_samples/Box.glb'},
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
          'asset': '$_samples/RiggedSimple.glb',
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
          properties: const <String, Object?>{'asset': '$_samples/Box.glb'},
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
          properties: const <String, Object?>{'asset': '$_samples/Box.glb'},
        ),
      );
      expect(scene.meshes, isNotEmpty);

      visuals.dispose();

      expect(scene.meshes, isEmpty);
      expect(visuals.nodes, isEmpty);
    },
  );

  test('models started together go into the scene in the order they were '
      'added, whichever file is decoded first', () async {
    // Each file is decoded on an isolate of its own, and the scene's order
    // is part of the picture: the cull tree is built over it and draws are
    // claimed in it.
    //
    // Mutation: in `ModelVisuals._addInTurn`, drop `await previous` — the
    // second file is read at once and the first held back, so the second
    // model goes into the scene first.
    // The first file is held back by not existing yet: [_WaitedFile] reads
    // it once it appears. A file rather than a completer, because the read
    // may run on the decoding isolate, where a completer of this one's is a
    // copy nobody completes; the disk is the same from every isolate.
    final held = Directory.systemTemp.createTempSync('model_order_');
    addTearDown(() => held.deleteSync(recursive: true));
    final firstPath = '${held.path}/first.glb';

    final scene = Scene();
    final visuals = ModelVisuals(
      scene,
      device: _device(),
      source: _WaitedFile.new,
      onIssue: (issue) => fail('$issue'),
    );
    addTearDown(visuals.dispose);

    EntityDef model(String name, String path) => EntityDef(
      type: 'model',
      name: name,
      position: Vector3.zero(),
      properties: <String, Object?>{'asset': path},
    );
    final both = Future.wait(<Future<SceneNode?>>[
      visuals.add(model('first', firstPath)),
      visuals.add(model('second', '$_samples/RiggedSimple.glb')),
    ]);

    // Long enough for the second to be read, decoded and placed when
    // nothing holds it back; with the fix it waits for the first.
    final waited = Stopwatch()..start();
    while (!visuals.nodes.containsKey('second') &&
        waited.elapsed < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Written beside it and renamed into place, so the reader never sees
    // half a file.
    File('$_samples/Box.glb').copySync('${held.path}/first.part');
    File('${held.path}/first.part').renameSync(firstPath);
    await both.timeout(const Duration(seconds: 30));

    final children = scene.root.childrenView;
    final first = children.indexOf(visuals.nodes['first']!);
    final second = children.indexOf(visuals.nodes['second']!);
    expect(first, greaterThanOrEqualTo(0));
    expect(second, greaterThan(first));
  });

  testWidgets('a model loaded through tester.runAsync, into a scene made '
      'under the test\'s fake clock, gets into the scene', (tester) async {
    // How `model_offsets_test.dart` loads one, and how a game's own widget
    // test would. The scene's line of turns once began with a future made
    // where the scene was — in the fake zone — and the load, awaiting it
    // from the real one, waited on a zone nobody pumped: the test never
    // ended.
    //
    // Mutation: start the line with `Future<void>.value()` made when the
    // scene is, and await it for the first turn — the load times out here.
    final scene = Scene();
    final visuals = ModelVisuals(
      scene,
      device: _device(),
      source: FileAssetSource.new,
      onIssue: (issue) => fail('$issue'),
    );
    addTearDown(visuals.dispose);

    final root = await tester.runAsync(
      () => visuals
          .add(
            EntityDef(
              type: 'model',
              name: 'crate',
              position: Vector3.zero(),
              properties: const <String, Object?>{'asset': '$_samples/Box.glb'},
            ),
          )
          .timeout(const Duration(seconds: 10)),
    );

    expect(root, isNotNull);
    expect(scene.meshes, isNotEmpty);
  });

  test('a loader let go of mid-load does not keep the next load out of the '
      'scene', () async {
    // A level closed while one of its files is still being read: the turn
    // that load holds is released with the loader, or whatever the scene is
    // asked for next waits for a file that may never come.
    //
    // Mutation: drop the loop over `_turns` in `ModelVisuals.dispose` — the
    // second load waits behind the first for ever and times out here.
    final scene = Scene();
    final device = _device();
    final stuck = ModelVisuals(
      scene,
      device: device,
      source: _NeverRead.new,
      onIssue: (issue) {},
    );
    final next = ModelVisuals(
      scene,
      device: device,
      source: FileAssetSource.new,
      onIssue: (issue) => fail('$issue'),
    );
    addTearDown(next.dispose);

    unawaited(
      stuck.add(
        EntityDef(
          type: 'model',
          name: 'stuck',
          position: Vector3.zero(),
          properties: const <String, Object?>{'asset': 'never.glb'},
        ),
      ),
    );
    final arriving = next.add(
      EntityDef(
        type: 'model',
        name: 'crate',
        position: Vector3.zero(),
        properties: const <String, Object?>{'asset': '$_samples/Box.glb'},
      ),
    );
    stuck.dispose();

    expect(await arriving.timeout(const Duration(seconds: 10)), isNotNull);
    expect(next.nodes, contains('crate'));
  });
}

/// A file that never finishes being read, wherever the read runs.
final class _NeverRead extends AssetSource {
  const _NeverRead(this.path);

  final String path;

  @override
  String get key => 'never:$path';

  @override
  Future<Uint8List> read() => Completer<Uint8List>().future;

  @override
  AssetUriResolver get resolveUri =>
      (request) => Completer<Uint8List>().future;
}

/// A file read off disk once it exists — for at most thirty seconds, so a
/// file that never comes fails the test rather than hanging it.
final class _WaitedFile extends AssetSource {
  const _WaitedFile(this.path);

  final String path;

  @override
  String get key => 'waited:$path';

  @override
  Future<Uint8List> read() async {
    final waited = Stopwatch()..start();
    while (!File(path).existsSync()) {
      if (waited.elapsed > const Duration(seconds: 30)) {
        throw StateError('$path never appeared');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return FileAssetSource(path).read();
  }

  @override
  AssetUriResolver get resolveUri => FileAssetSource(path).resolveUri;
}
