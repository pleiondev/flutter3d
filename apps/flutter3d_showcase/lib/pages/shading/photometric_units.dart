/// `Photometric`: lux and lumens off a datasheet, converted into
/// `LightNode.intensity` instead of tuned by eye.
///
/// Quoted by `photometric_units.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class PhotometricUnitsDemo extends ShowcaseDemo {
  double overcastLux = 10000.0;
  double lampLumens = 800.0;

  late final LightNode _sky;
  late final LightNode _lamp;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 32, rings: 16).build(),
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          sphere,
          RenderMaterial(baseColor: LinearColor.fromSrgb(0.8, 0.8, 0.8, 1.0)),
          name: 'ball',
        ),
      );

    // #region directional
    // A directional light has no falloff, so its intensity is what a surface
    // facing it reads: lux is the unit its own datasheet would give.
    _sky = LightNode(name: 'sky', intensity: overcastLux)
      ..setLocalForward(Vector3(-0.3, -0.7, -0.5));
    // #endregion directional

    // #region point
    // An 800 lm bulb is the ordinary sixty-watt incandescent it replaced.
    _lamp = LightNode(
      name: 'lamp',
      type: LightType.point,
      intensity: Photometric.fromLumens(lampLumens),
      range: 8.0,
    )..setPosition(1.6, 1.2, 1.0);
    // #endregion point

    return scene
      ..add(_sky)
      ..add(_lamp);
  }

  // #region exposure
  // Lux and candela are absolute, so the camera has to be set for them as a
  // photographer would be: metered once for the overcast sky the page opens
  // under, plus the scene's flat ambient (in the engine's pre-1.0 unit), and
  // then left alone. About EV100 12, f/4 at roughly a two-hundred-and-fiftieth;
  // the sliders then brighten and darken the picture, as the weather would.
  static final PhysicalCamera _camera = PhysicalCamera.metered(
    10000.0 + 0.06 * Photometric.legacyUnit,
  );

  @override
  RenderSettings settings(DemoContext context) =>
      RenderSettings(camera: _camera);
  // #endregion exposure

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _sky.intensity = overcastLux;
    _lamp.intensity = Photometric.fromLumens(lampLumens);
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Sky (lux)',
      min: 500,
      max: 20000,
      value: () => overcastLux,
      onChanged: (double v) => overcastLux = v,
    ),
    SliderControl(
      'Lamp (lumens)',
      min: 100,
      max: 1600,
      value: () => lampLumens,
      onChanged: (double v) => lampLumens = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    const double epsilon = 1e-6;
    if ((_sky.intensity - overcastLux).abs() > epsilon) {
      throw StateError('the sky intensity does not convert back to its lux');
    }
    if ((Photometric.toLumens(_lamp.intensity) - lampLumens).abs() > epsilon) {
      throw StateError('the lamp intensity does not convert back to lumens');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
