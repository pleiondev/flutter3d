/// A pane of glass in front of a striped wall, showing the wall through it.
///
/// Quoted by `transmission.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class TransmissionDemo extends ShowcaseDemo {
  double transmission = 1.0;
  double roughness = 0.0;
  double thickness = 0.9;
  double ior = 1.5;

  late final RenderMaterial _pane;
  late final RenderMaterial _ball;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 2.6
      ..yaw = 0.0
      ..pitch = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    final Quaternion upright = Quaternion.axisAngle(
      Vector3(1.0, 0.0, 0.0),
      math.pi / 2,
    );
    RenderMaterial flat(Vector4 color) => RenderMaterial(
      lighting: LightingModel.unlit,
      baseColor: _fromSrgb(color),
    );

    // #region wall
    final DeviceMesh half = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 3.0, depth: 4.0).build(),
    );
    final DeviceMesh stripe = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 0.08, depth: 4.0).build(),
    );
    final Scene scene = Scene()
      ..ambientIntensity = 0.2 * Photometric.legacyUnit
      ..add(
        MeshNode(half, flat(Vector4(0.8, 0.1, 0.1, 1.0)), name: 'red wall')
          ..setRotation(upright)
          ..setPosition(-1.5, 0.0, -2.0),
      )
      ..add(
        MeshNode(half, flat(Vector4(0.1, 0.2, 0.9, 1.0)), name: 'blue wall')
          ..setRotation(upright)
          ..setPosition(1.5, 0.0, -2.0),
      );
    for (var i = 0; i < 9; i++) {
      scene.add(
        MeshNode(stripe, flat(Vector4(0.95, 0.95, 0.9, 1.0)), name: 'stripe')
          ..setRotation(upright)
          ..setPosition(-2.0 + i * 0.5, 0.0, -1.98),
      );
    }
    // #endregion wall

    // #region glass
    RenderMaterial glass(String name, {required double thickness}) =>
        RenderMaterial(
          name: name,
          lighting: LightingModel.pbrLayered,
          baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 1.0),
          roughness: roughness,
          doubleSided: true,
          extensions: MaterialExtensions(
            transmission: transmission,
            thickness: thickness,
            ior: ior,
          ),
        );
    _pane = glass('pane', thickness: 0.0);
    _ball = glass('ball', thickness: thickness);
    scene
      ..add(
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 0.9, depth: 1.4).build(),
            ),
            _pane,
            name: 'pane',
          )
          ..setRotation(upright)
          ..setPosition(-0.6, 0.0, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.45, segments: 48, rings: 24).build(),
          ),
          _ball,
          name: 'ball',
        )..setPosition(0.6, 0.0, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -1.0).normalized()),
      );
    // #endregion glass
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    for (final (RenderMaterial material, double depth)
        in <(RenderMaterial, double)>[(_pane, 0.0), (_ball, thickness)]) {
      material
        ..roughness = roughness
        ..extensions = MaterialExtensions(
          transmission: transmission,
          thickness: depth,
          ior: ior,
        );
    }
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Transmission',
      min: 0,
      max: 1,
      value: () => transmission,
      onChanged: (double v) => transmission = v,
    ),
    SliderControl(
      'Roughness',
      min: 0,
      max: 1,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
    SliderControl(
      'Thickness',
      min: 0,
      max: 1.5,
      value: () => thickness,
      onChanged: (double v) => thickness = v,
      // In the mesh's own units, as glTF measures it, not metres.
      format: (double v) => '${v.toStringAsFixed(2)} units',
    ),
    SliderControl(
      'Index of refraction',
      min: 1.0,
      max: 2.4,
      value: () => ior,
      onChanged: (double v) => ior = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // A pane with no transmission is opaque, drawn in one pass as it always
    // was; at an index of 1.5 it is ordinary metal-rough, and at another
    // index it keeps that index's reflectance.
    if (transmission <= 0.0) return;
    final Set<String> ran = <String>{
      for (final FramePass pass in frame.passes) pass.name,
    };
    if (!ran.contains('scene colour copy')) {
      throw StateError(
        'the glass is in the frame but the scene was not copied',
      );
    }
    final FramePass? glass = frame.passes
        .where((FramePass p) => p.name == 'transparent')
        .firstOrNull;
    if (glass == null || glass.drawCalls < 1) {
      throw StateError('the pass that draws the glass drew nothing');
    }
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
