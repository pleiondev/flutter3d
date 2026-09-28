/// `LightType.area`: a rectangle with extent, so a room reads as lit by a
/// window rather than by a bright dot painted behind one, and a polished
/// floor shows the window's shape.
///
/// Quoted by `area_lights.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AreaLightsDemo extends ShowcaseDemo {
  double width = 2.5;
  double height = 1.5;
  double floorRoughness = 0.25;

  late final LightNode _window;
  late final MeshNode _pane;
  late final Material _glass;
  late final Material _floorMaterial;

  /// A plane is built lying down, facing +Y; a quarter turn about X stands
  /// it up facing +Z, into the room.
  static Quaternion get _standUp =>
      Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.5
      ..yaw = 0.45
      ..pitch = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region window
    // The panel faces the node's local -Z. Set in the back wall and aimed
    // at a point in front of it, it shines into the room.
    _window = LightNode(name: 'window', type: LightType.area, intensity: 8.0)
      ..width = width
      ..height = height
      ..setPosition(0.0, 0.3, -1.45);
    _window.lookAt(Vector3(0.0, 0.3, 3.0));
    // #endregion window

    // #region pane
    // The light itself is not drawn. A glowing rectangle of the same size,
    // just behind it, is what a person sees as the window.
    _glass = Material(
      name: 'window glass',
      baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
      emissive: Vector3(3.0, 3.0, 2.8),
    );
    _pane =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 1, depth: 1).build(),
            ),
            _glass,
            name: 'window pane',
          )
          ..setRotation(_standUp)
          ..setPosition(0.0, 0.3, -1.48);
    // #endregion pane

    // #region room
    final MeshNode backWall =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 6, depth: 4).build(),
            ),
            Material(
              name: 'wall',
              baseColor: Vector4(0.6, 0.58, 0.55, 1.0),
              roughness: 0.9,
              doubleSided: true,
            ),
            name: 'back wall',
          )
          ..setRotation(_standUp)
          ..setPosition(0.0, 0.0, -1.5);
    // #endregion room

    // #region floor
    // A floor of its own, so its roughness can go down to a polish.
    _floorMaterial = Material(
      name: 'floor',
      baseColor: Vector4(0.45, 0.45, 0.47, 1.0),
      roughness: floorRoughness,
    );
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 6, depth: 5).build(),
      ),
      _floorMaterial,
      name: 'floor',
    )..setPosition(0.0, -1.8, 1.0);
    // #endregion floor

    return Scene()
      ..add(backWall)
      ..add(_pane)
      ..add(floor)
      ..add(_window);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _window
      ..width = width
      ..height = height;
    _pane.setScale(width, 1.0, height);
    // The light's radiance is its intensity over its area, so a wider
    // window is dimmer per square metre. The pane dims by the same ratio,
    // measured from the 2.5 by 1.5 it starts at.
    final double dim = (2.5 * 1.5) / (width * height);
    _glass.emissive.setValues(3.0 * dim, 3.0 * dim, 2.8 * dim);
    _floorMaterial.roughness = floorRoughness;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Width',
      min: 0.5,
      max: 4,
      value: () => width,
      onChanged: (double v) => width = v,
    ),
    SliderControl(
      'Height',
      min: 0.5,
      max: 3,
      value: () => height,
      onChanged: (double v) => height = v,
    ),
    SliderControl(
      'Floor roughness',
      min: 0.05,
      max: 1,
      value: () => floorRoughness,
      onChanged: (double v) => floorRoughness = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_window.type != LightType.area) {
      throw StateError('the window is not an area light');
    }
    if (_window.width != width || _window.height != height) {
      throw StateError('the panel size did not track the sliders');
    }
    final Vector3 halfWidth = _window.readHalfWidth();
    final Vector3 halfHeight = _window.readHalfHeight();
    if (halfWidth.length2 == 0.0 || halfHeight.length2 == 0.0) {
      throw StateError('the panel has no extent to shade against');
    }
    if (_floorMaterial.roughness != floorRoughness) {
      throw StateError('the floor roughness did not track its slider');
    }
    if (frame.drawCalls < 3) {
      throw StateError('the room was not drawn');
    }
    // #endregion check
  }
}
