import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../theme/game_ui_theme.dart';

/// A course flattened to a line, with a dot for everything on it.
///
/// [outline] is the course in world XZ, closed back to its first point.
/// [markers] are the things on it in the same plane; the first is the
/// player's, drawn larger and in [playerColor], the rest in [othersColor];
/// either left out is the [GameUiTheme]'s `miniMapPlayer` or `miniMapOthers`,
/// and the line and the box are its `miniMapTrack` and `miniMapBackdrop`.
///
/// **Fitted to the box rather than drawn at a fixed scale:** a course is
/// whatever size it is, and a map that assumed one would put half of every
/// other course outside the corner it is drawn in.
class MiniMap extends StatelessWidget {
  const MiniMap({
    super.key,
    required this.outline,
    required this.markers,
    this.size = 150,
    this.playerColor,
    this.othersColor,
  });

  final List<Vector2> outline;
  final List<Vector2> markers;

  /// The box's side, in logical pixels.
  final double size;
  final Color? playerColor;
  final Color? othersColor;

  @override
  Widget build(BuildContext context) {
    final theme = GameUiTheme.of(context);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.miniMapBackdrop,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: MiniMapPainter(
          outline: outline,
          markers: markers,
          playerColor: playerColor ?? theme.miniMapPlayer,
          othersColor: othersColor ?? theme.miniMapOthers,
          trackColor: theme.miniMapTrack,
        ),
      ),
    );
  }
}

/// What [MiniMap] paints, public so a HUD that lays out its own frame can
/// paint the map into it, and so a test can read where a point lands.
class MiniMapPainter extends CustomPainter {
  const MiniMapPainter({
    required this.outline,
    required this.markers,
    this.playerColor = const Color(0xFFFFFFFF),
    this.othersColor = const Color(0xFFE0553F),
    this.trackColor = const Color(0xFF7E8794),
  });

  final List<Vector2> outline;
  final List<Vector2> markers;
  final Color playerColor;
  final Color othersColor;

  /// The course line's colour.
  final Color trackColor;

  /// Where [point] lands in a box of [size], or null when the outline has no
  /// extent to fit.
  Offset? place(Vector2 point, Size size) {
    if (outline.length < 2) return null;
    final minX = outline.map((Vector2 p) => p.x).reduce(math.min);
    final maxX = outline.map((Vector2 p) => p.x).reduce(math.max);
    final minY = outline.map((Vector2 p) => p.y).reduce(math.min);
    final maxY = outline.map((Vector2 p) => p.y).reduce(math.max);
    final span = math.max(maxX - minX, maxY - minY);
    if (span <= 0) return null;
    final scale = math.min(size.width, size.height) / span;
    return Offset(
      (point.x - (minX + maxX) / 2) * scale + size.width / 2,
      (point.y - (minY + maxY) / 2) * scale + size.height / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final start = place(outline.isEmpty ? Vector2.zero() : outline.first, size);
    if (start == null) return;

    final path = Path()..moveTo(start.dx, start.dy);
    for (final point in outline.skip(1)) {
      final at = place(point, size)!;
      path.lineTo(at.dx, at.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = trackColor,
    );

    for (var i = 0; i < markers.length; i++) {
      canvas.drawCircle(
        place(markers[i], size)!,
        i == 0 ? 4.5 : 3.0,
        Paint()..color = i == 0 ? playerColor : othersColor,
      );
    }
  }

  @override
  bool shouldRepaint(MiniMapPainter old) => true;
}
