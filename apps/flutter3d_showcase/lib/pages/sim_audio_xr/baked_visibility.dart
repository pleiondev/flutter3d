/// Which parts of a level can be seen from where, decided before the game
/// runs, and applied every frame by hiding the batches a camera cannot see.
///
/// Quoted by `baked_visibility.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class BakedVisibilityDemo extends ShowcaseDemo {
  late final String _report;

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
        Brush(centre: Vector3(5, 1, 2), size: Vector3(0.4, 8, 4)),
      ],
    );
    // #endregion level

    // #region bake
    final visibility = LevelVisibility.bake(level, cellSize: 2.0);
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

    return Scene()
      ..add(nearMarker)
      ..add(farMarker)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

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
