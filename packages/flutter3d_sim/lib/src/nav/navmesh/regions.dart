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

/// How the lattice is cut into tiles, and which of them to work on.
///
/// [size] is in cells; nought is one tile over the whole lattice. [across]
/// is how many tiles a row of the lattice has.
typedef NavTiles = ({int size, int across, int x0, int z0, int x1, int z1});

/// The first region number of [tile]: the tile's own number in the upper
/// bits, so a region is named by where it is and the same region gets the
/// same number however much of the lattice is being baked.
int tileRegionBase(int tile) => tile << 16;

/// Regions, numbered from [tileRegionBase] of their tile plus one; zero is
/// no region. Only the spans of the tiles `[x0, x1)` by `[z0, z1)` of
/// [tiles] are given one, each tile swept on its own: a region never
/// crosses a tile's edge, which is what lets a tile be baked again without
/// its neighbours.
Int32List monotoneRegions(OpenField field, {required NavTiles tiles}) {
  final region = Int32List(field.spanCount);
  final size = tiles.size;
  for (var tz = tiles.z0; tz < tiles.z1; tz++) {
    for (var tx = tiles.x0; tx < tiles.x1; tx++) {
      // The tile's columns in this field's own numbering.
      final x0 = size == 0 ? 0 : tx * size - field.offsetX;
      final z0 = size == 0 ? 0 : tz * size - field.offsetZ;
      final x1 = size == 0 ? field.columns : x0 + size;
      final z1 = size == 0 ? field.rows : z0 + size;
      _sweep(
        field,
        region,
        tileRegionBase(tz * tiles.across + tx),
        x0 < 0 ? 0 : x0,
        z0 < 0 ? 0 : z0,
        x1 > field.columns ? field.columns : x1,
        z1 > field.rows ? field.rows : z1,
      );
    }
  }
  return region;
}

/// The monotone sweep over columns `[x0, x1)` by `[z0, z1)` of [field],
/// numbering regions from [base] plus one.
void _sweep(
  OpenField field,
  Int32List region,
  int base,
  int x0,
  int z0,
  int x1,
  int z1,
) {
  // Per sweep in the current row: the region of the row before it continues,
  // how many of its spans reached that region, and the id it ends up with.
  final continues = <int>[];
  final samples = <int>[];
  final ids = <int>[];
  // How many spans of the current row reached each region of the previous.
  final reached = <int, int>{};
  const several = -1;
  var next = base + 1;

  for (var cz = z0; cz < z1; cz++) {
    continues.clear();
    samples.clear();
    ids.clear();
    reached.clear();

    for (var cx = x0; cx < x1; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (field.area[s] == nullArea) continue;

        // The sweep this span extends along the row, or a new one. Nothing
        // west of the tile's first column is the tile's.
        final west = cx > x0 ? field.neighbour(s, 0) : -1;
        final sweep =
            west >= 0 && field.area[west] == field.area[s] && region[west] > 0
            ? region[west]
            : () {
                continues.add(0);
                samples.add(0);
                ids.add(0);
                return continues.length;
              }();

        // What the row before says about it, if that row is the tile's.
        final south = cz > z0 ? field.neighbour(s, 3) : -1;
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
    assert(next - base < 1 << 16, 'a tile with more regions than it can name');

    for (var cx = x0; cx < x1; cx++) {
      final c = cz * field.columns + cx;
      for (var s = field.cellStart[c]; s < field.cellStart[c + 1]; s++) {
        if (region[s] > 0) region[s] = ids[region[s] - 1];
      }
    }
  }
}
