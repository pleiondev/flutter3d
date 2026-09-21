/// Which parts of a level can be seen from where, decided before the game
/// runs, and applied every frame by hiding the batches a camera cannot see.
///
/// Quoted by `baked_visibility.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class BakedVisibilityDemo extends ShowcaseDemo {
  late final String _report;

  double eyeX = 0.0;
  bool walking = true;

  late final VisibilityCuller _live;
  late final MeshNode _eye;
  double _clock = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 15.0
      ..pitch = 0.85
      ..yaw = 0.0;
    context.orbit.target.setValues(5.0, 0.0, 2.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region level
    // A floor the whole way along, and one solid wall crossing it a third of
    // the way down: nothing on the near side of the wall can be seen from
    // the far side.
    final level = Level(
      name: 'corridor',
      brushes: <Brush>[
        Brush(centre: Vector3(5, -2, 2), size: Vector3(14, 4, 4)),
        Brush(centre: Vector3(5, 1, 2), size: Vector3(1.0, 8, 4)),
      ],
    );
    // #endregion level

    // #region bake
    final visibility = LevelVisibility.bake(level, cellSize: 1.0);
    // #endregion bake

    final material = f3d.Material(
      name: 'room',
      baseColor: Vector4(0.6, 0.6, 0.8, 1.0),
    );
    final nearMarker = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      material,
      name: 'near',
    )..setPositionFrom(Vector3(0, 0.5, 2));
    final farMarker = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      material,
      name: 'far',
    )..setPositionFrom(Vector3(10, 0.5, 2));

    // #region cull
    final culler = VisibilityCuller(visibility, <VisibilityBatch>[
      (
        node: nearMarker,
        bounds: Aabb3.minMax(Vector3(-1, 0, 1), Vector3(1, 2, 3)),
      ),
      (
        node: farMarker,
        bounds: Aabb3.minMax(Vector3(9, 0, 1), Vector3(11, 2, 3)),
      ),
    ]);
    final hiddenFromNearSide = culler.apply(Vector3(0, 0.2, 2));
    // #endregion cull

    _report =
        'standing on the near side, $hiddenFromNearSide of 2 batches are '
        'hidden; near marker visible: ${nearMarker.visible}, far marker '
        'visible: ${farMarker.visible}';

    // #region live
    // The same culler, over four markers, asked again from wherever the eye
    // is each frame: a marker is on when the eye's own cell can see it.
    const List<double> stands = <double>[0.0, 1.5, 8.5, 10.0];
    final List<MeshNode> markers = <MeshNode>[
      for (final double x in stands)
        blockNode(
          context,
          'marker $x',
          Vector3(1.4, 1.4, 1.4),
          Vector4(0.85, 0.6, 0.35, 1.0),
          at: Vector3(x, 0.7, 2.0),
        ),
    ];
    _live = VisibilityCuller(visibility, <VisibilityBatch>[
      for (final MeshNode marker in markers)
        (
          node: marker,
          bounds: Aabb3.minMax(
            marker.readPosition() - Vector3.all(0.7),
            marker.readPosition() + Vector3.all(0.7),
          ),
        ),
    ]);
    // #endregion live
    _eye = ballNode(
      context,
      'eye',
      0.35,
      Vector4(0.45, 0.65, 0.95, 1.0),
      at: Vector3(0.0, 0.35, 2.0),
    );
    return sceneOf(<SceneNode>[
      blockNode(
        context,
        'floor',
        Vector3(14.0, 0.1, 4.0),
        Vector4(0.34, 0.38, 0.36, 1.0),
        at: Vector3(5.0, -0.05, 2.0),
      ),
      blockNode(
        context,
        'wall',
        Vector3(1.0, 3.0, 4.0),
        Vector4(0.55, 0.5, 0.5, 1.0),
        at: Vector3(5.0, 1.5, 2.0),
      ),
      _eye,
      ...markers,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (walking) eyeX = 5.0 + 5.8 * math.sin(_clock * 0.4);
    _eye.setPosition(eyeX, 0.35, 2.0);
    _live.apply(Vector3(eyeX, 0.2, 2.0));
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Eye at',
      min: -1.0,
      max: 10.9,
      value: () => eyeX,
      onChanged: (double v) {
        walking = false;
        eyeX = v;
      },
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
    ToggleControl(
      'Walk about',
      value: () => walking,
      onChanged: (bool v) => walking = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('a marker was not drawn');
    }
    if (!_report.contains('near marker visible: true')) {
      throw StateError('the side the eye stands on should stay visible');
    }
    if (!_report.contains('far marker visible: false')) {
      throw StateError(
        'the far side of a solid wall with no doorway should be hidden',
      );
    }
  }
}
