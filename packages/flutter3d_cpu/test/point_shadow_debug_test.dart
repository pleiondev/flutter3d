/// `RenderSettings.showPointShadowDebug`, drawn on the software rasteriser.
///
///     flutter test test/point_shadow_debug_test.dart
///
/// **A flag that did nothing here, and did not say so.** The setting reaches
/// `PointShadow.params2.w` on every backend; `lib/surface.glsl` reads it and
/// takes the surface buffer over with the penumbra estimate — red for how wide
/// the kernel came out, green for how far the blocker was, blue where the
/// search found nothing. This backend's transcription of that function skipped
/// the branch, so the composite dutifully switched to the surface buffer and
/// showed the ordinary octahedral normals: a plausible picture, and the worst
/// possible answer from a diagnostic, because a reader takes a radius off it.
///
/// The channel exists because two explanations for a collapsed estimate were
/// argued from the finished picture and both were wrong. A backend that shows
/// a different picture from the one the argument is about is that failure
/// again, one level down.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// A floor, a blocker above it, and a point light above that.
///
/// The blocker is held clear of the floor so there is both shadow to measure a
/// penumbra in and lit floor beyond it, where the eight-tap search finds
/// nothing and the channel answers blue.
({Scene scene, CameraNode camera}) _room() {
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
    ..add(block(Vector3(2.0, 0.4, 2.0), Vector3(0.0, 2.5, 0.0), 'blocker'))
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 60.0,
        range: 20.0,
        castsShadow: true,
        name: 'lamp',
      )..setPosition(0.0, 7.0, 0.0),
    );

  final camera = CameraNode()
    ..setPosition(0.0, 8.0, -10.0)
    ..lookAt(Vector3(0.0, 0.0, 0.5));
  return (scene: scene, camera: camera);
}

/// The frame, as RGBA bytes.
Future<List<int>> _frame({required bool debug}) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final room = _room();
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      // A radius of its own, so the contact-hardening search actually runs —
      // with it at zero the estimate is the fixed kernel and the green channel
      // has nothing to report.
      shadows: const ShadowSettings(pointLightRadius: 0.4),
      showPointShadowDebug: debug,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// How many pixels are mostly one channel, by that channel's index.
List<int> _dominant(List<int> pixels) {
  final counts = <int>[0, 0, 0];
  for (var at = 0; at < pixels.length; at += 4) {
    final r = pixels[at];
    final g = pixels[at + 1];
    final b = pixels[at + 2];
    final most = r >= g && r >= b ? 0 : (g >= b ? 1 : 2);
    if (<int>[r, g, b][most] > 60) counts[most]++;
  }
  return counts;
}

void main() {
  test('the flag shows the penumbra estimate and not the normals', () async {
    // The three colours the channel is defined in terms of. Blue is the one
    // worth naming: it marks where the search found nothing at all, which is a
    // different answer from "found a blocker touching the surface" and is the
    // distinction the whole diagnostic exists to draw. An octahedral normal
    // buffer of a floor seen from above is red and green and has no blue in it,
    // so blue is also what tells the two pictures apart.
    //
    // Mutation: delete the `if (debugging)` block in
    // `cpu_shaders_shadow_point.dart` — the surface buffer comes back as
    // normals, there is no blue, and this fails. Delete the `debugSurface`
    // branch in `writeSurface` and it fails the same way, which is the other
    // half of the same wire.
    final debug = await _frame(debug: true);
    final plain = await _frame(debug: false);

    expect(debug, isNot(equals(plain)), reason: 'the flag changed nothing');

    final counts = _dominant(debug);
    expect(
      counts[2],
      greaterThan(100),
      reason:
          'no fragment reported "the search found nothing", which is what the '
          'lit floor beyond the blocker is: the surface buffer is showing '
          'something other than the estimate',
    );
  });
}
