/// Coloured panes at three depths and two that cross through each other,
/// composited sorted or without a sort.
///
/// Quoted by `order_independent_transparency.md` and shown whole in the Source
/// tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class OrderIndependentTransparencyDemo extends ShowcaseDemo {
  int mode = 1;

  static const List<TransparencyMode> _modes = <TransparencyMode>[
    TransparencyMode.sorted,
    TransparencyMode.weightedBlended,
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.2
      ..yaw = 0.35
      ..pitch = 0.15;
  }

  @override
  Scene build(DemoContext context) {
    // #region panes
    final DeviceMesh quad = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 1.2, depth: 1.2).build(),
    );
    final List<({double x, double z, double yaw, Vector4 color})> panes =
        <({double x, double z, double yaw, Vector4 color})>[
          (x: -0.3, z: 0.6, yaw: 0.0, color: Vector4(0.9, 0.1, 0.1, 0.5)),
          (x: 0.0, z: 0.0, yaw: 0.0, color: Vector4(0.1, 0.9, 0.1, 0.45)),
          (x: 0.3, z: -0.6, yaw: 0.0, color: Vector4(0.1, 0.2, 0.9, 0.6)),
          // These two cross through each other: no order of the two is right
          // for every pixel.
          (x: 0.1, z: 0.3, yaw: 0.6, color: Vector4(0.9, 0.8, 0.1, 0.4)),
          (x: 0.1, z: 0.3, yaw: -0.6, color: Vector4(0.8, 0.1, 0.9, 0.35)),
        ];
    final Scene scene = Scene();
    for (final pane in panes) {
      scene.add(
        MeshNode(
            quad,
            RenderMaterial(
              lighting: LightingModel.unlit,
              baseColor: _fromSrgb(pane.color),
              alphaMode: MaterialAlphaMode.blend,
              doubleSided: true,
            ),
            name: 'pane',
          )
          ..setPosition(pane.x, 0.0, pane.z)
          ..setRotationYawPitchRoll(pane.yaw, math.pi / 2, 0.0),
      );
    }
    // #endregion panes

    // #region wall
    return scene..add(
      MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          RenderMaterial(
            lighting: LightingModel.unlit,
            baseColor: LinearColor.fromSrgb(0.45, 0.45, 0.45, 1.0),
            doubleSided: true,
          ),
          name: 'wall',
        )
        ..setPosition(0.0, 0.0, -1.6)
        ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
    // #endregion wall
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    transparency: _modes[mode],
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Transparency',
      options: const <String>['Sorted', 'Weighted blended'],
      index: () => mode,
      onChanged: (int i) => mode = i,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final FramePass? pass = frame.passes
        .where((FramePass p) => p.name == 'scene')
        .firstOrNull;
    if (pass == null) throw StateError('the scene pass did not run');
    // Weighted blended adds one full-screen resolve to the scene pass, on top
    // of a draw for every mesh.
    final int meshes = scene.meshes.length;
    final int expected = _modes[mode] == TransparencyMode.weightedBlended
        ? meshes + 1
        : meshes;
    if (pass.drawCalls < expected) {
      throw StateError(
        'the scene pass drew ${pass.drawCalls}, expected at least $expected',
      );
    }
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
