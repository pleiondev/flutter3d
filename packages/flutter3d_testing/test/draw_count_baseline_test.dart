/// `FrameResult.drawCalls`, pinned to an exact number for a scene whose own
/// composition is known — `qa-14`'s own row: a regression that adds or drops
/// a draw the picture alone would not obviously show (an extra empty pass,
/// a mesh drawn twice, a composite skipped) is exactly what a pixel
/// comparison is the wrong tool for and a count is the right one.
///
///     flutter test test/draw_count_baseline_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// [count] cuboids in a row, shadows and bloom off so nothing but the
/// meshes themselves and the frame's own composite contribute a draw.
Future<RenderedFrame> _scene(int count) => renderFrame(
  width: 64,
  height: 64,
  settings: const RenderSettings(
    shadows: ShadowSettings(enabled: false),
    bloom: BloomSettings(enabled: false),
  ),
  build: (FrameRequest request) {
    final device = request.device;
    final scene = Scene();
    for (var i = 0; i < count; i++) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1, 1, 1)).build(),
          ),
          Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
          name: 'box$i',
        )..setPosition(i.toDouble(), 0.0, 0.0),
      );
    }
    final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
    return (scene: scene, camera: camera);
  },
);

void main() {
  group('drawCalls is exactly one composite plus one draw a mesh', () {
    // Measured, not guessed: printed for 0..3 meshes before writing this
    // assertion, with and without the sky on, to find which "+1" was real.
    // Turning the sky off changed nothing, which is what said the constant
    // term is the frame's own tone-mapping composite — a full-screen pass
    // every frame pays whether or not anything is in the scene — and not
    // a background quad.
    for (final count in <int>[0, 1, 2, 3]) {
      test('$count mesh(es): drawCalls == ${count + 1}', () async {
        final frame = await _scene(count);
        expect(frame.drawCalls, count + 1);
      });
    }
  });

  test('two nodes sharing one uploaded mesh still draw twice', () async {
    // The baseline's own point: drawCalls counts draws, not distinct meshes
    // — a regression that started batching or, worse, silently drawing one
    // of two instanced nodes would move this number and nothing about the
    // picture would necessarily say so.
    final frame = await renderFrame(
      width: 64,
      height: 64,
      settings: const RenderSettings(
        shadows: ShadowSettings(enabled: false),
        bloom: BloomSettings(enabled: false),
      ),
      build: (FrameRequest request) {
        final device = request.device;
        final scene = Scene();
        final mesh = DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(1, 1, 1)).build(),
        );
        final material = Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0));
        scene.add(
          MeshNode(mesh, material, name: 'a')..setPosition(-1.0, 0.0, 0.0),
        );
        scene.add(
          MeshNode(mesh, material, name: 'b')..setPosition(1.0, 0.0, 0.0),
        );
        final camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
        return (scene: scene, camera: camera);
      },
    );

    expect(frame.drawCalls, 3);
  });
}
