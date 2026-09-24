/// Static casters live in an atlas of their own, and a moving caster redraws
/// only itself over a copy of them — `S1`.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A floor that receives, a row of walls, and one block that moves, with the
/// walls marked static when [static].
({Scene scene, MeshNode mover, CameraNode camera}) _scene(
  CpuDevice device, {
  required bool static,
}) {
  final floor = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(20, 0.1, 20)).build(),
  );
  final block = DeviceMesh.upload(device, CuboidShape().build());
  final scene = Scene()
    ..add(
      MeshNode(
          floor,
          Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
        )
        ..setPosition(0.0, -1.0, 0.0)
        ..shadowCasting = ShadowCastingMode.off,
    )
    ..add(
      LightNode(intensity: 6.0, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );
  for (var i = 0; i < 5; i++) {
    scene.add(
      MeshNode(block, Material(name: 'wall $i'))
        ..setPosition(-4.0 + i * 2.0, 0.0, -2.0)
        ..shadowIsStatic = static,
    );
  }
  final mover = scene.add(
    MeshNode(block, Material(name: 'mover'), name: 'mover')
      ..setPosition(-1.0, 0.0, 1.0),
  );
  final camera = scene.add(CameraNode())
    ..setPosition(0.0, 4.0, 6.0)
    ..lookAt(Vector3(0.0, 0.0, -1.0));
  return (scene: scene, mover: mover, camera: camera);
}

const RenderSettings _settings = RenderSettings(
  shadows: ShadowSettings(enabled: true, cascades: 3),
);

void main() {
  int cascadeDraws(FrameResult frame) => frame.passes
      .where((p) => p.name == 'directional shadows')
      .fold(0, (a, p) => a + p.drawCalls);

  CpuDevice device() => CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  FrameResult render(Renderer renderer, Scene scene, CameraNode camera) =>
      renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: _settings,
      );

  test('a moving caster over static walls draws itself and a copy', () {
    final gpu = device();
    final built = _scene(gpu, static: true);
    final renderer = Renderer.create(device: gpu);
    render(renderer, built.scene, built.camera);
    expect(cascadeDraws(render(renderer, built.scene, built.camera)), 0);

    built.mover.translate(0.5, 0.0, 0.0);
    final moved = cascadeDraws(render(renderer, built.scene, built.camera));
    // At most one copy and the mover per cascade: the five walls are not
    // drawn again. Mutation: drop `only: false` from the frame's draw. Every
    // wall is drawn into every tile it is in, on top of its own copy.
    expect(moved, greaterThan(0));
    expect(moved, lessThanOrEqualTo(3 * 2));
  });

  test('the split draws what drawing everything draws', () async {
    final gpu = device();
    Future<List<int>> pixels(FrameResult result) async {
      final bytes = await gpu.readPixels(result.frame);
      return <int>[
        for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
      ];
    }

    final split = _scene(gpu, static: true);
    final whole = _scene(gpu, static: false);
    final splitRenderer = Renderer.create(device: gpu);
    final wholeRenderer = Renderer.create(device: gpu);
    for (var step = 0; step < 4; step++) {
      final a = await pixels(render(splitRenderer, split.scene, split.camera));
      final b = await pixels(render(wholeRenderer, whole.scene, whole.camera));
      // Mutation: copy colour without `gl_FragDepth`. The mover's shadow is
      // drawn over the walls' wherever it is farther from the light.
      expect(a, b, reason: 'frame $step');
      split.mover.translate(0.0, 0.0, -0.8);
      whole.mover.translate(0.0, 0.0, -0.8);
    }
  });
}
