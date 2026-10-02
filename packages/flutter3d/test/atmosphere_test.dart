/// The air of a scene at one moment, a day of it, lights dimmed together,
/// and a horizon the fog does not reach.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Atmosphere _noon() => Atmosphere(
  sky: Vector3(0.4, 0.6, 0.9),
  sunColor: Vector3(1.0, 1.0, 0.9),
  sunIntensity: 3.0,
  ambientIntensity: 0.4,
);

Atmosphere _night() => Atmosphere(
  sky: Vector3(0.0, 0.0, 0.1),
  fogDensity: 0.02,
  sunColor: Vector3(0.2, 0.2, 0.4),
  sunIntensity: 0.2,
  ambientIntensity: 0.05,
);

void main() {
  test('a blend moves every part of the air by the same amount', () {
    // Mutation: blend the sun by the amount and the sky by another.
    final dusk = Atmosphere.lerp(_noon(), _night(), 0.5);
    expect(dusk.sky.z, closeTo(0.5, 1e-6));
    expect(dusk.sunIntensity, closeTo(1.6, 1e-6));
    expect(dusk.fogDensity, closeTo(0.01, 1e-6));
    expect(dusk.fog.density, closeTo(0.01, 1e-6));
  });

  test('a height fog blends with the rest of the air and reaches the fog', () {
    // `P5`. Mutation: leave the two new fields out of `lerp`, or out of the
    // `fog` getter. A morning mist that is meant to lift through the day
    // either never lifts or never lies on the ground at all.
    final mist = Atmosphere(
      sky: Vector3(0.6, 0.6, 0.6),
      fogDensity: 0.05,
      fogHeightFalloff: 0.2,
      fogBaseHeight: 2.0,
      sunColor: Vector3(1.0, 1.0, 1.0),
    );
    final half = Atmosphere.lerp(_noon(), mist, 0.5);
    expect(half.fogHeightFalloff, closeTo(0.1, 1e-9));
    expect(half.fogBaseHeight, closeTo(1.0, 1e-9));
    expect(half.fog.heightFalloff, closeTo(0.1, 1e-9));
    expect(half.fog.baseHeight, closeTo(1.0, 1e-9));
  });

  test('a day goes round, blending the last key back into the first', () {
    final day = AtmosphereCycle(<(double, Atmosphere)>[
      (0.0, _noon()),
      (60.0, _night()),
    ], period: 120.0);
    expect(day.at(0.0).sunIntensity, closeTo(3.0, 1e-6));
    expect(day.at(30.0).sunIntensity, closeTo(1.6, 1e-6));
    expect(day.at(60.0).sunIntensity, closeTo(0.2, 1e-6));
    expect(day.at(90.0).sunIntensity, closeTo(1.6, 1e-6), reason: 'dawn');
    expect(day.at(150.0).sunIntensity, closeTo(1.6, 1e-6), reason: 'wrapped');
  });

  test('the air goes onto a scene, its sun and its sky', () {
    final scene = Scene();
    final sun = LightNode(type: LightType.directional, intensity: 1.0);
    final clear = Vector4.zero();
    _night().applyTo(scene, sun: sun, clearColor: clear);
    expect(scene.ambientIntensity, closeTo(0.05, 1e-6));
    expect(sun.intensity, closeTo(0.2, 1e-6));
    expect(clear.z, closeTo(0.1, 1e-6));
  });

  test('a group of lights dims together and comes back as it was', () {
    // Mutation: write the level into each light as its intensity.
    final low = LightNode(intensity: 2.0);
    final high = LightNode(intensity: 8.0);
    final lamps = LightGroup(<LightNode>[low, high])..level = 0.0;
    expect(low.intensity, 0.0);
    lamps.level = 0.5;
    expect(low.intensity, 1.0);
    expect(high.intensity, 4.0);
    lamps.level = 1.0;
    expect(high.intensity, 8.0);
  });

  test('a material outside the fog stays its colour through it', () async {
    // A horizon of hills through thick fog: fogged, it is the fog's colour;
    // not, it is its own.
    //
    // Mutation: fog every material.
    Future<int> red({required bool fogged}) async {
      final it = cpuTestDevice(width: 16, height: 16);
      final hill = MeshNode(
        DeviceMesh.upload(
          it.device,
          CuboidShape(size: Vector3.all(20.0)).build(),
        ),
        Material(
          baseColor: Vector4(1.0, 0.0, 0.0, 1.0),
          lighting: LightingModel.unlit,
          fogged: fogged,
        ),
      )..setPosition(0.0, 0.0, -80.0);
      final camera = CameraNode()..lookAt(Vector3(0.0, 0.0, -1.0));
      final scene = Scene()
        ..add(camera)
        ..add(hill);
      final frame =
          Renderer.create(
            device: it.device,
            fallbackAlbedo: it.albedo,
            fallbackNormal: it.normal,
          ).render(
            width: 16,
            height: 16,
            scene: scene,
            views: <RenderView>[RenderView(camera: camera)],
            settings: RenderSettings(
              tonemap: false,
              fog: FogSettings(color: Vector3(0.0, 0.0, 1.0), density: 0.2),
            ),
          );
      final pixels = await it.device.readPixels(frame.frame);
      return pixels!.buffer.asUint8List()[(8 * 16 + 8) * 4];
    }

    expect(await red(fogged: true), lessThan(40));
    expect(await red(fogged: false), greaterThan(200));
  });
}
