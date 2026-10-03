/// Particles through an orthographic camera — `P7`.
///
///     dart test test/orthographic_particles_test.dart
///
/// Every particle stage measured its fog from the eye's position, and a mesh
/// particle lit its faces by how squarely they faced it. Through an
/// orthographic lens the eye is only where the camera was put along its axis
/// and moves nothing in the picture, so a particle off the axis came out
/// foggier, and a shard's face turned towards the camera dimmer, than the
/// same particle on it. Two identical particles at the same depth, one on the
/// axis and one off it, must now draw the same.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 24;

enum _Stage { disc, sprite, sixWay, mesh }

/// The brightest light in the eight columns on either side of each of the
/// two particles' centres — on the axis, and four metres to the right of it.
({double onAxis, double offAxis}) _pair(_Stage stage, {FogSettings? fog}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle upload(int width, int height, Uint8List bytes) =>
      device.createTextureFromPixels(
        width: width,
        height: height,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(bytes),
      )!;

  final effect = ParticleEffect(
    count: 1,
    emitter: const SphereEmitter(speed: Range.exact(0.0)),
    lifetime: const Range.exact(5.0),
    size: const Range.exact(1.5),
    color: Vector4(0.8, 0.5, 0.2, 1.0),
  );
  final particles = ParticleSystem(capacity: 2)
    ..burst(effect, Vector3(0.0, 0.0, -5.0))
    ..burst(effect, Vector3(4.0, 0.0, -5.0));

  // Two pixels to the metre, looking down -z from the origin.
  final camera = CameraNode()
    ..projection = const OrthographicProjection(height: 12.0);
  final scene = Scene()..add(camera);

  final white = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
  final sheet = stage == _Stage.sixWay
      ? bakeSixWay(density: smokePuff(), frames: 1, columns: 1, cell: 16)
      : null;
  final PassContributor contributor = stage == _Stage.mesh
      ? MeshParticleContributor(
          particles,
          mesh: DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3.all(1.0)).build(),
          ),
        )
      : ParticleContributor(
          particles,
          texture: stage == _Stage.sprite ? upload(4, 4, white) : null,
          sixWay: sheet == null
              ? null
              : SixWayMaterial(
                  positive: upload(sheet.width, sheet.height, sheet.positive),
                  negative: upload(sheet.width, sheet.height, sheet.negative),
                  ambient: Vector3(1.0, 1.0, 1.0),
                ),
        );
  final renderer = Renderer.create(device: device)..addContributor(contributor);
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog ?? const FogSettings(),
    ),
  );
  final frame = device.readHdrPixels(result.frame);
  double brightest(int centre) => <double>[
    for (var x = centre - 4; x < centre + 4; x++)
      for (var y = _height ~/ 2 - 2; y < _height ~/ 2 + 2; y++)
        frame[(y * _width + x) * 4],
  ].reduce(math.max);
  return (onAxis: brightest(_width ~/ 2), offAxis: brightest(_width ~/ 2 + 8));
}

void main() {
  for (final stage in _Stage.values) {
    test('a ${stage.name} particle off the axis fogs as one on it', () {
      // Mutation: measure `FogDistance` in `cpu_shaders_particles.dart` from
      // the eye's position — the one off the axis is 6.4 metres away rather
      // than 5, and a fifth of a metre's density leaves it a quarter darker.
      final it = _pair(
        stage,
        fog: FogSettings(color: Vector3.zero(), density: 0.2),
      );
      expect(it.onAxis, greaterThan(0.02), reason: 'no particle on the axis');
      expect(it.offAxis, closeTo(it.onAxis, it.onAxis * 0.02));
    });
  }

  test('a mesh particle off the axis is lit as one on it', () {
    // Mutation: measure `TowardsEyeFrom` from the eye's position — the face
    // of the shard off the axis turns thirty-nine degrees from it and dims.
    final it = _pair(_Stage.mesh);
    expect(it.onAxis, greaterThan(0.02), reason: 'no particle on the axis');
    expect(it.offAxis, closeTo(it.onAxis, it.onAxis * 0.02));
  });
}
