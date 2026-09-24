/// A camera walking through a static scene keeps the cascades it did not
/// change, and the frames it draws are the frames an uncached renderer draws
/// — `S1`.
///
/// Stands in for the `cascade-walk` golden: eight frames of a walk, drawn by
/// one renderer that keeps its tiles and by eight that start from nothing,
/// compared to the byte.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A floor with a row of blocks along the walk, lit at an angle.
({Scene scene, MeshNode far, CameraNode camera}) _scene(CpuDevice device) {
  final floor = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(40, 0.1, 40)).build(),
  );
  final block = DeviceMesh.upload(device, CuboidShape().build());
  final scene = Scene()
    ..add(
      MeshNode(
          floor,
          Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
        )
        ..setPosition(0.0, -1.0, 0.0)
        // Receives but does not cast: a floor that cast would cover every
        // texel of every tile, and a tile it covers hides whether the reset
        // happened at all.
        ..shadowCasting = ShadowCastingMode.off,
    )
    ..add(
      LightNode(intensity: 6.0, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );
  for (var i = 0; i < 6; i++) {
    scene.add(
      MeshNode(block, Material(name: 'block $i'))
        ..setPosition(-5.0 + i * 2.0, 0.0, -2.0),
    );
  }
  // The corner of the casters' bounds, which the last cascade is fitted to,
  // and a block well inside them that the camera's cascades never reach.
  scene.add(
    MeshNode(block, Material(name: 'corner'))..setPosition(15.0, 0.0, -15.0),
  );
  final far = scene.add(
    MeshNode(block, Material(name: 'far'), name: 'far')
      ..setPosition(10.0, 0.0, -12.0),
  );
  final camera = scene.add(CameraNode());
  return (scene: scene, far: far, camera: camera);
}

void _place(CameraNode camera, int step) {
  final x = -4.0 + step * 0.6;
  camera
    ..setPosition(x, 2.0, 4.0)
    ..lookAt(Vector3(x, 0.0, -2.0));
}

const RenderSettings _settings = RenderSettings(
  shadows: ShadowSettings(enabled: true, cascades: 3),
);

void main() {
  int cascadeDraws(FrameResult frame) => frame.passes
      .where((p) => p.name == 'directional shadows')
      .fold(0, (a, p) => a + p.drawCalls);

  test('a walking camera keeps the cascade that covers the scene', () {
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);
    final draws = <int>[];
    for (var step = 0; step < 8; step++) {
      _place(built.camera, step);
      draws.add(
        cascadeDraws(
          renderer.render(
            width: _size,
            height: _size,
            scene: built.scene,
            views: <RenderView>[RenderView(camera: built.camera)],
            settings: _settings,
          ),
        ),
      );
    }
    // The first frame draws every tile. After it the last cascade, fitted to
    // the casters rather than to the camera, is never drawn again: every
    // caster is in it, so a frame that redrew it would cost at least as many
    // draws as there are casters on top of the near tiles.
    // Mutation: key every cascade on the camera's own matrix. Each frame
    // draws as much as the first.
    for (final later in draws.skip(1)) {
      expect(later, lessThan(draws.first));
    }
  });

  test('a caster moving far off keeps the tiles it is not in', () {
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);
    _place(built.camera, 0);
    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: _settings,
    );
    final first = cascadeDraws(frame());
    expect(cascadeDraws(frame()), 0);
    // Across the level, in the last cascade only: one reset and the casters
    // of that one tile, not every tile again.
    built.far.translate(0.0, 0.0, 1.0);
    final moved = cascadeDraws(frame());
    expect(moved, greaterThan(0));
    // Mutation: put `SceneNode.changeEpoch` back in the key. Every tile.
    expect(moved, lessThan(first));
  });

  test('eight frames of a walk are the frames drawn from nothing', () async {
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    Future<List<int>> pixels(FrameResult result) async {
      final bytes = await device.readPixels(result.frame);
      return <int>[
        for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
      ];
    }

    final kept = Renderer.create(device: device);
    final walk = _scene(device);
    for (var step = 0; step < 8; step++) {
      _place(walk.camera, step);
      final cached = await pixels(
        kept.render(
          width: _size,
          height: _size,
          scene: walk.scene,
          views: <RenderView>[RenderView(camera: walk.camera)],
          settings: _settings,
        ),
      );
      final fresh = _scene(device);
      _place(fresh.camera, step);
      final drawn = await pixels(
        Renderer.create(device: device).render(
          width: _size,
          height: _size,
          scene: fresh.scene,
          views: <RenderView>[RenderView(camera: fresh.camera)],
          settings: _settings,
        ),
      );
      expect(cached, drawn, reason: 'frame $step');
    }
  });

  test('a caster that moved leaves no shadow where it was', () async {
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    Future<List<int>> pixels(
      Renderer renderer,
      Scene scene,
      CameraNode camera,
    ) async {
      final result = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: _settings,
      );
      final bytes = await device.readPixels(result.frame);
      return <int>[
        for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
      ];
    }

    final kept = Renderer.create(device: device);
    final built = _scene(device);
    _place(built.camera, 3);
    final before = await pixels(kept, built.scene, built.camera);
    final block = built.scene.meshes[3];
    block.translate(0.0, 0.0, 3.0);
    final after = await pixels(kept, built.scene, built.camera);
    expect(after, isNot(before));

    final fresh = _scene(device);
    _place(fresh.camera, 3);
    fresh.scene.meshes[3].translate(0.0, 0.0, 3.0);
    // Mutation: skip the tile reset. The redrawn tile keeps the block where
    // it was under where it is, and its old shadow stays on the floor.
    expect(
      after,
      await pixels(Renderer.create(device: device), fresh.scene, fresh.camera),
    );
  });
}
