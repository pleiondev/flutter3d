/// The circuit, flattened, with a dot for every car — split out of `hud.dart`
/// because it is the one piece of the HUD that draws rather than lays out
/// text, and a [CustomPainter] beside four [StatelessWidget]s was the odd one
/// out in that file.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import 'race_readout.dart';

class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.readout});

  final RaceReadout readout;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        height: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: _MapPainter(
            outline: readout.outline,
            cars: readout.carsOnMap,
          ),
        ),
      );
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.outline, required this.cars});

  final List<Vector2> outline;
  final List<Vector2> cars;

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.length < 2) return;

    // Fitted to the box rather than drawn at a fixed scale: a circuit is
    // whatever size it is, and a map that assumed one would put half of every
    // other track outside the corner it is drawn in.
    var minX = outline.first.x;
    var maxX = minX;
    var minY = outline.first.y;
    var maxY = minY;
    for (final point in outline) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    final span = math.max(maxX - minX, maxY - minY);
    if (span <= 0) return;
    final scale = math.min(size.width, size.height) / span;

    Offset place(Vector2 point) => Offset(
          (point.x - (minX + maxX) / 2) * scale + size.width / 2,
          (point.y - (minY + maxY) / 2) * scale + size.height / 2,
        );

    final path = Path()..moveTo(place(outline.first).dx, place(outline.first).dy);
    for (final point in outline.skip(1)) {
      final at = place(point);
      path.lineTo(at.dx, at.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF7E8794),
    );

    for (var i = 0; i < cars.length; i++) {
      canvas.drawCircle(
        place(cars[i]),
        i == 0 ? 4.5 : 3.0,
        Paint()..color = i == 0 ? Colors.white : const Color(0xFFE0553F),
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
