/// The browser's [BackgroundShapeSolver]: it has no isolate to send work
/// to, so the shapes are worked out when they are asked for, as
/// `LiquidShapeSolver.immediate` works them.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';

/// A liquid's menisci and its surfaces' modes worked out off the frame,
/// where the platform has somewhere to work them: in the browser there is
/// nowhere, and every answer is given when it is asked for.
final class BackgroundShapeSolver extends LiquidShapeSolver {
  /// A solver; in the browser, one that works at once.
  BackgroundShapeSolver();

  /// Whether answers are worked out off the frame here: never in the
  /// browser.
  static bool get isAvailable => false;

  /// Nothing to let go in the browser.
  void dispose() {}
}
