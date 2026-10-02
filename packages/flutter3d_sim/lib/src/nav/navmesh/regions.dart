/// The floor cut into regions, each of which becomes one outline.
///
/// ## Monotone, not watershed
///
/// A watershed grows regions from the middle of open floor outward and gives
/// rounder ones, which make better polygons. It also gives regions with holes
/// — a region that flows round a pillar and meets itself on the far side —
/// and an outline with a hole in it needs a pass that cuts the hole into the
/// outline before anything can triangulate it. That pass, and the merging of
/// small regions that a watershed needs to be usable, are most of the code
/// and most of the ways a bake can disagree with itself.
///
/// A monotone sweep cannot make a hole. It goes row by row, and a run of floor
/// continues the region of the run before it only when that region continues
/// into nothing else; so every region is one run per row, the runs of
/// consecutive rows overlap, and a shape like that has no inside to go round.
/// What it costs is regions that are longer and thinner than they need be,
/// which the triangles merged into polygons afterwards mostly hide.
library;

import 'dart:typed_data';

import 'open_field.dart';
import 'span_field.dart';

/// Regions numbered from one, and how many there are. Zero is no region.
({Int32List region, int count}) monotoneRegions(OpenField field) {
  final region = Int32List(field.spanCount);
  // Per sweep in the current row: the region of the row before it continues,
  // how many of its spans reached that region, and the id it ends up with.
  final continues = <int>[];
  final samples = <int>[];
  final ids = <int>[];
  // How many spans of the current row reached each region of the previous.
  final reached = <int, int>{};
  const several = -1;
  var next = 1;

  for (var cz = 0; cz < field.rows; cz++) {
    continues.clear();
    samples.clear();
    ids.clear();
    reached.clear();

    for (var cx = 0; cx < field.columns; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (field.area[s] == nullArea) continue;

        // The sweep this span extends along the row, or a new one.
        final west = field.neighbour(s, 0);
        final sweep =
            west >= 0 && field.area[west] == field.area[s] && region[west] > 0
            ? region[west]
            : () {
                continues.add(0);
                samples.add(0);
                ids.add(0);
                return continues.length;
              }();

        // What the row before says about it.
        final south = field.neighbour(s, 3);
        if (south >= 0 && field.area[south] == field.area[s]) {
          final before = region[south];
          if (before > 0) {
            final k = sweep - 1;
            if (continues[k] == 0 || continues[k] == before) {
              continues[k] = before;
              samples[k]++;
              reached[before] = (reached[before] ?? 0) + 1;
            } else {
              continues[k] = several;
            }
          }
        }
        region[s] = sweep;
      }
    }

    // A sweep keeps the region below it when all of that region's spans in
    // this row are the sweep's — otherwise the region forks here, and each
    // branch is a region of its own.
    for (var k = 0; k < continues.length; k++) {
      final before = continues[k];
      ids[k] = before > 0 && reached[before] == samples[k] ? before : next++;
    }

    for (var cx = 0; cx < field.columns; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (region[s] > 0) region[s] = ids[region[s] - 1];
      }
    }
  }
  return (region: region, count: next - 1);
}
