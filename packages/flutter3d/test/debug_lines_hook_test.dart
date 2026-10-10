/// A renderer draws an application's own debug lines beside its own.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lines added through debugLines are drawn, and cost nothing when '
      'there is no hook', () {
    final device = FakeBackend();
    TextureHandle texel() => device.createTexture(
      const RenderTargetDescriptor(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(),
      fallbackNormal: texel(),
    );
    final camera = CameraNode()
      ..setPosition(0.0, 0.0, 5.0)
      ..lookAt(Vector3.zero());
    final scene = Scene()..add(camera);
    void frame() => renderer.render(
      width: 32,
      height: 24,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(),
    );

    frame();
    expect(renderer.debugDraw.lineCount, 0);

    // A hitbox's edge, say, which the scene knows nothing about.
    renderer.debugLines = (DebugDraw lines) => lines.addLine(
      Vector3(-1.0, 0.0, 0.0),
      Vector3(1.0, 0.0, 0.0),
      const LinearColor(0.0, 1.0, 0.0),
    );
    frame();
    expect(renderer.debugDraw.lineCount, 1);

    renderer.debugLines = null;
    frame();
    expect(renderer.debugDraw.lineCount, 1, reason: 'not rebuilt: skipped');
  });
}
