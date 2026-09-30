/// A Flame sprite animation drawn in the scene on a card that faces the
/// camera, rendered for real on the CPU device.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Road extends FlameGame with HasFlutter3d {}

const int _size = 24;

/// Four pixels by two: the left half red, the right half blue.
Future<ui.Image> _twoFrames() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    )
    ..drawRect(
      const ui.Rect.fromLTWH(2, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFF0000FF),
    );
  return recorder.endRecording().toImage(4, 2);
}

({int r, int g, int b}) _middle(ByteData? pixels) {
  final rgba = pixels!.buffer.asUint8List(
    pixels.offsetInBytes,
    pixels.lengthInBytes,
  );
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return (r: rgba[at], g: rgba[at + 1], b: rgba[at + 2]);
}

void main() {
  testWidgets('each frame of a Flame animation is drawn in turn on a card '
      'that faces the camera', (tester) async {
    // Mutation: draw the whole image on the card, or leave it facing +Z.
    final cpu = cpuTestDevice(width: _size, height: _size);
    final renderer = Renderer.create(
      device: cpu.device,
      fallbackAlbedo: cpu.albedo,
      fallbackNormal: cpu.normal,
    );
    final game = _Road()..open3d(cpu.device);
    // Looking at the card from its side: it has to turn to be seen at all.
    game.camera3d
      ..setPosition(3.0, 0.5, 0.0)
      ..lookAt(Vector3(0.0, 0.5, 0.0));
    await tester.runAsync(() async {
      await initializeGame(() => game);
      final image = await _twoFrames();
      final animation = SpriteAnimation.fromFrameData(
        image,
        SpriteAnimationData.sequenced(
          amount: 2,
          stepTime: 0.5,
          textureSize: Vector2(2.0, 2.0),
        ),
      );
      await game.add(
        SpriteBillboardComponent(
          animation: animation,
          device: cpu.device,
          scene: game.scene,
          plane: BridgePlane.ground(),
        ),
      );
      await game.ready();
    });

    Future<({int r, int g, int b})> look() async {
      final result = renderer.render(
        width: _size,
        height: _size,
        scene: game.scene,
        views: <RenderView>[
          RenderView(
            camera: game.camera3d,
            clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
          ),
        ],
        settings: const RenderSettings(
          tonemap: false,
          bloom: BloomSettings(enabled: false),
        ),
      );
      return _middle(await cpu.device.readPixels(result.frame));
    }

    game.update(0.0);
    final first = (await tester.runAsync(look))!;
    expect(first.r, greaterThan(150), reason: 'the first frame is red');
    expect(first.b, lessThan(60));

    game.update(0.5);
    final second = (await tester.runAsync(look))!;
    expect(second.b, greaterThan(150), reason: 'the second is blue');
    expect(second.r, lessThan(60));
  });

  testWidgets('billboards handed one atlas share its material and its cards, '
      'and a one-shot goes when it has played', (tester) async {
    // A bank of reeds uploaded its sheet once for each reed.
    //
    // Mutation: give every billboard its own atlas.
    final cpu = cpuTestDevice(width: _size, height: _size);
    final game = _Road()..open3d(cpu.device);
    final atlas = BillboardAtlas(cpu.device);
    late final SpriteBillboardComponent reed;
    late final SpriteBillboardComponent other;
    late final SpriteBillboardComponent flash;
    await tester.runAsync(() async {
      await initializeGame(() => game);
      final image = await _twoFrames();
      final sprite = Sprite(image, srcSize: Vector2(2.0, 2.0));
      reed = SpriteBillboardComponent(
        sprite: sprite,
        atlas: atlas,
        device: cpu.device,
        scene: game.scene,
        plane: BridgePlane.ground(),
      );
      other = SpriteBillboardComponent(
        sprite: sprite,
        atlas: atlas,
        device: cpu.device,
        scene: game.scene,
        plane: BridgePlane.ground(),
        position: Vector2(3.0, 0.0),
      );
      flash = SpriteBillboardComponent(
        animation: SpriteAnimation.fromFrameData(
          image,
          SpriteAnimationData.sequenced(
            amount: 2,
            stepTime: 0.1,
            textureSize: Vector2(2.0, 2.0),
            loop: false,
          ),
        ),
        atlas: atlas,
        device: cpu.device,
        scene: game.scene,
        plane: BridgePlane.ground(),
        removeOnFinish: true,
      );
      await game.addAll(<Component>[reed, other, flash]);
      await game.ready();
    });

    MeshNode cardOf(SpriteBillboardComponent billboard) =>
        billboard.visual.childrenView.whereType<MeshNode>().single;
    expect(cardOf(reed).material, same(cardOf(other).material));
    expect(cardOf(reed).mesh, same(cardOf(other).mesh));
    expect(cardOf(flash).material, same(cardOf(reed).material));

    for (var i = 0; i < 4; i++) {
      game.update(0.1);
    }
    await tester.runAsync(game.ready);
    expect(flash.isMounted, isFalse, reason: 'played, and gone');
    expect(reed.isMounted, isTrue);
  });
}
