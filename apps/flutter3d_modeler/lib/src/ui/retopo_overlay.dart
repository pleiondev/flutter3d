/// `pro-rt-03`: what a retopology looks like while it is being drawn — the
/// source behind it, the new quads as ribbons, and the quad under the
/// pointer.
///
/// **The source is drawn faint and the new mesh is drawn on top of it.** A
/// retopology is made by looking at a shape and tracing over it; a viewport
/// that drew the two at the same weight would be one where the thing being
/// traced and the thing being drawn are indistinguishable, and one that hid
/// the source would leave nothing to trace.
///
/// **Ribbons rather than hairlines.** A quad grid drawn a pixel wide
/// disappears against a lit surface at any distance and aliases into a moiré
/// at a glancing angle; 1.6 points of width is what holds the shape of the
/// grid while still reading as a wireframe rather than as a solid.
///
/// **The active quad is filled, not outlined.** The four corners a person
/// has placed so far are the thing they are aiming with, and an outline of
/// them is another four lines among a grid of lines. A fill at 22% says
/// "this one" at a glance and still shows the surface through it.
library;

import 'package:flutter/material.dart';

/// The active quad's own colour — `pro-rt-03`'s own `#FF458E`.
const Color kActiveQuadColour = Color(0xFFFF458E);

/// How much of it is drawn — `pro-rt-03`'s own 22%.
const double kActiveQuadOpacity = 0.22;

/// How wide a retopology ribbon is drawn, in logical pixels —
/// `pro-rt-03`'s own 1.6.
const double kRetopoRibbonWidth = 1.6;

/// How much of the source shows through behind the retopology.
///
/// **Two values rather than one, because two things are being looked at.**
/// While the grid is being drawn the source is a guide and wants to be
/// faint; while it is being judged, the source is the answer and wants to be
/// readable. `pro-rt-03`'s own acceptance asks for the frame at both.
const double kSourceFaint = 0.25;

/// See [kSourceFaint].
const double kSourceClear = 0.6;

/// One quad of the retopology, in screen space.
typedef ScreenQuad = List<Offset>;

/// Draws the retopology grid and the quad under the pointer.
///
/// The source mesh itself is drawn by the viewport underneath, at
/// [sourceAlpha] — this paints only what is on top of it.
class RetopoOverlay extends CustomPainter {
  const RetopoOverlay({
    required this.quads,
    required this.sourceAlpha,
    this.active,
    this.ribbon = kRetopoRibbonWidth,
  });

  /// Every quad already placed, each four points in screen space.
  final List<ScreenQuad> quads;

  /// How much of the source shows through — [kSourceFaint] or
  /// [kSourceClear], read by the viewport rather than by this painter, and
  /// carried here so a repaint happens when it changes.
  final double sourceAlpha;

  /// The quad being placed, with however many corners are down so far.
  final ScreenQuad? active;

  final double ribbon;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ribbon
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85);
    for (final ScreenQuad quad in quads) {
      if (quad.length < 2) continue;
      canvas.drawPath(_pathOf(quad, closed: quad.length > 2), grid);
    }

    final ScreenQuad? open = active;
    if (open == null || open.isEmpty) return;
    if (open.length >= 3) {
      canvas.drawPath(
        _pathOf(open, closed: true),
        Paint()
          ..style = PaintingStyle.fill
          ..color = kActiveQuadColour.withValues(alpha: kActiveQuadOpacity),
      );
    }
    canvas.drawPath(
      _pathOf(open, closed: open.length > 3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ribbon
        ..strokeJoin = StrokeJoin.round
        ..color = kActiveQuadColour,
    );
    // The corners themselves, so a person placing the fourth can see the
    // three already down even where the ribbon runs along an edge of the
    // grid underneath.
    for (final Offset corner in open) {
      canvas.drawCircle(corner, ribbon * 2, Paint()..color = kActiveQuadColour);
    }
  }

  static Path _pathOf(ScreenQuad quad, {required bool closed}) {
    final Path path = Path()..moveTo(quad.first.dx, quad.first.dy);
    for (var i = 1; i < quad.length; i++) {
      path.lineTo(quad[i].dx, quad[i].dy);
    }
    if (closed) path.close();
    return path;
  }

  @override
  bool shouldRepaint(RetopoOverlay old) =>
      old.quads != quads ||
      old.active != active ||
      old.sourceAlpha != sourceAlpha ||
      old.ribbon != ribbon;
}
