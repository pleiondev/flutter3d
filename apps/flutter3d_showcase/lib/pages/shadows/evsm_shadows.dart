/// The sun's shadow map turned into exponential moments, blurred once, and
/// read back with one filtered tap per pixel.
///
/// Quoted by `evsm_shadows.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class EvsmShadowsDemo extends ShowcaseDemo {
  int filterChoice = 2;
  double blurRadius = 4;
  double bleedReduction = 0.2;

  // #region filters
  static const List<ShadowFilter> _filters = <ShadowFilter>[
    ShadowFilter.pcf,
    ShadowFilter.pcss,
    ShadowFilter.evsm,
  ];
  // #endregion filters

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.3
      ..pitch = 0.81
      ..yaw = 0.27;
  }

  @override
  Scene build(DemoContext context) {
    MeshNode slab(
      String name,
      Vector3 size,
      Vector3 at,
      RenderMaterial material,
    ) => MeshNode(
      DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
      material,
      name: name,
    )..setPosition(at.x, at.y, at.z);

    // #region casters
    final RenderMaterial grey = RenderMaterial(
      name: 'grey',
      baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.62, 1.0),
    );
    final Scene scene = Scene()
      ..add(
        slab(
          'floor',
          Vector3(14.0, 0.2, 14.0),
          Vector3(0.0, -0.1, 0.0),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.52, 1.0),
          ),
        ),
      )
      ..add(slab('box', Vector3(1.6, 0.2, 1.6), Vector3(0.0, 0.6, 0.0), grey))
      ..add(
        slab('post', Vector3(0.2, 1.5, 0.2), Vector3(-2.0, 0.75, 1.0), grey),
      );
    // #endregion casters

    // #region sun
    final LightNode sun = LightNode(
      name: 'sun',
      intensity: 1.5 * Photometric.legacyUnit,
    )..setLocalForward(Vector3(-0.85, -1.0, -0.2).normalized());
    // #endregion sun
    return scene..add(sun);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: ShadowSettings(
      cascades: 1,
      viewDistance: 20.0,
      filter: _filters[filterChoice],
      evsmBlurRadius: blurRadius.round(),
      evsmBleedReduction: bleedReduction,
      directionalLightRadius: 0.02,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Filter',
      options: const <String>['PCF', 'PCSS', 'EVSM'],
      index: () => filterChoice,
      onChanged: (int i) => filterChoice = i,
    ),
    SliderControl(
      'Blur radius',
      min: 0,
      max: 8,
      divisions: 8,
      value: () => blurRadius,
      onChanged: (double v) => blurRadius = v,
      format: (double v) => '${v.round()} texels',
    ),
    SliderControl(
      'Bleed reduction',
      min: 0,
      max: 0.95,
      value: () => bleedReduction,
      onChanged: (double v) => bleedReduction = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!frame.passes.any((FramePass p) => p.name == 'directional shadows')) {
      throw StateError('the sun drew no shadow map to filter');
    }
    if (_filters[filterChoice] != ShadowFilter.evsm) return;
    final PassSkip? skipped = frame.skipReasonOf('shadow moments');
    if (skipped != null) {
      throw StateError('the moments were refused: $skipped');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'shadow moments')) {
      throw StateError('the shadow map was never turned into moments');
    }
  }
}
