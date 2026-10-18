/// A light that flickers like fire or pulses like something magical, with a
/// brightness that drives both the glow it draws and the light it casts.
///
/// Quoted by `light_fixtures.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The `light-fixtures` page: a torch whose brightness drives its glow and
/// its light. Its check is that a disabled fixture reports no brightness.
final class LightFixturesDemo extends ShowcaseDemo {
  /// Whether the torch pulses, rather than flickering like a flame.
  bool pulseInstead = false;

  late final LightNode _torchLight;
  late final RenderMaterial _torchMaterial;

  // #region fixture
  late LightFixture _fixture = LightFixture(
    name: 'torch',
    light: 'torch',
    behavior: const FlameFlicker(),
  );
  // #endregion fixture

  @override
  Scene build(DemoContext context) {
    _torchMaterial = RenderMaterial(
      name: 'torch',
      baseColor: LinearColor.fromSrgb(0.9, 0.6, 0.2, 1.0),
    );
    final ball = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      _torchMaterial,
      name: 'torch-ball',
    );
    _torchLight = LightNode(
      name: 'torch',
      intensity: 4.0 * LightNode.defaultIntensity,
    )..setLocalForward(Vector3(-0.2, -1.0, -0.1));
    return Scene()
      ..add(ball)
      ..add(_torchLight);
  }

  // #region step
  @override
  void update(DemoContext context, double dt) {
    _fixture.step(dt);
    _torchLight.intensity =
        4.0 * _fixture.brightness * LightNode.defaultIntensity;
    _torchMaterial.emissive = LinearColor(
      _fixture.brightness,
      _fixture.brightness * 0.6,
      _fixture.brightness * 0.2,
    );
  }
  // #endregion step

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Pulse instead of flicker',
      value: () => pulseInstead,
      onChanged: (bool v) {
        pulseInstead = v;
        _fixture = LightFixture(
          name: 'torch',
          light: 'torch',
          behavior: pulseInstead ? const PulseLight() : const FlameFlicker(),
        );
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the torch ball was not drawn');
    }
    // #region toggle
    // Switching the fixture off drops its brightness to zero on the next
    // step, whichever behaviour is driving it.
    _fixture.enabled = false;
    _fixture.step(1 / 60);
    // #endregion toggle
    if (_fixture.brightness != 0.0) {
      throw StateError('a disabled fixture should report no brightness');
    }
  }
}
