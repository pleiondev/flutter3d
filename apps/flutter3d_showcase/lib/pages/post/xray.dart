/// X-ray silhouettes: the outline of what a wall hides, painted over the wall.
///
/// Quoted by `xray.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class XrayDemo extends ShowcaseDemo {
  bool enabled = true;
  int colourChoice = 0;

  // #region layer
  /// One bit of `layerMask`, picked so it does not collide with the default.
  static const int _watched = 1 << 2;
  // #endregion layer

  static const List<String> _colourNames = <String>['Orange', 'Green', 'Cyan'];

  Vector3 get _colour => switch (colourChoice) {
    1 => Vector3(0.1, 1.0, 0.2),
    2 => Vector3(0.1, 0.9, 1.0),
    _ => Vector3(1.0, 0.32, 0.08),
  };

  late final int _meshCount;
  late final bool _stencil;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.2
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.0, 0.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;
    _stencil = device.supportsStencil;

    final MeshNode floor = MeshNode(
      DeviceMesh.upload(device, const PlaneShape(width: 12, depth: 12).build()),
      Material(
        name: 'floor',
        baseColor: Vector4(0.5, 0.5, 0.52, 1.0),
        roughness: 0.9,
        doubleSided: true,
      ),
      name: 'floor',
    );

    final MeshNode wall = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(4.0, 2.4, 0.3)).build(),
      ),
      Material(
        name: 'wall',
        baseColor: Vector4(0.65, 0.6, 0.55, 1.0),
        roughness: 0.9,
      ),
      name: 'wall',
    )..setPosition(0.0, 1.2, 0.0);

    // #region hidden
    final MeshNode monster = MeshNode(
      DeviceMesh.upload(
        device,
        const CapsuleShape(radius: 0.4, height: 0.9).build(),
      ),
      Material(
        name: 'monster',
        baseColor: Vector4(0.3, 0.7, 0.35, 1.0),
        roughness: 0.5,
      ),
      name: 'monster',
    )..setPosition(0.0, 0.85, -2.0);
    monster.layerMask = 1 | _watched;
    // #endregion hidden

    _meshCount = 3;
    return Scene()
      ..add(floor)
      ..add(wall)
      ..add(monster)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.6)),
      );
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    xray: XraySettings(layerMask: enabled ? _watched : 0, color: _colour),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'X-ray',
      value: () => enabled,
      onChanged: (bool v) => enabled = v,
    ),
    ChoiceControl(
      'Colour',
      options: _colourNames,
      index: () => colourChoice,
      onChanged: (int i) => colourChoice = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region draws
    final int drawn = frame.passes
        .firstWhere((FramePass p) => p.name == 'scene')
        .drawCalls;
    final int extra = enabled && _stencil ? 2 : 0;
    if (drawn != _meshCount + extra) {
      throw StateError(
        'the scene pass made $drawn draws; $_meshCount meshes and '
        '$extra x-ray draws were expected',
      );
    }
    // #endregion draws
  }
}
