/// Taps on what a bridged component draws under a perspective camera, and
/// its hitboxes drawn in the scene where it is.
library;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart' show Anchor, Component;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

final class _World extends FlameGame with HasFlutter3d {
  @override
  CameraNode createCamera3d() =>
      CameraNode(
          projection: const PerspectiveProjection(fovYRadians: 0.9, far: 200.0),
        )
        ..setPosition(0.0, 6.0, 6.0)
        ..lookAt(Vector3(0.0, 0.0, -10.0));
}

final class _Crate extends Object3dComponent with Tap3dCallbacks {
  _Crate(GraphicsDevice device, Scene scene, Vector2 at, {required this.name})
    : super(
        node: MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(2.0)).build(),
          ),
          Material(),
        ),
        scene: scene,
        plane: BridgePlane.ground(),
        direction: SyncDirection.flameToScene,
        position: at,
      );

  final String name;
  int taps = 0;

  @override
  void onTap3d(Vector2 screen) => taps++;
}

Future<({_World game, CpuDevice device})> _open() async {
  final device = CpuDevice(
    width: 32,
    height: 24,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final game = await initializeGame(_World.new);
  game.open3d(device);
  return (game: game, device: device);
}

void main() {
  test('a tap on a crate drawn in perspective finds it, where Flame would '
      'not', () async {
    // Mutation: hit-test by the crate's Flame rectangle instead.
    final (:game, :device) = await _open();
    final crate = _Crate(device, game.scene, Vector2(0.0, -10.0), name: 'a');
    final taps = Taps3dComponent();
    await game.addAll(<Component>[crate, taps]);
    await game.ready();
    game.update(0.0);

    final screen = game.projector.toScreen(crate.scenePosition)!;
    expect(taps.nearestAt(screen), same(crate));
    expect(
      crate.containsPoint(screen),
      isFalse,
      reason: 'Flame\'s own test misses the crate the player can see',
    );
    expect(taps.nearestAt(Vector2(1.0, 1.0)), isNull);
  });

  test('of two crates under one finger, the nearer hears it', () async {
    final (:game, :device) = await _open();
    final far = _Crate(device, game.scene, Vector2(0.0, -12.5), name: 'far');
    final near = _Crate(device, game.scene, Vector2(0.0, -10.0), name: 'near');
    final taps = Taps3dComponent();
    await game.addAll(<Component>[far, near, taps]);
    await game.ready();
    game.update(0.0);

    // A point both crates' screen boxes cover: the middle of their overlap.
    final a = game.projector.boundsOf(near.node.subtreeBounds!)!;
    final b = game.projector.boundsOf(far.node.subtreeBounds!)!;
    final left = a.left > b.left ? a.left : b.left;
    final right = a.right < b.right ? a.right : b.right;
    final top = a.top > b.top ? a.top : b.top;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    expect(left < right && top < bottom, isTrue, reason: 'no overlap to tap');
    final screen = Vector2((left + right) / 2.0, (top + bottom) / 2.0);
    expect(far.hitAt3d(screen, game.projector), isTrue);
    expect(taps.nearestAt(screen), same(near));
  });

  test('a hitbox is drawn in the scene, round its component, at its '
      'height', () async {
    final (:game, :device) = await _open();
    final crate = _Crate(device, game.scene, Vector2(3.0, -10.0), name: 'a')
      ..elevation = 1.5
      ..size = Vector2(2.0, 2.0)
      ..anchor = Anchor.center
      ..add(RectangleHitbox());
    await game.add(crate);
    await game.ready();

    final lines = DebugDraw();
    addHitboxes3d(lines, game);
    expect(lines.lineCount, 4);
    // Every end of every edge: on the crate's plane at its height, within a
    // metre of its middle across.
    final data = lines.vertexBytes.buffer.asFloat32List(
      lines.vertexBytes.offsetInBytes,
      lines.vertexCount * DebugDraw.floatsPerVertex,
    );
    for (var v = 0; v < lines.vertexCount; v++) {
      final at = v * DebugDraw.floatsPerVertex;
      expect(data[at + 1], closeTo(1.5, 1e-6));
      expect((data[at] - 3.0).abs(), closeTo(1.0, 1e-6));
      expect((data[at + 2] + 10.0).abs(), closeTo(1.0, 1e-6));
    }
  });
}
