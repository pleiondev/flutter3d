/// The scene the smallest application draws, built with no window.
///
///     flutter test test/cube_scene_test.dart
///
/// Small, because the application is: a test that the one thing it builds is
/// there, on the software device a project without a GPU in CI has.
library;

import 'package:flutter3d/flutter3d.dart';
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
}
