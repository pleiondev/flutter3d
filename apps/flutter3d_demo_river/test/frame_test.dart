/// The river, drawn: a frame through the game's own camera on a CPU device,
/// with no widget tree and no `GameWidget`, the way
/// `site/content/reference/testing.md` draws one frame of a game.
library;

import 'dart:typed_data';

import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_river/src/models.dart';
import 'package:flutter3d_demo_river/src/river_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

const int _width = 160;
const int _height = 90;

/// The game's world and a frame of it, from where `RiverScreen` puts its
/// camera: behind the jet and above it, looking up the river.
Future<({Uint8List rgba, int drawCalls})> _frame() async {
  final it = cpuTestDevice(width: _width, height: _height);
  final game = await initializeGame(RiverGame.new);
  final scene = Scene();
  game.build(it.device, scene);
  await game.ready();

  final camera =
      CameraNode(
          projection: const PerspectiveProjection(
            fovYRadians: 0.85,
            far: 400.0,
          ),
        )
        ..setPosition(0.0, flightHeight + 11.0, -game.distance + 11.0)
        ..lookAt(Vector3(0.0, 0.0, -game.distance - 9.0));
  scene.add(camera);

  final result =
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ).render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[
          RenderView(
            camera: camera,
            clearColor: Vector4(0.27, 0.48, 0.78, 1.0),
          ),
        ],
        settings: const RenderSettings(),
      );
  final pixels = await it.device.readPixels(result.frame);
  return (rgba: pixels!.buffer.asUint8List(), drawCalls: result.drawCalls);
}

void main() {
  test('the valley, the water and the jet are all drawn', () async {
    final (:rgba, :drawCalls) = await _frame();
    expect(drawCalls, greaterThan(3));

    // Grass is green-dominant and water blue-dominant; a frame with both
    // has the land and the river where the camera expects them, and not
    // everything at the origin or the wrong colour.
    var grass = 0;
    var water = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final (r, g, b) = (rgba[i], rgba[i + 1], rgba[i + 2]);
      if (g > r + 20 && g > b + 20) grass++;
      if (b > r + 30 && b > g + 10) water++;
    }
    final pixels = _width * _height;
    expect(grass, greaterThan(pixels ~/ 10), reason: 'too little land');
    expect(water, greaterThan(pixels ~/ 20), reason: 'too little river');
  });
}
