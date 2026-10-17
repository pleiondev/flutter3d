/// Particles in a height fog — `P5`: the air thins upwards for a puff of
/// smoke as it does for the ground beside it.
///
///     dart test test/particle_height_fog_test.dart
///
/// The particle stages were handed the fog as thick as it is at the camera
/// and fogged by distance at that density the whole way, so a spark high
/// above the eye fogged as if the air up there were as thick as the air
/// round the camera, while the wall behind it thinned out of the fog. Every
/// stage now integrates the height fog along the ray as the lit stages'
/// `ApplyFog` does. Drawn by the software backend through a real renderer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;

enum _Stage { disc, sprite, sixWay, mesh }

/// Where the particle stands: four metres above the camera, five ahead.
final Vector3 _target = Vector3(0.0, 4.0, -5.0);

/// The brightest red round the middle of the frame, linear, with the camera at the
/// origin looking at one particle at [_target] under [fog].
double _brightest(_Stage stage, {FogSettings fog = const FogSettings()}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  TextureHandle upload(int width, int height, Uint8List bytes) =>
      device.createTextureFromPixels(
        width: width,
        height: height,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(bytes),
      );

  final particles = ParticleSystem(capacity: 1)
    ..burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(1.5),
        color: LinearColor(0.8, 0.5, 0.2, 1.0),
      ),
      _target,
    );
  final camera = CameraNode()..lookAt(_target);
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
                  ambient: LinearColor.white,
                ),
        );
  final renderer = Renderer.create(device: device)
    ..renderSteps.addContributor(contributor);
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <CameraView>[
      CameraView(
        camera: camera,
        clearColor: LinearColor.fromSrgb(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog,
    ),
  );
  // The frame holds sRGB-encoded values; the shares compared are linear.
  final frame = device.readHdrPixels(result.frame);
  final encoded = <double>[
    for (var x = _size ~/ 2 - 2; x < _size ~/ 2 + 2; x++)
      for (var y = _size ~/ 2 - 2; y < _size ~/ 2 + 2; y++)
        frame[(y * _size + x) * 4],
  ].reduce(math.max);
  return encoded <= 0.04045
      ? encoded / 12.92
      : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
}

void main() {
  final fog = FogSettings(
    color: LinearColor.black,
    density: 0.4,
    heightFalloff: 0.5,
    baseHeight: 0.0,
  );
  // The share `ApplyFog` keeps of a fragment four metres above the eye: the
  // density at the eye times the mean of e^(−falloff·h) over the climb.
  final k = 0.5 * _target.y;
  final mean = (1.0 - math.exp(-k)) / k;
  final expected = math.exp(-fog.densityAt(0.0) * mean * _target.length);
  final atCamera = math.exp(-fog.densityAt(0.0) * _target.length);

  for (final stage in _Stage.values) {
    test('a ${stage.name} particle above the eye fogs as the thinner air '
        'there does', () {
      // Mutation: drop the falloff from `FogTransmittance` in
      // `cpu_shaders_particles.dart` (or leave `eye.w` unbound in the
      // contributor), and the particle fogs at the camera's density the
      // whole way: a third of what it keeps here.
      final clear = _brightest(stage);
      final fogged = _brightest(stage, fog: fog);
      expect(clear, greaterThan(0.01), reason: 'the particle is not there');
      expect(fogged / clear, closeTo(expected, 0.02));
      expect(
        fogged / clear,
        greaterThan(atCamera + 0.05),
        reason: "fogged at the camera's density the whole way",
      );
    });
  }
}
