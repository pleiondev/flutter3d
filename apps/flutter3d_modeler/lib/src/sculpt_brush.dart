/// The sculpting brush's own four settings, in one object — `pro-sc-08`'s
/// state, lifted out of `_ModelerScreenState` by `ui-37d`'s own tail.
///
/// **A holder because a `part of` file cannot declare a field.** `ui-37d` put
/// every method that reads `context`, `mounted`, `setState` or `_device` into
/// `screen/*.dart` as an `extension … on _ModelerScreenState`, and stopped
/// there: Dart gives an extension no way to add a field, so the sessions,
/// notifiers and panel settings the screen owns all stayed in the class body
/// and `main.dart` stayed at 868 lines against a target of 400. The row says
/// what closing that number costs — "folding groups of those fields into
/// holder objects … each is a refactor of its own with its own goldens to
/// hold" — and names the pro-mode sessions as the first group. This is that
/// group's sculpting half.
///
/// **Mutable, and not a `ChangeNotifier`.** The screen already calls
/// `setState` when a slider moves, which is what repaints the panel; adding a
/// notifier would be a second way to say the same thing and two places for a
/// repaint to come from. Nothing outside the screen watches these.
///
/// None of the four is on `ModelHistory`, which is the same reason they were
/// plain fields before this: undo has nowhere to put a brush size back to.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart' show BrushFalloff;

import 'ui/sculpt_panel.dart' show kSculptCursorDiameter;

final class SculptBrush {
  /// The cursor's width in logical pixels — `view-21`'s own ⌀140 is where it
  /// starts.
  ///
  /// **A diameter, and now named one.** The screen's field was
  /// `_sculptRadius` and held a diameter: two of its three readers divided by
  /// two and the third handed it to `SculptPanel.radius`, whose own doc
  /// comment says "the diameter of the cursor". So the name was wrong in two
  /// places and the arithmetic was right in all three; renaming it here costs
  /// nothing and is why [radius] exists below rather than a `/ 2` at every
  /// call site.
  double diameter = kSculptCursorDiameter;

  /// What a stroke's own `radiusPixels` reads.
  double get radius => diameter / 2;

  /// How hard the brush pushes at full pressure, 0 to 1.
  double strength = 0.5;

  /// How its influence tapers from the centre.
  BrushFalloff falloff = BrushFalloff.smooth;

  /// Whether a stroke is mirrored across `x = 0`.
  bool symmetryX = false;
}
