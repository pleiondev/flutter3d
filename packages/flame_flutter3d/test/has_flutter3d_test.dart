/// A Flame game that owns its 3D world: opened on a device, built once, and
/// hosted by `Flutter3dFlameWidget` with nothing but the game.
library;

import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

final class _World extends FlameGame with HasFlutter3d {
  int built = 0;
  Renderer? handed;
  final SceneNode floor = SceneNode(name: 'floor');

  @override
  void onOpen3d() {
    built++;
    scene.add(floor);
  }

  @override
  void onRenderer3d(Renderer renderer) {
    // What the world built is there to be given the renderer.
    expect(built, 1);
    handed = renderer;
  }
}

CpuDevice _device() => CpuDevice(
  width: 32,
  height: 24,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('opened before it is loaded, it builds once it has loaded', () async {
    final game = _World()..open3d(_device());
    expect(game.built, 0, reason: 'nothing to build a game on yet');
    await initializeGame(() => game);
    expect(game.built, 1);
    expect(game.scene.cameras, contains(game.camera3d));
    expect(game.floor.parent, isNotNull);
  });

  test('opened after it is loaded, it builds at once, and only once', () async {
    final game = await initializeGame(_World.new);
    expect(game.has3d, isFalse);
    expect(() => game.scene, throwsStateError);

    game.open3d(_device());
    expect(game.built, 1);
    expect(() => game.open3d(_device()), throwsStateError);
    expect(game.built, 1);
  });

  test('its background lets the 3D layer through', () {
    expect(_World().backgroundColor().a, 0.0);
  });

  testWidgets('the widget hosts it with nothing but the game', (tester) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final game = _World();

    await tester.pumpWidget(
      MaterialApp(
        home: Flutter3dFlameWidget(
          game: game,
          existing: (device: device, renderer: renderer),
        ),
      ),
    );
    await tester.pump();

    expect(game.device, same(device));
    expect(game.handed, same(renderer));
    expect(game.built, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test(
    'a renderer handed over before it is loaded waits for the world',
    () async {
      // The widget's order: the device opens, the renderer is made, and only
      // then does Flame load the game.
      final device = _device();
      final renderer = Renderer.create(device: device);
      final game = _World()
        ..open3d(device)
        ..attachRenderer(renderer);
      expect(game.handed, isNull);
      await initializeGame(() => game);
      expect(game.handed, same(renderer));
    },
  );
}
