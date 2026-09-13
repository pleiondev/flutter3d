/// mcp-03n's own acceptance, made concrete: a `Renderer` draws a frame in
/// this package alone, under plain `dart test`, with no Flutter SDK
/// anywhere in the resolution.
///
///     dart test test/renders_without_flutter_test.dart
///
/// `FakeBackend`, from `flutter3d_hardware`'s own `testing.dart`, rather than
/// a real backend: every real one either needs the Flutter SDK
/// (`flutter3d_impeller`, `flutter3d_webgl`, `flutter3d_webgpu`) or, for
/// `flutter3d_cpu`, still carries one test file that does (`cross_backend_
/// test.dart`, a named exception until mcp-04n) — either way, this package
/// dev-depending on it would put the Flutter SDK back in its own
/// resolution, which is exactly the property this test exists to prove
/// absent.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a Renderer draws a frame with no Flutter SDK behind it', () {
    final device = FakeBackend();
    final mesh = DeviceMesh.upload(device, CuboidShape().build());
    final scene = Scene()
      ..add(MeshNode(mesh, Material())..setPosition(0.0, 0.0, -5.0))
      ..add(CameraNode());
    final renderer = Renderer.create(device: device);

    final result = renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
    );

    expect(result.frame, isNotNull);
    expect(result.drawCalls, greaterThan(0));
  });
}
