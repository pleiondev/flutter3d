/// The game itself, loaded with no widget, stepped and drawn — the Flame game
/// and the bridge between it and the 3D layer, not a likeness of them.
///
///     flutter test test/frame_test.dart
///
/// A party of two goes in through `CrawlerGame(party:)`, the level loads
/// through the game's own `enter`, the bridge's components place the heroes
/// and the horde, and a frame is drawn on the software device through the
/// game's scene and camera. Counted pixels rather than a golden: the floor is
/// drawn, each hero's colour is in it, and so is the grunt's.
library;

import 'dart:typed_data';

import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_crawler/src/crawler_game.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the party and the horde are drawn in the first level', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final game = CrawlerGame(party: const <String>['warrior', 'elf'])
      ..open3d(it.device)
      ..attachRenderer(renderer);
    await initializeGame(() => game);

    for (var i = 0; i < 200 && game.phase != CrawlPhase.playing; i++) {
      await Future<void>.delayed(Duration.zero);
      await game.ready();
    }
    expect(game.phase, CrawlPhase.playing, reason: 'the level never loaded');

    Uint8List? pixels;
    for (var i = 0; i < 4; i++) {
      game.update(1.0 / 60.0);
      await game.ready();
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: game.scene,
        views: <RenderView>[RenderView(camera: game.camera3d)],
        settings: game.renderSettings(),
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
    expect(
      game.staged!.horde.count,
      greaterThan(0),
      reason: 'the placed grunt, drawn by the bridge',
    );
  });
}
