/// Where an agent can stand, baked once from the level's architecture into a
/// lattice a step can query in one array lookup.
///
/// Quoted by `nav_grid.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class NavGridDemo extends ShowcaseDemo {
  late final NavGrid _grid;

  @override
  Scene build(DemoContext context) {
    _grid = _bake();
    final material = Material(
      name: 'floor',
      baseColor: Vector4(0.5, 0.55, 0.6, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region brushes
  /// Two floor slabs joined by a narrow bridge, so most of the gap between
  /// them is not walkable but the bridge is.
  static List<Brush> _brushes() => <Brush>[
    Brush(centre: Vector3(2, 0, 2), size: Vector3(4, 1, 4)),
    Brush(centre: Vector3(5.5, 0, 3.5), size: Vector3(3, 1, 1)),
    Brush(centre: Vector3(9, 0, 2), size: Vector3(4, 1, 4)),
  ];
  // #endregion brushes

  // #region bake
  static NavGrid _bake() => NavGrid.bake(_brushes(), cellSize: 0.5);
  // #endregion bake

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      ColoredBox(
        color: const Color(0xFF14161A),
        child: Center(
          child: CustomPaint(
            size: const Size(320, 200),
            painter: _GridPainter(_grid),
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the floor marker was not drawn');
    }
    // #region query
    final onFirstSlab = _grid.isWalkable(_grid.cellAtPoint(2.0, 2.0));
    final inTheGap = _grid.isWalkable(_grid.cellAtPoint(4.5, 0.5));
    final onBridge = _grid.isWalkable(_grid.cellAtPoint(5.0, 3.5));
    // #endregion query
    if (!onFirstSlab || inTheGap || !onBridge) {
      throw StateError(
        'the slabs and the bridge should be walkable and the open gap '
        'should not',
      );
    }
  }
}

/// Draws the grid from above: light for a walkable cell, dark for not.
final class _GridPainter extends CustomPainter {
  const _GridPainter(this.grid);

  final NavGrid grid;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / grid.columns;
    final cellH = size.height / grid.rows;
    final paint = Paint();
    for (var index = 0; index < grid.cellCount; index++) {
      final cx = grid.cellX(index);
      final cz = grid.cellZ(index);
      paint.color = grid.isWalkable(index)
          ? const Color(0xFF7FB0FF)
          : const Color(0xFF2A2C33);
      canvas.drawRect(
        Rect.fromLTWH(cx * cellW, cz * cellH, cellW, cellH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
