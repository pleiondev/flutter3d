/// The texture-painting brush's own settings and the canvas the panel draws
/// — `pro-pt-05`'s state, lifted out of `_ModelerScreenState` by `ui-37d`'s
/// own tail. See [SculptBrush], which is the same move for the same reason.
library;

import 'dart:ui' as ui;

import 'ui/paint_panel.dart' show kPaintCursorDiameter;

final class PaintBrush {
  /// Which layer a stroke lands on.
  int layer = 0;

  /// Linear RGBA, the range `PaintStroke.colour` reads.
  List<double> colour = const <double>[0.85, 0.2, 0.2, 1];

  /// The cursor's width in logical pixels — a diameter, and named one here
  /// for the reason [SculptBrush.diameter] gives: the screen's field was
  /// `_paintRadius`, held a diameter, and every reader but the panel divided
  /// it by two.
  double diameter = kPaintCursorDiameter;

  /// What a stroke's own `radiusPixels` reads.
  double get radius => diameter / 2;

  /// How hard the brush paints at full pressure, 0 to 1.
  double strength = 1;

  /// The mask a stroke is confined to, or null for none.
  String? mask;

  /// The flattened canvas the panel shows — the layers composited, redrawn
  /// when one of them changes.
  ///
  /// **A `ui.Image` the screen owns and the panel borrows.** It is not brush
  /// state and it is here anyway, because it is the other half of what the
  /// paint panel is handed and splitting the two would mean the screen
  /// holding one field to avoid holding two.
  ui.Image? canvas;
}
