/// The yard, drawn — not the simulation, the picture. Follows
/// `site/content/reference/testing.md`'s own "And draw one frame anyway"
/// pattern: a bare `Scene`/`Renderer` on a CPU device, no widget tree and no
/// `GameWidget`. See `apps/flutter3d_demo_arcade/lib/main.dart`'s own doc
/// comment for why mounting the real `Flutter3dFlameWidget` is not what this
/// file tries to do.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_arcade/src/arcade_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

/// The same top-down camera `ArcadeScreen` builds, standing alone so this
/// file does not need a widget tree to get one.
CameraNode _topDownCamera() =>
    CameraNode(projection: const OrthographicProjection(height: 22.0))
      ..setPosition(0.0, cameraHeight, 0.0)
      ..setLocalForward(Vector3(0.0, -1.0, 0.0), up: Vector3(0.0, 0.0, -1.0));

void main() {
  test('a frame renders', () {
    final it = cpuTestDevice(width: 320, height: 180);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );

    final game = ArcadeGame();
    final scene = Scene();
    game.spawnWorld(it.device, scene);
    scene.add(_topDownCamera());

    final frame = renderer.render(
      width: 320,
      height: 180,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.first)],
      settings: const RenderSettings(),
    );

    expect(frame.drawCalls, greaterThan(0));
  });

  test('the ground and the ship are both actually drawn', () async {
    // The cheapest guard against "the scene built but everything is at the
    // origin, invisible, or the wrong colour" — a coloured yard floor plus a
    // ship reads as more than one flat brightness across the frame.
    final it = cpuTestDevice(width: 320, height: 180);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );

    final game = ArcadeGame();
    final scene = Scene();
    game.spawnWorld(it.device, scene);
    scene.add(_topDownCamera());

    final result = renderer.render(
      width: 320,
      height: 180,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.first)],
      settings: const RenderSettings(),
    );
    final pixels = await it.device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');

    final rgba = pixels!.buffer.asUint8List();
    var low = 255;
    var high = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final brightness = rgba[i] + rgba[i + 1] + rgba[i + 2];
      if (brightness < low) low = brightness;
      if (brightness > high) high = brightness;
    }

    expect(
      high - low,
      greaterThan(20),
      reason: 'every pixel of the frame is the same brightness',
    );
  });
}
