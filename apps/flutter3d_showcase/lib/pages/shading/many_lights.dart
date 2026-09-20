/// Thirty-two lights on one draw: eight in the shader's own slots and
/// twenty-four more through the light list, with `lightFadeBand` softening
/// the edge between them.
///
/// Quoted by `many_lights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ManyLightsDemo extends ShowcaseDemo {
  double fadeBand = 0.5;

  /// Eight direct slots plus the twenty-four-light tail is thirty-two; eight
  /// more than that is what a floor this crowded actually has to drop.
  static const int _torchCount = 40;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.7;
  }

  @override
  Scene build(DemoContext context) {
    // #region floor
    // One plane, one draw, and a bounding sphere wide enough to reach every
    // torch — the case `LightBuffer.gatherNearFrom` exists for.
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 20, depth: 20).build(),
      ),
      Material(
        baseColor: Vector4(0.5, 0.5, 0.55, 1.0),
        roughness: 0.85,
        doubleSided: true,
      ),
      name: 'floor',
    );
    // #endregion floor

    final Scene scene = Scene()..add(floor);

    // #region torches
    for (var i = 0; i < _torchCount; i++) {
      final double angle = i / _torchCount * 2.0 * math.pi;
      scene.add(
        LightNode(
          name: 'torch $i',
          type: LightType.point,
          intensity: 2.5,
          range: 3.5,
        )..setPosition(math.cos(angle) * 6.0, 0.6, math.sin(angle) * 6.0),
      );
    }
    // #endregion torches

    return scene;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    lightFadeBand: fadeBand,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Fade band',
      min: 0,
      max: 1,
      value: () => fadeBand,
      onChanged: (double v) => fadeBand = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (scene.lights.length != _torchCount) {
      throw StateError(
        'expected $_torchCount torches, found '
        '${scene.lights.length}',
      );
    }
    final int expectedDropped = math.max(
      _torchCount - LightBuffer.maxLights - LightBuffer.maxExtraLights,
      0,
    );
    if (expectedDropped == 0) {
      throw StateError(
        'this scene needs more torches than the cap to prove '
        'anything is actually dropped',
      );
    }
    if (frame.lightsDropped != expectedDropped) {
      throw StateError(
        'expected $expectedDropped lights past the eight slots and the '
        'twenty-four-light tail, the frame reports ${frame.lightsDropped}',
      );
    }
    if (frame.drawCalls < 1) {
      throw StateError('the floor was not drawn');
    }
    // #endregion check
  }
}
