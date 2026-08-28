/// The same scene, drawn again, is the same picture.
///
///     flutter test test/steady_frame_test.dart
///
/// **Reported as "the editor flickers like hell"**, with the detail that
/// settled where to look: a large blue rectangle and a small green one
/// alternating. Those are `DebugColors.bounds` and `DebugColors.selection` —
/// the debug overlay — and an overlay that appears on one frame and not the
/// next is a renderer whose output depends on which frame it is.
///
/// Nothing in the repository asked this question before. Every golden renders
/// one frame; the parity suites render one frame each; the editor's own frame
/// test renders twice and rebuilds the scene in between, which is a different
/// question. A frame that differs from the one before it, with nothing changed,
/// is invisible to all of them.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
  MeshNode box,
})
_room() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene();
  final floor = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(40.0, 1.0, 40.0)).build(),
    ),
    Material(name: 'floor', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
    name: 'floor',
  )..setPosition(0.0, -1.0, 0.0);
  scene.add(floor);

  // Bright enough to bloom, because the report was about the brightest thing on
  // screen — a torch — and bloom is on by default.
  final box = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
    ),
    Material(
      name: 'lamp',
      baseColor: Vector4(1.0, 0.85, 0.5, 1.0),
      emissive: Vector3(2.0, 1.6, 0.8),
    ),
    name: 'lamp',
  )..setPosition(0.0, 1.0, -6.0);
  scene.add(box);

  scene.add(
    LightNode(color: Vector3(1.0, 1.0, 1.0), intensity: 4.0)
      ..lookAt(Vector3(-0.4, -1.0, -0.3)),
  );

  // A lamp that casts, which is what a crypt is lit by and what the editor
  // holds still while nothing moves.
  scene.add(
    LightNode(
      type: LightType.point,
      color: Vector3(1.0, 0.8, 0.5),
      intensity: 8.0,
      range: 24.0,
      castsShadow: true,
    )..setPosition(2.0, 3.0, -3.0),
  );

  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.05,
      near: 0.1,
      far: 200.0,
    ),
  )..setPosition(0.0, 1.5, 6.0);
  camera.lookAt(Vector3(0.0, 1.0, -6.0));
  scene.add(camera);

  return (
    device: device,
    renderer: renderer,
    scene: scene,
    camera: camera,
    box: box,
  );
}

Future<Uint8List> _draw(
  ({
    CpuDevice device,
    Renderer renderer,
    Scene scene,
    CameraNode camera,
    MeshNode box,
  })
  it,
  RenderSettings settings,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  final pixels = await it.device.readPixels(result.frame);
  return pixels!.buffer.asUint8List();
}

void main() {
  test('six frames of a scene nobody touched are one picture', () async {
    final it = _room();
    const settings = RenderSettings();

    final first = await _draw(it, settings);
    for (var frame = 2; frame <= 6; frame++) {
      final next = await _draw(it, settings);
      final difference = compareFrames(first, next, channel: 0);
      expect(
        difference.differing,
        0,
        reason: 'frame $frame differs from the first: $difference',
      );
    }
  });

  test('and so are six with something highlighted', () async {
    // What the editor asks for: an outline round the selection. The engine has
    // had this pass since before anything called it, and the editor is its
    // first caller.
    final it = _room();
    final settings = RenderSettings(highlighted: <SceneNode>[it.box]);

    final first = await _draw(it, settings);
    for (var frame = 2; frame <= 6; frame++) {
      final next = await _draw(it, settings);
      final difference = compareFrames(first, next, channel: 0);
      expect(
        difference.differing,
        0,
        reason: 'frame $frame differs from the first: $difference',
      );
    }
  });

  test('and so are six with the debug overlay on', () async {
    final it = _room();
    const settings = RenderSettings(
      debug: DebugDrawOptions(bounds: true, lightGizmos: true, axes: true),
    );

    final first = await _draw(it, settings);
    for (var frame = 2; frame <= 6; frame++) {
      final next = await _draw(it, settings);
      final difference = compareFrames(first, next, channel: 0);
      expect(
        difference.differing,
        0,
        reason: 'frame $frame differs from the first: $difference',
      );
    }
  });

  test('and so are eight with a lamp that casts a shadow', () async {
    // **The one the editor found.** A cube shadow is drawn into an atlas tile
    // and kept until the tile's signature changes, and a static scene should
    // therefore draw one tile once and reuse it for ever. If instead the tile
    // is redrawn with a different answer on some frames, the room brightens and
    // darkens with nobody touching anything — which is what "the editor
    // flickers" looks like from the outside.
    final it = _room();
    const settings = RenderSettings(
      shadows: ShadowSettings(cascades: 1, resolution: 256),
    );

    final first = await _draw(it, settings);
    for (var frame = 2; frame <= 8; frame++) {
      final next = await _draw(it, settings);
      final difference = compareFrames(first, next, channel: 0);
      expect(
        difference.differing,
        0,
        reason: 'frame $frame differs from the first: $difference',
      );
    }
  });
}
