/// A monster is drawn the size it is fought at.
///
///     flutter test test/monster_size_test.dart
///
/// **The frog was two metres seventy-four in a four-metre corridor**, over a
/// hitbox one metre seven tall. `tool/prepare_monsters.py` exists to normalise
/// exactly this and believed it had: it scaled each download by
/// `target / measured`, and its measurement was the mesh's own bounding box
/// times the scale on the armature node.
///
/// That is not where a skinned vertex is drawn. It is drawn at
/// `jointWorld * inverseBind * v`, blended across the joints it names, and the
/// bounding box only agrees when those matrices are one shared transform —
/// which they stop being the moment the script scales the hierarchy without
/// touching the inverse binds it was authored against. Three monsters asked to
/// be 1.7, 1.8 and 2.4 came out 2.74, 2.03 and 2.28.
///
/// So this measures the picture. Rendered on the software backend, posed on the
/// clip the game plays first, counted in pixels and converted back to metres —
/// no arithmetic shared with the script that writes the files, because a check
/// that reuses the measurement it is checking cannot fail.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_dungeon/src/monster_looks.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 400;
const int _height = 400;

/// Far enough that the near side of a monster is not appreciably larger than
/// its far side: at twenty metres a body one metre deep is out by five per
/// cent, which is inside what this asks of the number.
const double _distance = 20.0;
const double _fov = 0.4;

/// How tall and wide [path] draws, in metres, posed on its resting clip.
Future<({double tall, double wide})> _drawn(String path) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final document = await GltfLoader().load(File(path).readAsBytesSync());
  final asset = await ModelAsset.fromDocument(document, device: device);
  final scene = Scene();
  final instance = asset.instantiate(scene, name: 'monster');

  // The clip the game plays when a monster is doing nothing, chosen the same
  // way `DungeonMonsters` chooses it. A model measured in its bind pose is a
  // model measured in a shape nobody ever sees.
  final player = instance.player!;
  for (final wanted in DungeonMonsters.clipsForState[MonsterState.idle]!) {
    if (player.playNamed(wanted)) break;
  }

  scene.add(
    LightNode(color: Vector3(1.0, 1.0, 1.0), intensity: 4.0)
      ..lookAt(Vector3(-0.3, -0.3, -1.0)),
  );
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: _fov,
      near: 0.1,
      far: 60.0,
    ),
  )..setPosition(0.0, 1.5, _distance);
  camera.lookAt(Vector3(0.0, 1.5, 0.0));
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

  var top = _height, bottom = -1, left = _width, right = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      // Anything not the black it was cleared to. The models are unlit on
      // their far side, so the threshold is low rather than generous.
      if (pixels[i] + pixels[i + 1] + pixels[i + 2] < 12) continue;
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      left = math.min(left, x);
      right = math.max(right, x);
    }
  }
  expect(bottom, greaterThan(0), reason: '$path drew nothing at all');

  final perPixel = 2 * _distance * math.tan(_fov / 2) / _height;
  return (tall: (bottom - top) * perPixel, wide: (right - left) * perPixel);
}

void main() {
  for (final kind in DungeonMonsters.modelsForKind.keys) {
    test('the $kind is drawn the height it is fought at', () async {
      final def = Monsters.byName[kind]!;
      final drawn = await _drawn(DungeonMonsters.modelsForKind[kind]!);

      // A tenth of the body, not a fixed margin: what the script normalises
      // is the bind pose, and a resting clip is free to crouch or stretch a
      // little — the yeti's idle sits 0.11 m below its bind height. What this
      // refuses is the frog, which stood 1.6 times its own hitbox.
      expect(
        drawn.tall,
        closeTo(def.height, def.height * 0.1),
        reason:
            'the $kind draws ${drawn.tall.toStringAsFixed(2)} m tall '
            'over a hitbox ${def.height} m tall — a monster you shoot over '
            'the head of. Re-run tool/prepare_monsters.py.',
      );
    });
  }

  test('and none of them is wider than the room it is fought in', () async {
    // The frog's arms are its silhouette and they are meant to be wide. What
    // this refuses is a monster that cannot be seen whole in a corridor: the
    // crypt's are four metres, and something three and a half across fills one
    // from wall to wall.
    for (final kind in DungeonMonsters.modelsForKind.keys) {
      final drawn = await _drawn(DungeonMonsters.modelsForKind[kind]!);
      expect(
        drawn.wide,
        lessThan(3.0),
        reason: 'the $kind is ${drawn.wide.toStringAsFixed(2)} m across',
      );
    }
  });
}
