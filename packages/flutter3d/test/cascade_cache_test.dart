/// `gfx-68n`: a cascade nobody changed is not redrawn.
///
///     flutter test test/cascade_cache_test.dart
///
/// **What it cost.** Every cascade was drawn from nothing every frame, which on
/// a scene larger than the nearest cascade covers is the whole caster set two
/// or three times over, for a picture identical to the one already sitting in
/// the texture. The atlas is `devicePrivate` and has always survived the frame;
/// nothing was reading it back.
///
/// **This is the row's acceptance rather than the row's design.** The row asked
/// for the static/dynamic split the point-light atlas has: a persistent static
/// tile per cascade, fitted with slack, and the two depths combined in the
/// shader. That does not carry over as directly as it reads. A point light's
/// six faces depend on the light alone, so a static face stays valid while the
/// camera walks around it; a cascade is fitted to the camera and re-snapped as
/// it moves, so a static cascade must either be refitted whenever the camera
/// leaves its slack — giving the two halves different matrices, which means a
/// second matrix set and a second lookup rather than a `min` of one — or fitted
/// to the scene instead, which is a different volume at a different resolution.
/// Either way it is a sampler and three matrices added to every lit stage
/// across five implementations, and the per-pixel filter run twice.
///
/// So what landed is the whole pass cached on everything that decides a texel,
/// which is what both halves of the acceptance actually ask for. What it gives
/// up against the split: one dynamic caster moving invalidates the frame's
/// cascades rather than only the dynamic half of them.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A floor with two blocks over it, lit at an angle, with three cascades.
({Scene scene, MeshNode mover, CameraNode camera}) _scene(
  CpuDevice device, {
  bool casting = true,
}) {
  final floor = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(12, 0.1, 12)).build(),
  );
  final block = DeviceMesh.upload(device, CuboidShape().build());

  final mode = casting ? ShadowCastingMode.on : ShadowCastingMode.off;
  final mover = MeshNode(block, Material(name: 'mover'), name: 'mover')
    ..setPosition(0.0, 0.7, 0.0)
    ..shadowCasting = mode;

  final scene = Scene()
    ..add(
      MeshNode(
        floor,
        Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
      )..setPosition(0.0, -1.0, 0.0),
    )
    ..add(mover)
    ..add(
      MeshNode(block, Material(name: 'still'), name: 'still')
        ..setPosition(3.0, 0.7, 1.0)
        ..shadowCasting = mode,
    )
    ..add(
      LightNode(intensity: 6.0, castsShadow: true)
        ..setPosition(4.0, 5.0, 0.01)
        ..lookAt(Vector3.zero()),
    );

  final camera = scene.add(CameraNode())
    ..setPosition(0.0, 5.0, 7.0)
    ..lookAt(Vector3.zero());

  return (scene: scene, mover: mover, camera: camera);
}

void main() {
  /// How many casters the directional pass drew.
  int cascadeDraws(FrameResult frame) => frame.passes
      .where((p) => p.name == 'directional shadows')
      .fold(0, (a, p) => a + p.drawCalls);

  test('a still camera over a static scene redraws no cascade', () async {
    // **The row's own acceptance.** The first frame fills the atlas; the next
    // three read it.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);

    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: const RenderSettings(
        shadows: ShadowSettings(enabled: true, cascades: 3),
      ),
    );

    expect(cascadeDraws(frame()), greaterThan(0));
    expect(cascadeDraws(frame()), 0);
    expect(cascadeDraws(frame()), 0);
  });

  test('and still shows the shadow it drew on the first frame', () async {
    // **The claim that makes the skip safe**, and the one a cache that quietly
    // dropped the atlas would fail: the second frame is the first frame, to the
    // byte. A pass that skipped its draws and also left the shader's own
    // parameters at nought would read a perfectly good atlas at a strength of
    // zero and come back unshadowed — which is what the closure in the pass is
    // there to prevent.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    Future<List<int>> frame(
      Renderer renderer,
      Scene scene,
      CameraNode camera,
    ) async {
      final result = renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[
          RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: const RenderSettings(
          shadows: ShadowSettings(enabled: true, cascades: 3),
        ),
      );
      final bytes = await device.readPixels(result.frame);
      return <int>[
        for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i),
      ];
    }

    final renderer = Renderer.create(device: device);
    final built = _scene(device);
    final first = await frame(renderer, built.scene, built.camera);
    final second = await frame(renderer, built.scene, built.camera);

    expect(second, first);

    // Against a frame with nothing casting rather than against a brightness
    // threshold. The first draft used a threshold, and the floor here is lit at
    // an angle so the shadow never got below it: the test then proved that two
    // identical unshadowed frames are identical, which is true and empty.
    final lit = Renderer.create(device: device);
    final plain = _scene(device, casting: false);
    final unshadowed = await frame(lit, plain.scene, plain.camera);

    var darker = 0;
    for (var i = 0; i < first.length; i += 4) {
      if (first[i] < unshadowed[i] - 2) darker++;
    }
    expect(
      darker,
      greaterThan(20),
      reason: 'nothing in the fixture is in shadow, so it measures nothing',
    );
  });

  test('a moved caster redraws the cascades it is in', () async {
    // The other half. `SceneNode.changeEpoch` is what carries it, so this also
    // catches a key that forgot to ask.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);

    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: const RenderSettings(
        shadows: ShadowSettings(enabled: true, cascades: 3),
      ),
    );

    frame();
    expect(cascadeDraws(frame()), 0);

    built.mover.translate(0.0, 0.0, 1.5);
    expect(cascadeDraws(frame()), greaterThan(0));
    expect(cascadeDraws(frame()), 0);
  });

  test('a camera that moved redraws them too', () async {
    // The cascades are fitted to the camera and re-snapped as it moves, which
    // is the whole reason a static cascade is not the same problem as a static
    // cube face. The matrices are in the key, so this follows.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);

    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: const RenderSettings(
        shadows: ShadowSettings(enabled: true, cascades: 3),
      ),
    );

    frame();
    expect(cascadeDraws(frame()), 0);

    built.camera
      ..setPosition(4.0, 6.0, 9.0)
      ..lookAt(Vector3.zero());
    expect(cascadeDraws(frame()), greaterThan(0));
  });

  test('a cut-out caster whose threshold changed redraws them', () async {
    // A material is not a node, so neither the change epoch nor the static
    // generation hears about it — which is why the key reads the casters'
    // materials directly. `gfx-60n` made that threshold decide pixels.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = _scene(device);
    built.mover.material.alphaMode = MaterialAlphaMode.mask;

    FrameResult frame() => renderer.render(
      width: _size,
      height: _size,
      scene: built.scene,
      views: <RenderView>[RenderView(camera: built.camera)],
      settings: const RenderSettings(
        shadows: ShadowSettings(enabled: true, cascades: 3),
      ),
    );

    frame();
    expect(cascadeDraws(frame()), 0);

    built.mover.material.alphaCutoff = 0.9;
    expect(cascadeDraws(frame()), greaterThan(0));
  });
}
