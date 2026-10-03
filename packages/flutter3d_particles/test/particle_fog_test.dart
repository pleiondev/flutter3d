/// Particles fog as the lit scene does — `P7`, `P5`: by depth through an
/// orthographic lens, and thinning upwards in a height fog.
///
///     dart test test/particle_fog_test.dart
///
/// The particle stages declared the fog's block with two of its four members,
/// the colour and the eye. They could not tell an orthographic camera from a
/// perspective one, so they fogged in rings round the eye's point, which
/// through an orthographic lens is only where the camera was put; and they
/// could not read the height fog's falloff, so a puff of smoke fogged at the
/// camera's density whatever its height. Drawn by the software backend
/// through a real renderer.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// The red, linear, of the pixels at [pixels] when discs two metres across
/// stand at [at], seen by [camera] under [fog].
List<double> _red({
  required CameraNode camera,
  required List<Vector3> at,
  required List<(int, int)> pixels,
  FogSettings fog = const FogSettings(),
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final particles = ParticleSystem(capacity: at.length);
  for (final where in at) {
    particles.burst(
      ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(2.0),
        color: Vector4(0.8, 0.5, 0.2, 1.0),
      ),
      where,
    );
  }
  final scene = Scene()..add(camera);
  final renderer = Renderer.create(device: device)
    ..addContributor(ParticleContributor(particles));
  final result = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog,
    ),
  );
  final frame = device.readHdrPixels(result.frame);
  return <double>[
    for (final (x, y) in pixels)
      switch (frame[(y * _size + x) * 4]) {
        final encoded when encoded <= 0.04045 => encoded / 12.92,
        final encoded => math.pow((encoded + 0.055) / 1.055, 2.4).toDouble(),
      },
  ];
}

void main() {
  test('through an orthographic lens two discs at one depth fog alike', () {
    // One on the axis and one three metres to the side, both five metres
    // deep: the same air between them and the eye's plane.
    //
    // Mutation: fog by distance from the eye whatever the lens, as before
    // `P7`. The one to the side is 5.8 m from the eye's point and comes out
    // a quarter darker.
    CameraNode camera() =>
        CameraNode()
          ..projection = const OrthographicProjection(height: 8.0, far: 100.0);
    final at = <Vector3>[Vector3(0.0, 0.0, -5.0), Vector3(3.0, 0.0, -5.0)];
    // Six pixels a metre, so three metres right of the middle is pixel 42.
    const pixels = <(int, int)>[(24, 24), (42, 24)];
    final clear = _red(camera: camera(), at: at, pixels: pixels);
    final fogged = _red(
      camera: camera(),
      at: at,
      pixels: pixels,
      fog: FogSettings(color: Vector3.zero(), density: 0.4),
    );

    expect(clear[0], greaterThan(0.05), reason: 'the middle disc is not there');
    expect(clear[1], greaterThan(0.05), reason: 'the side disc is not there');
    final middle = fogged[0] / clear[0];
    final side = fogged[1] / clear[1];
    expect(middle, closeTo(math.exp(-0.4 * 5.0), 0.02));
    expect(side, closeTo(middle, 0.02));
  });

  test('in a height fog a disc above the eye fogs as thin air does', () {
    // The camera at the fog's base looking up at a disc four metres higher
    // and five ahead: the air along the way thins towards it, and the share
    // the disc keeps is the closed form `ApplyFog` integrates for the lit
    // stages.
    //
    // Mutation: drop the falloff from `ParticleFogTransmittance`. The disc
    // fogs at the camera's density the whole way and comes out darker.
    final target = Vector3(0.0, 4.0, -5.0);
    CameraNode camera() => CameraNode()..lookAt(target);
    final fog = FogSettings(
      color: Vector3.zero(),
      density: 0.4,
      heightFalloff: 0.5,
    );
    const pixels = <(int, int)>[(24, 24)];
    final clear = _red(camera: camera(), at: <Vector3>[target], pixels: pixels);
    final fogged = _red(
      camera: camera(),
      at: <Vector3>[target],
      pixels: pixels,
      fog: fog,
    );

    final k = 0.5 * 4.0;
    final mean = (1.0 - math.exp(-k)) / k;
    final expected = math.exp(-fog.densityAt(0.0) * mean * target.length);
    expect(clear.single, greaterThan(0.05), reason: 'the disc is not there');
    expect(fogged.single / clear.single, closeTo(expected, 0.02));
    expect(
      fogged.single / clear.single,
      greaterThan(math.exp(-fog.densityAt(0.0) * target.length) + 0.05),
      reason: 'fogged at the camera\'s density the whole way',
    );
  });
}
