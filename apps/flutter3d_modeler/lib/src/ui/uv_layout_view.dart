/// `pro-uv-07`'s own UV-layout painter: a checker backdrop standing in for a
/// texture, every island's own triangles over it tinted by how stretched its
/// UV mapping is, and a tap that names which triangle of which island it
/// landed on.
///
/// **400×400, the acceptance's own size**, painted into UV's own `[0, 1]`
/// square with V flipped: UV's own origin is the bottom-left corner of a
/// texture, a canvas's is the top-left, and drawing UV literally would show
/// every island upside down against a texture viewer's own right-side-up
/// checker.
///
/// **The checker mirrors `CheckerboardTexture`'s own two tones**
/// (`package:flutter3d`'s `procedural_texture.dart`) rather than reusing that
/// class outright: it encodes RGBA8 pixels for a `GraphicsDevice` to upload,
/// which is a texture and an async decode this painter — a plain `Canvas`
/// with no device anywhere near it — has no use for. Painting the same two
/// colours as rects keeps one visual language between the 3D preview's own
/// checker and this one without either owning the other.
library;

import 'package:flutter/material.dart';

import '../uv_unwrap_layout.dart';

/// A tap landed on triangle [triangleIndex] of the island at [islandId] in
/// the [UvLayoutView.islands] list it was given.
typedef UvTriangleTap = void Function(int islandId, int triangleIndex);

/// The 400×400 UV-space picture: a checker, every island tinted by stretch,
/// and a tap that reports which triangle it hit.
final class UvLayoutView extends StatelessWidget {
  const UvLayoutView({
    super.key,
    required this.islands,
    this.selectedIslandId,
    this.onTriangleTap,
    this.size = 400,
    this.checkerCells = 32,
    this.semanticLabel,
  });

  /// What to paint — [buildUvIslandData]'s own output, one entry per island.
  final List<UvIslandData> islands;

  /// Which island's own outline draws brighter, or null for none selected.
  final int? selectedIslandId;

  /// A tap landed inside a triangle. Null leaves the picture untappable —
  /// a caller with nothing to do about a selection need not pay for the
  /// [GestureDetector] either.
  final UvTriangleTap? onTriangleTap;

  /// Edge length in logical pixels — 400 is the acceptance's own number, and
  /// the most this takes: a parent with less room gets a smaller square
  /// rather than a clipped one, see [build].
  final double size;

  /// Checker cells per edge — 32 is the acceptance's own number.
  final int checkerCells;

  /// What a screen reader is told this picture is — the caller's own words,
  /// already translated, since this file is pumped by tests with no
  /// localizations above it. Null leaves the picture unannounced, which is
  /// what it was before `UvScreen` had a sentence to give it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      // **The side it is given, not the side it asked for.** A parent
      // narrower than [size] — `UvScreen`'s own column on anything short of a
      // wide desktop — hands down a tight width, and a `SizedBox` of 400
      // inside it is laid out at that width whatever it asked for. The
      // painter already drew to the box it got; the tap still divided by
      // [size], so a press landed on a different triangle from the one under
      // it. One number for both is what makes them the same picture.
      final double room = constraints.biggest.shortestSide;
      final double side = room.isFinite && room < size ? room : size;
      final picture = CustomPaint(
        size: Size.square(side),
        painter: _UvLayoutPainter(
          islands: islands,
          selectedIslandId: selectedIslandId,
          checkerCells: checkerCells,
        ),
      );
      final tap = onTriangleTap;
      final Widget pressable = tap == null
          ? picture
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) =>
                  _handleTap(details.localPosition, side, tap),
              child: picture,
            );
      return SizedBox.square(
        dimension: side,
        child: semanticLabel == null
            ? pressable
            : Semantics(label: semanticLabel, image: true, child: pressable),
      );
    },
  );

  void _handleTap(Offset local, double side, UvTriangleTap onTap) {
    final uv = _toUv(local, side);
    for (final island in islands) {
      for (var i = 0; i < island.triangles.length; i++) {
        if (_containsPoint(island.triangles[i], uv)) {
          onTap(island.id, i);
          return;
        }
      }
    }
  }
}

/// [local] — a canvas position — back into the UV space [_toCanvas] paints
/// from: the inverse of the same flip.
Offset _toUv(Offset local, double size) =>
    Offset(local.dx / size, 1 - local.dy / size);

/// A UV-space point onto the canvas [size] squares its own `[0, 1]` onto.
Offset _toCanvas(Offset uv, double size) =>
    Offset(uv.dx * size, (1 - uv.dy) * size);

/// The standard sign-of-area test, done for all three edges of [t]: [p] is
/// inside exactly when it is on the same side of every one of them.
bool _containsPoint(UvTriangle t, Offset p) {
  double sign(Offset a, Offset b, Offset c) =>
      (a.dx - c.dx) * (b.dy - c.dy) - (b.dx - c.dx) * (a.dy - c.dy);
  final d1 = sign(p, t.a, t.b);
  final d2 = sign(p, t.b, t.c);
  final d3 = sign(p, t.c, t.a);
  final hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

final class _UvLayoutPainter extends CustomPainter {
  _UvLayoutPainter({
    required this.islands,
    required this.selectedIslandId,
    required this.checkerCells,
  });

  final List<UvIslandData> islands;
  final int? selectedIslandId;
  final int checkerCells;

  /// `CheckerboardTexture`'s own light and dark tones, this painter's own
  /// class doc explains why they are copied rather than shared.
  static const Color _light = Color(0xFFE8E2D4);
  static const Color _dark = Color(0xFF6A6E7A);

  static const Color _outline = Color(0x66000000);
  static const Color _selectedOutline = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    _paintChecker(canvas, size);
    _paintIslands(canvas, size);
  }

  void _paintChecker(Canvas canvas, Size size) {
    final cell = size.width / checkerCells;
    final paint = Paint();
    for (var row = 0; row < checkerCells; row++) {
      for (var col = 0; col < checkerCells; col++) {
        paint.color = (row + col).isEven ? _light : _dark;
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell, cell),
          paint,
        );
      }
    }
  }

  void _paintIslands(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _outline;
    final selectedOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _selectedOutline;

    for (final island in islands) {
      if (island.triangles.isEmpty) continue;
      fill.color = island.color;
      final path = Path();
      for (final triangle in island.triangles) {
        final a = _toCanvas(triangle.a, size.width);
        final b = _toCanvas(triangle.b, size.width);
        final c = _toCanvas(triangle.c, size.width);
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close();
      }
      canvas.drawPath(path, fill);
      canvas.drawPath(
        path,
        island.id == selectedIslandId ? selectedOutline : outline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UvLayoutPainter oldDelegate) =>
      !identical(oldDelegate.islands, islands) ||
      oldDelegate.selectedIslandId != selectedIslandId ||
      oldDelegate.checkerCells != checkerCells;
}
