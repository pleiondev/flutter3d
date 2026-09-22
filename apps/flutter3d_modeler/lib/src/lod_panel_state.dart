/// What screen 17 remembers between builds — `pro-lod-04`'s own wiring half,
/// the same move `UvPanelState` and `pro_panel_state.dart` make and for the
/// same reason: an `extension` on the screen's state cannot declare a field.
///
/// **Whether the screen is up is here and not on `ModelerState`.** It is a
/// view of Object mode rather than a mode of its own — the hand-over reaches
/// it from an object's inspector and leaves it back to the same — so there
/// is nothing for a mode switch, an agent's `ui.setMode` or an undo to keep
/// in step with. The levels themselves are on the document, where undo does
/// reach them.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// `pro-lod-04`: whether the three thirds are on screen, and the simplified
/// meshes they are drawn from.
final class LodPanelState {
  /// Whether screen 17 has taken the viewport's place.
  bool open = false;

  /// One for the life of the screen: it keys on `ModelObject.version`, so a
  /// ratio dragged or a base mesh edited regenerates exactly the levels that
  /// went stale and no others. A cache per build would simplify a mesh three
  /// times on every tick.
  final LodMeshCache cache = LodMeshCache();
}

/// What a new level starts as, given the ones there are — half as many
/// triangles as the coarsest so far, taking over at half its screen size.
///
/// **Each level halves the one before it, because that is what a LOD chain
/// is.** Half the triangles at half the size on screen keeps the triangles
/// per pixel roughly level down the whole chain, which is the one property
/// that makes a switch between two levels hard to see. The first level
/// starts from the full mesh at a quarter of the screen: an object bigger
/// than that is one a person is looking at.
///
/// Floored rather than allowed to reach nought — `AddLod` refuses a ratio or
/// a threshold of zero, and the sixth halving of a threshold is a level for
/// an object three pixels tall.
({double ratio, double maxScreenFraction}) nextLodAfter(List<LodSpec> levels) {
  if (levels.isEmpty) return (ratio: 0.5, maxScreenFraction: 0.25);
  final LodSpec coarsest = levels.reduce(
    (LodSpec a, LodSpec b) => a.ratio <= b.ratio ? a : b,
  );
  final LodSpec smallest = levels.reduce(
    (LodSpec a, LodSpec b) =>
        a.maxScreenFraction <= b.maxScreenFraction ? a : b,
  );
  return (
    ratio: (coarsest.ratio / 2).clamp(0.05, 1.0),
    maxScreenFraction: (smallest.maxScreenFraction / 2).clamp(0.01, 1.0),
  );
}
