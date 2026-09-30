/// The first level and the party in it, drawn — not the simulation, the
/// picture.
///
///     flutter test test/frame_test.dart
///
/// Through what `main` calls: `openLevel` reads the document with the level
/// loader, `stage` spawns it, the visuals are the game's. Counted pixels
/// rather than a golden: what is asserted is that the floor was drawn and
/// that each hero's colour is somewhere in the frame.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_crawler/src/crawl_visuals.dart';
import 'package:flutter3d_demo_crawler/src/level_open.dart';
import 'package:flutter3d_demo_crawler/src/staging.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the gatehouse is drawn, with the party standing in it', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final (:kinds, :loaded, :fixtures) = await openLevel(
      levelAsset(firstLevel),
      device: it.device,
    );
    final staged = stage(
      loaded.level,
      loaded.collision,
      party: <HeroClass>[HeroClass.warrior, HeroClass.elf],
      registry: kinds,
      onFixture: fixtures.add,
    );
    final visuals = CrawlVisuals(device: it.device, heroes: staged.sim.heroes)
      ..addTo(loaded.scene);
    final camera = loaded.scene.add(
      CameraNode(
        name: 'camera',
        projection: PerspectiveProjection(
          fovYRadians: staged.sim.framing.tuning.fieldOfView,
          far: 200.0,
        ),
      ),
    );
    final follow = CrawlCamera();

    Uint8List? pixels;
    for (var i = 0; i < 3; i++) {
      staged.sim.step(1.0 / 60.0);
      visuals.sync(staged.sim, staged.horde);
      fixtures.sync(i / 60.0);
      follow.follow(staged.sim.framing, 1.0 / 60.0);
      camera
        ..setPositionFrom(follow.eye)
        ..lookAt(follow.target);
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: loaded.scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: crawlRenderSettings,
      );
      pixels = (await it.device.readPixels(result.frame))!.buffer.asUint8List();
    }

    var lit = 0;
    var red = 0;
    var green = 0;
    for (var p = 0; p < pixels!.length; p += 4) {
      final r = pixels[p], g = pixels[p + 1], b = pixels[p + 2];
      if (r + g + b > 30) lit++;
      if (r > 120 && r > g * 2 && r > b * 2) red++;
      if (g > 120 && g > r * 1.5 && g > b * 1.5) green++;
    }
    expect(lit, greaterThan(_width * _height ~/ 2), reason: 'the floor');
    expect(red, greaterThan(0), reason: 'the warrior');
    expect(green, greaterThan(0), reason: 'the elf');
  });
}
