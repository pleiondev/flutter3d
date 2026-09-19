/// The level as the player has seen it, from above: floor where they walked,
/// walls where the floor stopped, nothing where they have not been.
///
/// Quoted by `automap.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class AutomapDemo extends ShowcaseDemo {
  late final NavGrid _grid;
  late final Automap _map;

  @override
  Scene build(DemoContext context) {
    // #region grid
    _grid = NavGrid.bake(<Brush>[
      Brush(centre: Vector3(5, 0, 5), size: Vector3(10, 1, 10)),
    ], cellSize: 0.5);
    _map = Automap(_grid, revealRadius: 3.0);
    // #endregion grid

    final material = Material(
      name: 'walker',
      baseColor: Vector4(0.6, 0.9, 0.7, 1.0),
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

  // #region reveal
  void _walk() {
    _map.reveal(Vector3(1.0, 0.0, 1.0));
    _map.reveal(Vector3(3.0, 0.0, 1.0));
  }
  // #endregion reveal

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    _walk();
    return ColoredBox(
      color: const Color(0xFF14161A),
      child: Center(
        child: CustomPaint(
          size: const Size(320, 200),
          painter: _MapPainter(_grid, _map),
        ),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the walker marker was not drawn');
    }
    _walk();
    // #region check
    final nearWhereWalked = _map.isFloor(_grid.cellAtPoint(2.0, 1.0));
    final farAcrossTheFloor = _map.isRevealed(_grid.cellAtPoint(9.0, 9.0));
    // #endregion check
    if (!nearWhereWalked) {
      throw StateError(
        'a cell the walk passed near should be revealed as floor',
      );
    }
    if (farAcrossTheFloor) {
      throw StateError(
        'the automap should not reveal floor nobody walked near',
      );
    }
  }
}

/// Draws revealed floor light, revealed walls dark, and everything else
/// blank.
final class _MapPainter extends CustomPainter {
  const _MapPainter(this.grid, this.map);

  final NavGrid grid;
  final Automap map;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / grid.columns;
    final cellH = size.height / grid.rows;
    final paint = Paint();
    for (var index = 0; index < grid.cellCount; index++) {
      if (!map.isRevealed(index)) continue;
      final cx = grid.cellX(index);
      final cz = grid.cellZ(index);
      paint.color = map.isFloor(index)
          ? const Color(0xFFB6E3B0)
          : const Color(0xFF3A2A2A);
      canvas.drawRect(
        Rect.fromLTWH(cx * cellW, cz * cellH, cellW, cellH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}
