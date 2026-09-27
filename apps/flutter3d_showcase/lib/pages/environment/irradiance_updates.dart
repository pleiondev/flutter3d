/// The irradiance field kept current by the renderer: a few probes a frame
/// look at the room again, so the bounce follows a wall that changes colour.
///
/// Quoted by `irradiance_updates.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class IrradianceUpdatesDemo extends ShowcaseDemo {
  int wallColour = 0;
  double probesPerFrame = 2;
  double hysteresis = 0.9;

  late final Material _paint;
  late final IrradianceField _field;

  static final List<Vector4> _colours = <Vector4>[
    Vector4(0.85, 0.08, 0.08, 1.0),
    Vector4(0.08, 0.7, 0.12, 1.0),
    Vector4(0.1, 0.2, 0.85, 1.0),
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.35
      ..yaw = 0.5;
    context.orbit.target.setValues(-0.5, 1.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region room
    final Material floor = Material(
      name: 'floor',
      baseColor: Vector4(0.55, 0.55, 0.55, 1.0),
      roughness: 0.95,
      doubleSided: true,
    );
    _paint = Material(
      name: 'painted wall',
      baseColor: _colours[wallColour].clone(),
      roughness: 0.95,
      doubleSided: true,
    );
    final Scene scene = Scene()
      ..ambientIntensity = 1.0
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 6, depth: 6).build(),
          ),
          floor,
          name: 'floor',
        ),
      )
      ..add(
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 3, depth: 4).build(),
            ),
            _paint,
            name: 'wall',
          )
          ..setPosition(-2.0, 1.5, 0.0)
          ..setRotation(Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), -1.5708)),
      )
      ..add(
        LightNode(
          name: 'lamp',
          type: LightType.point,
          intensity: 30.0,
          range: 12.0,
        )..setPosition(-0.8, 2.5, 0.0),
      );
    // #endregion room

    // #region field
    _field =
        IrradianceField(
            origin: Vector3(-1.0, 0.5, -1.0),
            spacing: Vector3(1.0, 1.0, 1.0),
            countX: 2,
            countY: 2,
            countZ: 2,
          )
          ..gpuUpdates = probesPerFrame.round()
          ..fillGutters();
    scene.irradianceField = _field;
    // #endregion field
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _paint.baseColor.setFrom(_colours[wallColour]);
    _field
      ..gpuUpdates = probesPerFrame.round()
      ..hysteresis = hysteresis;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Wall colour',
      options: const <String>['Red', 'Green', 'Blue'],
      index: () => wallColour,
      onChanged: (int i) => wallColour = i,
    ),
    SliderControl(
      'Probes a frame',
      min: 1,
      max: 8,
      divisions: 7,
      value: () => probesPerFrame,
      onChanged: (double v) => probesPerFrame = v,
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Hysteresis',
      min: 0,
      max: 0.99,
      value: () => hysteresis,
      onChanged: (double v) => hysteresis = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final PassSkip? skipped = frame.skipReasonOf('irradiance update');
    if (skipped != null) {
      throw StateError('the probe update was skipped: $skipped');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'irradiance update')) {
      throw StateError('no probe was updated this frame');
    }
  }
}
