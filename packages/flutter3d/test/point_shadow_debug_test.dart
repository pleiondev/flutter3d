/// The penumbra estimate, painted into the surface buffer, without a GPU.
///
///     flutter test test/point_shadow_debug_test.dart
///
/// `RenderSettings.showPointShadowDebug` exists because two explanations for a
/// collapsing contact-hardening estimate were argued from the finished picture
/// and both turned out wrong: the quantity that settles it never leaves the
/// shadow lookup. Impeller and WebGL painted it; this rasteriser packed the
/// flag into `params2.w`, never read it, and drew the ordinary surface buffer —
/// so the backend that needs no device, and is therefore the one a headless
/// session reaches for, answered a plausible picture that was not the estimate.
/// That is the exact failure mode the channel was added to end.
///
/// What is asserted is a *difference*, not a colour: the debug view and the
/// plain surface view must not be the same picture. A brightness threshold
/// would pass on the day the channel stopped being written and the normals
/// happened to land in range.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 72;

({CpuDevice device, Renderer renderer}) _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

/// A floor, a torch above it, and a slab held in the light.
///
/// The slab is clear of the floor for the reason `cube-shadow-gap` is: a caster
/// resting on its receiver leaves the penumbra no room to open, and a debug
/// view of an estimate that is everywhere at its floor says nothing.
({Scene scene, CameraNode camera}) _room({bool castsShadow = true}) {
  final scene = Scene();
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode block(Vector3 size, Vector3 at, String name) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(
      name: name,
      baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
      lighting: LightingModel.pbr,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  scene
    ..add(block(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0), 'floor'))
    ..add(block(Vector3(1.2, 0.4, 1.2), Vector3(0.0, 2.6, 0.0), 'slab'))
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 60.0,
        range: 20.0,
        castsShadow: castsShadow,
        name: 'torch',
      )..setPosition(0.0, 7.0, 0.0),
    );

  final camera = CameraNode()
    ..setPosition(0.0, 9.0, -11.0)
    ..lookAt(Vector3(0.0, 0.0, 0.5));
  return (scene: scene, camera: camera);
}

/// The frame the composite hands back, as the parity grid reads it.
Future<List<int>> _grid(
  ({Scene scene, CameraNode camera}) room, {
  required RenderSettings settings,
}) async {
  final engine = _engine();
  final frame = engine.renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: settings,
  );
  final pixels = await engine.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return parityGrid(pixels!.buffer.asUint8List(), _width, _height);
}

RenderSettings _settings({
  bool debug = false,
  bool surface = false,
  double lightRadius = 0.0,
}) => RenderSettings(
  bloom: const BloomSettings(enabled: false),
  shadows: ShadowSettings(pointLightRadius: lightRadius),
  showSurfaceBuffer: surface,
  showPointShadowDebug: debug,
);

void main() {
  test('the estimate is a different picture from the surface buffer', () async {
    // Mutation: drop the `if (debug)` writes in
    // `cpu_shaders_shadow_point.dart`, or the `c.debugSurface` branch in
    // `writeSurface`, and the two grids come back identical — which is the
    // state this backend shipped in.
    final room = _room();
    final surface = await _grid(room, settings: _settings(surface: true));
    final estimate = await _grid(room, settings: _settings(debug: true));

    expect(
      estimate,
      isNot(surface),
      reason: 'the debug view drew the ordinary surface buffer',
    );
  });

  test('and so it is with a light wide enough to search for blockers', () async {
    // The other branch. A radius above zero runs the blocker search, so the
    // estimate comes from a measured penumbra rather than from the floor of the
    // clamp; a transcription that filled the channel in only one of the two
    // would pass the test above and fail here.
    final room = _room();
    final surface = await _grid(
      room,
      settings: _settings(surface: true, lightRadius: 0.3),
    );
    final estimate = await _grid(
      room,
      settings: _settings(debug: true, lightRadius: 0.3),
    );

    expect(estimate, isNot(surface));
  });

  test('a light that casts nothing writes no estimate at all', () async {
    // The channel belongs to the shadow lookup, and a lookup that never runs
    // must leave the buffer as the geometry wrote it. Without this, the test
    // above would also pass for a transcription that painted the channel from
    // somewhere unrelated to the shadow.
    final dark = _room(castsShadow: false);
    final surface = await _grid(dark, settings: _settings(surface: true));
    final estimate = await _grid(dark, settings: _settings(debug: true));

    expect(estimate, surface);
  });
}
