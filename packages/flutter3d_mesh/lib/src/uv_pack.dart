/// Laying rectangles into a shared UV square without overlapping — shelves,
/// not a solver.
///
/// **`pro-uv-05`, and the number `pro-uv-06`'s own unwrap command will read
/// off it.** Every island `projectUv` or `pro-uv-02`'s still-unbuilt `lscm`
/// produces is its own little rectangle of UV space; a texture needs them
/// laid out in one square with none touching. Shelf packing — sort by
/// height, walk rows, start a new row when one is full — is not optimal,
/// but it is simple, fast, and the standard first answer for exactly this
/// problem.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Where one island landed, and whether packing turned it a quarter turn to
/// get there.
final class PackedIsland {
  const PackedIsland({required this.offset, required this.rotated});

  /// The island's own bottom-left corner in the shared square, already at
  /// [PackResult.scale] — multiply the island's original width and height by
  /// that same scale to get its placed size.
  final Vector2 offset;

  /// True when the island was turned 90° to pack better. Only possible when
  /// [packIslands] was called with `allowRotate90: true`; a caller reading
  /// UVs back onto the mesh has to apply the same turn.
  final bool rotated;
}

/// The whole layout: where every island landed, and how much of the square
/// they actually cover.
final class PackResult {
  const PackResult({
    required this.islands,
    required this.scale,
    required this.fillRatio,
  });

  /// One entry per island, in [packIslands]'s own input order.
  final List<PackedIsland> islands;

  /// What every island's original width and height was multiplied by to
  /// reach the placements in [islands].
  final double scale;

  /// Total island area (before scaling) divided by the packed square's own
  /// area (also before scaling) — a ratio, so [scale] cancels out of it.
  final double fillRatio;
}

/// One shelf-packed layout at a fixed container [width]: where everything
/// landed (in [packIslands]'s own input order) and the total height used.
///
/// A single function computing both, so the binary search below and the
/// final answer can never disagree about what one width produces — the risk
/// two separate walks of the same shelves would otherwise carry.
({List<PackedIsland> islands, double height}) _layout(
  List<Vector2> sizes,
  double margin,
  double width,
  bool allowRotate90,
) {
  final oriented = List<Vector2>.generate(
    sizes.length,
    (int i) => _orient(sizes[i], width, allowRotate90),
  );

  // Next-Fit Decreasing Height: the tallest islands set each shelf's height
  // first, so a short one filling a later gap never forces a row taller
  // than it needed to be.
  final order = List<int>.generate(sizes.length, (int i) => i)
    ..sort((a, b) => oriented[b].y.compareTo(oriented[a].y));

  final islands = List<PackedIsland?>.filled(sizes.length, null);
  var cursorX = 0.0;
  var shelfY = 0.0;
  var shelfHeight = 0.0;
  var startedShelf = false;

  for (final i in order) {
    final size = oriented[i];
    if (startedShelf && cursorX + size.x > width) {
      shelfY += shelfHeight + margin;
      cursorX = 0.0;
      shelfHeight = 0.0;
      startedShelf = false;
    }
    islands[i] = PackedIsland(
      offset: Vector2(cursorX, shelfY),
      rotated: size.x != sizes[i].x || size.y != sizes[i].y,
    );
    cursorX += size.x + margin;
    shelfHeight = math.max(shelfHeight, size.y);
    startedShelf = true;
  }

  return (
    islands: <PackedIsland>[for (final it in islands) it!],
    height: shelfY + shelfHeight,
  );
}

/// [size], turned on its side when [allowRotate90] and doing so is the only
/// way it fits within [containerWidth] at all.
Vector2 _orient(Vector2 size, double containerWidth, bool allowRotate90) {
  if (!allowRotate90) return size;
  final fits = size.x <= containerWidth;
  final turnedFits = size.y <= containerWidth;
  if (!fits && turnedFits) return Vector2(size.y, size.x);
  return size;
}

/// Packs [sizes] — each island's own width and height before packing — into
/// one shared square, with at least [margin] of empty space between any two
/// islands and around the square's own edge.
///
/// [allowRotate90] lets an island that is taller than it is wide pack lying
/// down instead, when doing so is the only way it fits a row it would
/// otherwise overhang.
///
/// Returns null for an empty [sizes], a negative [margin], or a size that is
/// not positive in both dimensions — the same "cost nothing rather than
/// something wrong" refusal every geometry entry point in this package
/// makes.
PackResult? packIslands(
  List<Vector2> sizes, {
  required double margin,
  bool allowRotate90 = false,
}) {
  if (sizes.isEmpty || margin < 0) return null;
  for (final size in sizes) {
    if (size.x <= 0 || size.y <= 0) return null;
  }

  final totalArea = sizes.fold(0.0, (double sum, Vector2 s) => sum + s.x * s.y);

  // Binary search on the shelf packer's own target width — not on the final
  // scale directly. A shelf packer's efficiency depends heavily on the width
  // it is given: too narrow wastes height on half-empty rows, too wide
  // wastes width nothing sits against. The width where the packed height
  // comes out equal to the width is the one that turns the whole layout as
  // square as a shelf packer can make it, which is what lets the square this
  // returns waste the least space once it is scaled to a unit square.
  var low = math.sqrt(totalArea) * 0.3;
  var high = math.sqrt(totalArea) * 3.0 + sizes.length * margin;
  for (var i = 0; i < 40; i++) {
    final mid = (low + high) / 2;
    if (_layout(sizes, margin, mid, allowRotate90).height > mid) {
      low = mid;
    } else {
      high = mid;
    }
  }

  final width = high;
  final result = _layout(sizes, margin, width, allowRotate90);
  final side = math.max(width, result.height);
  final scale = 1.0 / side;

  return PackResult(
    islands: <PackedIsland>[
      for (final island in result.islands)
        PackedIsland(
          offset: island.offset..scale(scale),
          rotated: island.rotated,
        ),
    ],
    scale: scale,
    fillRatio: totalArea / (side * side),
  );
}
