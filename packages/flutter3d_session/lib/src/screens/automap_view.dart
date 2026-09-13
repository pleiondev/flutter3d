import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// The automap, drawn: floor where the player has walked, walls where it
/// stopped, an arrow where they stand.
///
/// A `CustomPainter` over the level's cells, centred on the player and
/// turned so that up on the screen is the way they face — the map a player
/// reads mid-fight, not the one they study. A cell is a rectangle; a level of
/// forty metres in quarter-metre cells is twenty-five thousand of them, of
/// which the painter draws only the revealed ones and only those that fall
/// on the screen, which is a few hundred. Nothing is cached, because a map
/// that is open is a map that is changing.
///
/// What it does not draw: monsters, items, the exit. A map that shows the
/// monsters is a different game, and the decision belongs to the game.
class AutomapView extends StatelessWidget {
  const AutomapView({
    super.key,
    required this.automap,
    required this.position,
    required this.yaw,
    this.metresAcross = 40.0,
    this.floor = const Color(0xFF9A9284),
    this.wall = const Color(0xFF2B2622),
    this.player = const Color(0xFFF2D133),
    this.backdrop = const Color(0xA0000000),
  });

  final Automap automap;

  /// Where the player is, in world space; the map is centred here.
  final Vector3 position;

  /// Which way the player faces, radians about Y; the map turns so this is
  /// up on the screen.
  final double yaw;

  /// How many metres of level the shorter side of the view shows.
  final double metresAcross;

  final Color floor;
  final Color wall;
  final Color player;
  final Color backdrop;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: AutomapPainter(
        automap: automap,
        position: position,
        yaw: yaw,
        metresAcross: metresAcross,
        floor: floor,
        wall: wall,
        player: player,
        backdrop: backdrop,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

/// The painting, public so a test can ask it what it would draw.
class AutomapPainter extends CustomPainter {
  const AutomapPainter({
    required this.automap,
    required this.position,
    required this.yaw,
    required this.metresAcross,
    required this.floor,
    required this.wall,
    required this.player,
    required this.backdrop,
  });

  final Automap automap;
  final Vector3 position;
  final double yaw;
  final double metresAcross;
  final Color floor;
  final Color wall;
  final Color player;
  final Color backdrop;

  /// Pixels per metre for a view of [size].
  double scaleFor(Size size) => size.shortestSide / metresAcross;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backdrop);
    final scale = scaleFor(size);
    final centre = Offset(size.width / 2, size.height / 2);
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      // `yaw` is the angle the player turned about Y; the world's -Z is
      // forward at yaw zero, and up on the screen is -y, so the map turns by
      // the yaw to bring the facing to the top.
      ..rotate(yaw)
      ..scale(scale, scale)
      ..translate(-position.x, -position.z);

    final grid = automap.grid;
    final cell = grid.cellSize;
    // Only the cells that can land on the screen: a square of half the
    // view's diagonal around the player, in cells.
    final reach = size.longestSide / scale / 2 * math.sqrt2;
    final minX = math.max(
      0,
      ((position.x - reach - grid.originX) / cell).floor(),
    );
    final maxX = math.min(
      grid.columns - 1,
      ((position.x + reach - grid.originX) / cell).ceil(),
    );
    final minZ = math.max(
      0,
      ((position.z - reach - grid.originZ) / cell).floor(),
    );
    final maxZ = math.min(
      grid.rows - 1,
      ((position.z + reach - grid.originZ) / cell).ceil(),
    );
    final floorPaint = Paint()..color = floor;
    final wallPaint = Paint()..color = wall;
    for (var z = minZ; z <= maxZ; z++) {
      for (var x = minX; x <= maxX; x++) {
        final index = grid.cellIndex(x, z);
        if (!automap.isRevealed(index)) continue;
        final left = grid.originX + x * cell;
        final top = grid.originZ + z * cell;
        canvas.drawRect(
          Rect.fromLTWH(left, top, cell, cell),
          automap.isFloor(index) ? floorPaint : wallPaint,
        );
      }
    }
    canvas.restore();

    // The player, always up, always in the middle: a triangle a metre long.
    final arrow = Path()
      ..moveTo(centre.dx, centre.dy - 0.6 * scale)
      ..lineTo(centre.dx + 0.35 * scale, centre.dy + 0.4 * scale)
      ..lineTo(centre.dx - 0.35 * scale, centre.dy + 0.4 * scale)
      ..close();
    canvas.drawPath(arrow, Paint()..color = player);
  }

  @override
  bool shouldRepaint(AutomapPainter old) => true;
}
