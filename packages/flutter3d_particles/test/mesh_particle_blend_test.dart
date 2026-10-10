/// Mesh particles that add light and mesh particles that take it away: one
/// shard over a grey background, drawn by the software backend through a
/// real renderer, once with each blend.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 32;
const double _grey = 0.5;

/// The middle pixel's red, as the composite hands it back, of a frame with
/// one particle of [color] at the origin drawn with [blend] over a grey clear.
double _middle(BlendState blend, Vector4 color) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final shard = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(1.0)).build(),
  );
  final particles = ParticleSystem(capacity: 1)
    ..burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(1.0),
        color: color,
      ),
      Vector3.zero(),
    );

  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 3.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()..add(camera);
  final renderer = Renderer.create(device: device)
    ..renderSteps.addContributor(
      MeshParticleContributor(particles, mesh: shard, blend: blend),
    );
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(
        camera: camera,
        clearColorSrgb: Vector4(_grey, _grey, _grey, 1.0),
      ),
    ],
    settings: const RenderSettings(
      tonemap: false,
      bloom: BloomSettings(enabled: false),
    ),
  );
  final Float32List frame = device.readHdrPixels(result.frame);
  return frame[((_size ~/ 2) * _size + _size ~/ 2) * 4];
}

void main() {
  // The grey with nothing over it, as the composite hands it back: a
  // particle of no colour changes nothing, whichever way it blends.
  final background = _middle(BlendState.additive, Vector4(0.0, 0.0, 0.0, 1.0));

  test('added, a particle brightens what is behind it', () {
    expect(
      _middle(BlendState.additive, Vector4(0.3, 0.3, 0.3, 1.0)),
      greaterThan(background + 0.1),
    );
  });

  test('darkening, it takes its colour out of what is behind it', () {
    expect(
      _middle(MeshParticleContributor.darkening, Vector4(0.6, 0.6, 0.6, 1.0)),
      lessThan(background - 0.2),
    );
    expect(
      _middle(MeshParticleContributor.darkening, Vector4(0.0, 0.0, 0.0, 1.0)),
      closeTo(background, 1e-6),
      reason: 'black takes nothing away',
    );
  });

  test('darkening, its alpha fades it towards nothing', () {
    final full = _middle(
      MeshParticleContributor.darkening,
      Vector4(0.6, 0.6, 0.6, 1.0),
    );
    final faint = _middle(
      MeshParticleContributor.darkening,
      Vector4(0.6, 0.6, 0.6, 0.25),
    );
    expect(faint, greaterThan(full + 0.1));
    expect(faint, lessThan(background));
  });
}
