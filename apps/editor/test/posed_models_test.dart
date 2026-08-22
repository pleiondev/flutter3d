/// A model in an editor stands the way it stands in the game.
///
///     flutter test test/posed_models_test.dart
///
/// **A skinned model in a file is in its bind pose**: arms out, legs apart,
/// because that is the shape a rig is authored in and no exporter saves a
/// resting one. The crypt's runner measures three and a third metres across
/// like that, and its shooter collapses to three centimetres. The game never
/// shows either, because the game plays a clip on the first frame; the editor
/// did not, and what it drew was reported as "some mess inside the cube".
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String _runner = '../dungeon/assets/models/monster_runner.glb';

const int _width = 160;
const int _height = 160;

/// What the model covers on screen, as the editor draws it.
///
/// The silhouette rather than the bounds: `MeshNode.worldBounds` of a skinned
/// mesh is the bind pose's box and does not move when the pose does, which is
/// exactly the trap this test is about — the bounds said three metres either
/// way while the picture changed completely.
Future<({int width, int height, int pixels})> _shapeOf(
  String path, {
  required bool posed,
  String? save,
}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final document = await GltfLoader().load(File(path).readAsBytesSync());
  final asset = await ModelAsset.fromDocument(document, device: device);
  final scene = Scene();
  final instance = asset.instantiate(scene, name: 'model');

  if (posed) {
    final player = instance.player!;
    final clips = player.clipNames;
    final resting = clips.indexWhere(
      (String name) => name.toLowerCase().contains('idle'),
    );
    player.play(resting < 0 ? 0 : resting);
  }

  scene.add(
    LightNode(color: Vector3(1.0, 1.0, 1.0), intensity: 4.0)
      ..lookAt(Vector3(-0.3, -0.6, -1.0)),
  );
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 0.9,
      near: 0.05,
      far: 40.0,
    ),
  )..setPosition(0.0, 1.0, 4.0);
  camera.lookAt(Vector3(0.0, 1.0, 0.0));
  scene.add(camera);

  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(),
  );
  final pixels = (await device.readPixels(result.frame))!.buffer.asUint8List();
  if (save != null) {
    File(save).writeAsBytesSync(encodePng(pixels, _width, _height));
  }

  var left = _width, right = -1, top = _height, bottom = -1, count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] < 12 && pixels[i + 1] < 12 && pixels[i + 2] < 12) continue;
    final p = i ~/ 4;
    final x = p % _width;
    final y = p ~/ _width;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
    count++;
  }
  return (width: right - left + 1, height: bottom - top + 1, pixels: count);
}

void main() {
  test('a model with clips is posed on one of them', () async {
    // **`play` applies the first frame immediately**, which is what an editor
    // wants and what nothing here had asked for: the editor never animates, so
    // one call is the difference between a model standing the way the game
    // stands it and a model standing however the rig was authored.
    final device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final document =
        await GltfLoader().load(File(_runner).readAsBytesSync());
    final asset = await ModelAsset.fromDocument(document, device: device);
    final instance = asset.instantiate(Scene(), name: 'model');
    final player = instance.player!;

    expect(player.clipNames, contains('Idle'),
        reason: 'the clip an editor should rest a model on is gone');

    final joint = _deepestJoint(instance.root);
    final before = joint.worldMatrix.getTranslation();
    player.play(player.clipNames.indexOf('Idle'));
    final after = joint.worldMatrix.getTranslation();

    expect(after, isNot(before),
        reason: 'playing a clip moved nothing: the player is driving nodes '
            'that are not the ones in this instance');
  });

  test('and it is drawn, at the size the game draws it', () async {
    // The measurement that ended a wrong theory. These monsters *are* big —
    // the runner is three and a third metres across with its arms out, in the
    // game as much as here — so "a mess inside the cube" was a large model seen
    // from a metre away in an unlit room, not a broken pose.
    //
    // What is not a measurement of anything is `MeshNode.worldBounds` on a
    // skinned mesh: it is the bind pose's box and does not move when the pose
    // does. Anything asking how big one of these is has to ask the picture.
    final shape = await _shapeOf(_runner, posed: true, save: '/tmp/posed.png');

    expect(shape.pixels, greaterThan(400), reason: 'nothing was drawn');
    expect(shape.width, greaterThan(40));
    expect(shape.height, greaterThan(40));
  });
}

/// The joint furthest from the root, which is the one a pose moves most.
SceneNode _deepestJoint(SceneNode root) {
  SceneNode deepest = root;
  var best = -1;
  void walk(SceneNode at, int depth) {
    if (depth > best) {
      best = depth;
      deepest = at;
    }
    for (final child in at.children) {
      walk(child, depth + 1);
    }
  }

  walk(root, 0);
  return deepest;
}
