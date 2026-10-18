/// The scene the smallest application draws, built with no window, and the
/// application itself opening its view.
///
///     flutter test test/cube_scene_test.dart
///
/// Small, because the application is: a test that the one thing it builds is
/// there, on the software device a project without a GPU in CI has.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_app_example/main.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the scene is one cube and the light that shows it', () {
    final scene = buildScene(
      CpuDevice(
        width: 16,
        height: 9,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      ),
    );

    expect(scene.meshes.map((MeshNode it) => it.name), <String?>['cube']);
    expect(scene.lights, hasLength(1));
  });

  testWidgets('the application opens a view and draws the cube in it', (
    tester,
  ) async {
    // A small window: the software rasteriser draws every pixel of it.
    tester.view
      ..physicalSize = const Size(160, 120)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CubeApp());
    // The device opens asynchronously: the software one under a test.
    for (
      var i = 0;
      i < 20 && find.byType(SceneSurface).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(find.byType(DidNotStart), findsNothing);
    final surface = tester.widget<SceneSurface>(find.byType(SceneSurface));
    expect(surface.scene.meshes.map((MeshNode it) => it.name), <String?>[
      'cube',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
