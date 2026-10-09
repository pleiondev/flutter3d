/// A generated cloud of Gaussians cut into a tree of levels of detail and
/// drawn under a splat budget.
///
/// Quoted by `splat_budget.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class SplatBudgetDemo extends ShowcaseDemo {
  /// Splats around the ring, and around the tube at each step of the ring.
  static const int _around = 60;
  static const int _tube = 40;

  double budget = 300.0;

  late final SplatOctree _tree;
  late final SplatLod _lod;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.6
      ..yaw = 0.3;
  }

  @override
  Scene build(DemoContext context) {
    // #region cloud
    const int count = _around * _tube;
    final Float32List centers = Float32List(count * 3);
    final Float32List colors = Float32List(count * 4);
    final Float32List scales = Float32List(count * 3);
    final Float32List rotations = Float32List(count * 4);
    for (var i = 0; i < count; i++) {
      final double a = (i ~/ _tube) / _around * 2.0 * math.pi;
      final double b = (i % _tube) / _tube * 2.0 * math.pi;
      final double ring = 1.4 + 0.45 * math.cos(b);
      centers.setAll(i * 3, <double>[
        ring * math.cos(a),
        0.45 * math.sin(b),
        ring * math.sin(a),
      ]);
      colors.setAll(i * 4, <double>[
        0.5 + 0.5 * math.cos(a),
        0.5 + 0.5 * math.sin(b),
        0.5 - 0.5 * math.cos(a),
        0.9,
      ]);
      scales.setAll(i * 3, <double>[0.05, 0.05, 0.05]);
      rotations[i * 4 + 3] = 1.0;
    }
    final SplatCloud cloud = SplatCloud(
      centers: centers,
      colors: colors,
      scales: scales,
      rotations: rotations,
    );
    // #endregion cloud

    // #region tree
    _tree = buildSplatOctree(cloud, leafCapacity: 64, grid: 4);
    // #endregion tree

    // #region contributor
    _lod = SplatLod(_tree, budget: budget.round());
    context.renderer.renderSteps.addContributor(SplatContributor.lod(_lod));
    // #endregion contributor

    return Scene()
      ..ambientColor = LinearColor(0.4, 0.46, 0.6)
      ..ambientIntensity = 0.24 * Photometric.legacyUnit;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region budget
    _lod.budget = budget.round();
    // #endregion budget
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    // #region slider
    SliderControl(
      'Splat budget',
      min: _tree.nodes.first.splatCount.toDouble(),
      max: _tree.leafSplatCount.toDouble(),
      value: () => budget,
      onChanged: (double v) => budget = v,
      format: (double v) => '${v.round()} of ${_tree.leafSplatCount}',
    ),
    // #endregion slider
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_tree.leafSplatCount != _around * _tube ||
        _lod.cut.isEmpty ||
        _lod.cutSplatCount > _lod.budget ||
        _lod.cutSplatCount >= _tree.leafSplatCount ||
        frame.drawCalls < 1) {
      throw StateError('the tree was not drawn as a cut under its budget');
    }
    // #endregion check
  }
}
