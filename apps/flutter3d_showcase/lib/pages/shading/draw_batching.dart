/// `RenderSettings.batchIdenticalDraws`: a run of nodes sharing a mesh and a
/// material collapses into one instanced call.
///
/// Quoted by `draw_batching.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DrawBatchingDemo extends ShowcaseDemo {
  bool batch = true;

  static const int _rows = 3;
  static const int _columns = 4;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    // #region crates
    final DeviceMesh crateMesh = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
    );
    final Material crateMaterial = Material(
      name: 'crate',
      baseColor: Vector4(0.7, 0.55, 0.3, 1.0),
      roughness: 0.7,
    );
    final Scene scene = Scene();
    for (var row = 0; row < _rows; row++) {
      for (var column = 0; column < _columns; column++) {
        scene.add(
          MeshNode(crateMesh, crateMaterial, name: 'crate $row-$column')
            ..setPosition(
              (column - (_columns - 1) / 2) * 1.1,
              0.0,
              (row - (_rows - 1) / 2) * 1.1,
            ),
        );
      }
    }
    // #endregion crates

    return scene..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -0.8, -0.5)),
    );
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    batchIdenticalDraws: batch,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Batch identical draws',
      value: () => batch,
      onChanged: (bool v) => batch = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final int crates = _rows * _columns;
    if (scene.meshes.length != crates) {
      throw StateError('expected $crates crates, found ${scene.meshes.length}');
    }
    if (batch && frame.batchedDraws < RenderSettings.batchRunMinimum) {
      throw StateError(
        'batching was on but only ${frame.batchedDraws} draws were merged',
      );
    }
    if (!batch && frame.batchedDraws != 0) {
      throw StateError(
        'batching was off but ${frame.batchedDraws} draws merged',
      );
    }
    // #endregion check
  }
}
