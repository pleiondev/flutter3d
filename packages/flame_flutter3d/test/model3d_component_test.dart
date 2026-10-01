/// [Model3dComponent] draws its scene into Flame's canvas, through the
/// readback path every backend but Impeller takes, and shares one device
/// per game.
library;

import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 32,
  height: 32,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A sphere instead of a model file, which a test has no bundle to read.
class _Sphere extends Model3dComponent {
  _Sphere({super.device}) : super(size: Vector2.all(32), pixelRatio: 1.0);

  @override
  Future<void> buildScene(GraphicsDevice device) async {
    final asset = ModelAsset.fromMesh(
      device,
      const SphereShape(radius: 1.0).build(),
      material: f3d.Material(baseColor: Vector4(0.9, 0.4, 0.3, 1.0)),
    );
    asset.instantiate(scene);
    frameModel(asset.localBounds);
  }
}

/// A game loaded and mounted the way a `GameWidget` would, so its children
/// mount, render and are removed.
Future<FlameGame> _game() => initializeGame(FlameGame.new);

/// One Flame frame: update, then paint into a throwaway picture.
void _frame(FlameGame game) {
  game.update(1 / 60);
  final recorder = ui.PictureRecorder();
  game.render(ui.Canvas(recorder));
  recorder.endRecording().dispose();
}

Future<int> _alphaAt(ui.Image image, int x, int y) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return bytes.getUint8((y * image.width + x) * 4 + 3);
}

void main() {
  testWidgets('the frame is read back and drawn: the model, and clear round '
      'it', (tester) async {
    await tester.runAsync(() async {
      final game = await _game();
      final sphere = _Sphere(device: _device());
      await game.world.add(sphere);
      await game.ready();

      _frame(game);
      // The readback and the decode are asynchronous; the next frame paints
      // what they produced.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _frame(game);

      final image = sphere.frameImage;
      expect(image, isNotNull);
      expect(await _alphaAt(image!, 16, 16), greaterThan(0));
      expect(
        await _alphaAt(image, 0, 0),
        0,
        reason:
            'the clear colour is transparent, so the 2D game shows round '
            'the model',
      );
    });
  });

  testWidgets('a removed component lets its picture go', (tester) async {
    await tester.runAsync(() async {
      final game = await _game();
      final sphere = _Sphere(device: _device());
      await game.world.add(sphere);
      await game.ready();
      _frame(game);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sphere.frameImage, isNotNull);

      sphere.removeFromParent();
      await game.ready();
      expect(sphere.frameImage, isNull);
    });
  });

  testWidgets('the components of one game share a device, and the last one '
      'out closes it', (tester) async {
    await tester.runAsync(() async {
      // Mutation: open a device per component, or forget the count and
      // keep the first device for ever.
      var opened = 0;
      final saved = Model3dComponent.openSharedDevice;
      addTearDown(() => Model3dComponent.openSharedDevice = saved);
      Model3dComponent.openSharedDevice =
          ({required int width, required int height}) async {
            opened++;
            return _device();
          };

      final game = await _game();
      final first = _Sphere();
      final second = _Sphere();
      await game.world.addAll(<Component>[first, second]);
      await game.ready();
      expect(opened, 1);
      expect(first.device, same(second.device));

      // One still holds it: a newcomer joins the same device.
      first.removeFromParent();
      await game.ready();
      final third = _Sphere();
      await game.world.add(third);
      await game.ready();
      expect(opened, 1);

      // Nobody holds it: it was closed, and the next one opens another.
      second.removeFromParent();
      third.removeFromParent();
      await game.ready();
      await game.world.add(_Sphere());
      await game.ready();
      expect(opened, 2);
    });
  });
}
