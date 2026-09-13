import 'package:flutter/material.dart';

import 'playtest_report.dart';

/// Where every cell and every death point in a [PlaytestReport] lands on
/// screen, and the one thing both painting and hit-testing need to agree
/// on: the same transform, so a marker is exactly where a tap on it is
/// read back from.
///
/// **A class of its own, tested without a widget.** The transform is
/// arithmetic — world metres to pixels, with the level's own footprint
/// fit to whatever size the screen handed over — and arithmetic is cheaper
/// to prove directly than through a `WidgetTester`'s hit-testing, which
/// only tells you the two agree, not that either is right.
final class HeatmapLayout {
  HeatmapLayout({required this.report, required this.size, this.margin = 24.0}) {
    var minX = 0.0, maxX = 0.0, minZ = 0.0, maxZ = 0.0;
    var first = true;
    void widen(double x, double z) {
      if (first) {
        minX = maxX = x;
        minZ = maxZ = z;
        first = false;
        return;
      }
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }

    for (final cell in report.cells) {
      widen(cell.x * report.cellSize, cell.z * report.cellSize);
      widen((cell.x + 1) * report.cellSize, (cell.z + 1) * report.cellSize);
    }
    for (final death in report.deaths) {
      widen(death.x, death.z);
    }
    if (first) {
      minX = -1.0;
      maxX = 1.0;
      minZ = -1.0;
      maxZ = 1.0;
    }

    _minX = minX;
    _minZ = minZ;
    final spanX = (maxX - minX).clamp(1.0, double.infinity);
    final spanZ = (maxZ - minZ).clamp(1.0, double.infinity);
    final available = Size(
      (size.width - margin * 2).clamp(1.0, double.infinity),
      (size.height - margin * 2).clamp(1.0, double.infinity),
    );
    _scale = (available.width / spanX < available.height / spanZ)
        ? available.width / spanX
        : available.height / spanZ;
  }

  final PlaytestReport report;
  final Size size;
  final double margin;

  late final double _minX;
  late final double _minZ;
  late final double _scale;

  double get cellPixels => report.cellSize * _scale;

  /// World `(x, z)` to a point on screen.
  Offset toScreen(double x, double z) =>
      Offset(margin + (x - _minX) * _scale, margin + (z - _minZ) * _scale);

  Rect cellRect(HeatmapCell cell) {
    final topLeft = toScreen(cell.x * report.cellSize, cell.z * report.cellSize);
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, cellPixels, cellPixels);
  }

  /// The closest death marker to [point], within [radius] pixels — what a
  /// tap resolves to, or null when nothing was close enough to mean it.
  DeathPoint? hitTest(Offset point, {double radius = 14.0}) {
    DeathPoint? closest;
    var closestDistance = radius;
    for (final death in report.deaths) {
      final at = toScreen(death.x, death.z);
      final distance = (at - point).distance;
      if (distance <= closestDistance) {
        closest = death;
        closestDistance = distance;
      }
    }
    return closest;
  }
}

/// `ai-02`: the heatmap and the death points from an `ai-01` playtest,
/// drawn over the level's own footprint — a flat top-down read of where a
/// random policy went and where it stopped going, since the editor's own
/// viewport has no simulation behind it to walk through the room itself.
///
/// Tapping a death marker calls [onDeathTap] with which run it was and
/// which step it happened on — enough to say where to look; actually
/// scrubbing to that step needs a running instance of whatever genre the
/// level belongs to, which the editor deliberately does not carry (see
/// `rp-02`'s own note on why "live play in the editor" was not the
/// direction taken).
final class PlaytestHeatmapView extends StatelessWidget {
  const PlaytestHeatmapView({
    super.key,
    required this.report,
    this.onDeathTap,
  });

  final PlaytestReport report;
  final void Function(DeathPoint death)? onDeathTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = HeatmapLayout(report: report, size: size);
        return GestureDetector(
          onTapUp: (details) {
            final death = layout.hitTest(details.localPosition);
            if (death != null) onDeathTap?.call(death);
          },
          child: CustomPaint(
            size: size,
            painter: _HeatmapPainter(layout),
          ),
        );
      },
    );
  }
}

final class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter(this.layout);

  final HeatmapLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF14161A),
    );

    final maxSamples = layout.report.maxSamples;
    for (final cell in layout.report.cells) {
      final density = maxSamples == 0 ? 0.0 : cell.samples / maxSamples;
      canvas.drawRect(
        layout.cellRect(cell),
        Paint()..color = Color.lerp(
          const Color(0x00FFB74D),
          const Color(0xFFFFB74D),
          density.clamp(0.0, 1.0),
        )!,
      );
    }

    for (final death in layout.report.deaths) {
      final at = layout.toScreen(death.x, death.z);
      canvas.drawCircle(at, 6.0, Paint()..color = const Color(0xFFEF5350));
      canvas.drawCircle(
        at,
        6.0,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.layout.report != layout.report;
}
