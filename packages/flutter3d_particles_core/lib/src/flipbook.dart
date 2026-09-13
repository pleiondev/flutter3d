/// A sprite sheet, and which cell of it a particle is showing.
///
/// The last thing a billboard needs a texture for. A single sprite makes a
/// particle a *shape*; a sheet makes it a small animation, which is how a puff
/// of smoke curls or a spark burns out rather than merely fading.
///
/// **Entirely in the vertex data, and therefore free.** Billboarding already
/// happens on the CPU here, so a cell is a rectangle the corner coordinates are
/// scaled into before they are written — no shader knows this exists, no
/// backend was changed for it, and a particle system with no flipbook writes
/// the same bytes it always did.
library;

import 'particle.dart';

/// One cell of the sheet, in texture space.
final class FlipbookCell {
  const FlipbookCell(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// A grid of frames, played across a particle's life.
final class Flipbook {
  Flipbook({
    required this.columns,
    required this.rows,
    this.frames,
    this.loops = 1,
  }) : assert(columns > 0 && rows > 0, 'a sheet has at least one cell'),
       assert(loops > 0, 'a flipbook plays at least once');

  final int columns;
  final int rows;

  /// How many cells are actually used, or null for all of them.
  ///
  /// A sheet is a grid and an animation is a count, and the two differ whenever
  /// the last row is not full. Playing the empty cells is not a subtle failure
  /// — the particle blinks out and comes back — but it is one a caller cannot
  /// avoid without saying so here.
  final int? frames;

  /// How many times the sequence plays over the particle's life.
  ///
  /// One is the usual answer: a flipbook is an animation with a beginning and
  /// an end, and a spark that restarts halfway through dying reads as two
  /// sparks. More than one suits a texture whose frames are a cycle rather than
  /// a story — a flame's flicker, a wisp turning.
  final int loops;

  int get frameCount {
    final all = columns * rows;
    final wanted = frames;
    if (wanted == null || wanted > all) return all;
    return wanted;
  }

  /// The cell [particle] is showing, from how far through its life it is.
  ///
  /// Driven by life rather than by a clock so that a slow particle and a fast
  /// one both play the whole animation exactly once. A frames-per-second
  /// flipbook would finish early on a long-lived particle and be cut off on a
  /// short one, and the particle's lifetime is already the thing every other
  /// property here is expressed against.
  FlipbookCell cellFor(Particle particle) {
    final count = frameCount;
    var frame = (particle.life * count * loops).floor();
    // The last frame is held rather than wrapped to the first. At exactly one
    // the floor lands one past the end, and a particle's final instant showing
    // frame zero again is a visible blink at the moment it disappears.
    frame = loops == 1 ? (frame >= count ? count - 1 : frame) : frame % count;
    if (frame < 0) frame = 0;

    final column = frame % columns;
    final row = frame ~/ columns;
    final width = 1.0 / columns;
    final height = 1.0 / rows;
    return FlipbookCell(column * width, row * height, width, height);
  }
}
