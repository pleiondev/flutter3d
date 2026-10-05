/// The space above every floor, and which floors an agent walks between.
library;

import 'dart:typed_data';

import 'span_field.dart';

/// Directions, in the order every stage walks them: −x, +z, +x, −z. Each is
/// the previous one turned a quarter the same way round, so `dir + 1` and
/// `dir + 3` are the two turns the contour walk takes.
const List<int> dirX = <int>[-1, 0, 1, 0];
const List<int> dirZ = <int>[0, 1, 0, -1];

/// One open span per floor: from the top of a solid span up to the bottom of
/// the next one, with links to the floors beside it.
///
/// Flat arrays rather than objects, indexed by span, because every stage after
/// this one is a sweep over all of them in the same fixed order — column by
/// column, lowest floor first — and that order is the bake's determinism.
final class OpenField {
  OpenField._({
    required this.columns,
    required this.rows,
    required this.offsetX,
    required this.offsetZ,
    required this.cellStart,
    required this.floor,
    required this.ceiling,
    required this.area,
    required this.links,
  });

  final int columns;
  final int rows;

  /// The lattice column and row of this field's column `(0, 0)`: nought for
  /// a whole level, the window's corner for a part of one baked again.
  final int offsetX;
  final int offsetZ;

  /// Spans of column `c` are `cellStart[c]` up to `cellStart[c + 1]`.
  final Int32List cellStart;

  /// In voxels.
  final Int32List floor;
  final Int32List ceiling;

  /// The walking surface, or [nullArea] once a filter has refused the span.
  final Uint8List area;

  /// `links[span * 4 + dir]`: the span stepped onto in that direction, or −1.
  final Int32List links;

  int get spanCount => floor.length;

  /// The span an agent reaches from [span] in [dir], or −1 when it reaches
  /// none — no link, or a link to a span a later filter refused.
  int neighbour(int span, int dir) {
    final next = links[span * 4 + dir];
    return next < 0 || area[next] == nullArea ? -1 : next;
  }

  /// Builds the open spans over every floor of [solid] and links them.
  ///
  /// Two floors side by side are linked when the step between them is at
  /// most [climb] and the gap they share is at least [height] tall — an agent
  /// has to fit through the opening, not only under each ceiling apart. Of
  /// the floors in the next column the lowest that qualifies wins; for an
  /// agent shorter than twice its step there can only be one.
  static OpenField build(
    SpanField solid, {
    required int height,
    required int climb,
  }) {
    final count = solid.columns * solid.rows;
    final cellStart = Int32List(count + 1);
    final floors = <int>[];
    final ceilings = <int>[];
    final areas = <int>[];
    for (var c = 0; c < count; c++) {
      cellStart[c] = floors.length;
      final column = solid.spans[c];
      for (var i = 0; i < column.length; i++) {
        if (column[i].area == nullArea) continue;
        floors.add(column[i].max);
        ceilings.add(i + 1 < column.length ? column[i + 1].min : SpanField.sky);
        areas.add(column[i].area);
      }
    }
    cellStart[count] = floors.length;

    final floor = Int32List.fromList(floors);
    final ceiling = Int32List.fromList(ceilings);
    final links = Int32List(floors.length * 4)
      ..fillRange(0, floors.length * 4, -1);

    for (var cz = 0; cz < solid.rows; cz++) {
      for (var cx = 0; cx < solid.columns; cx++) {
        final c = cz * solid.columns + cx;
        for (var s = cellStart[c]; s < cellStart[c + 1]; s++) {
          for (var dir = 0; dir < 4; dir++) {
            final nx = cx + dirX[dir];
            final nz = cz + dirZ[dir];
            if (nx < 0 || nz < 0 || nx >= solid.columns || nz >= solid.rows) {
              continue;
            }
            final n = nz * solid.columns + nx;
            for (var t = cellStart[n]; t < cellStart[n + 1]; t++) {
              final bottom = floor[s] > floor[t] ? floor[s] : floor[t];
              final top = ceiling[s] < ceiling[t] ? ceiling[s] : ceiling[t];
              if (top - bottom >= height &&
                  (floor[t] - floor[s]).abs() <= climb) {
                links[s * 4 + dir] = t;
                break;
              }
            }
          }
        }
      }
    }

    return OpenField._(
      columns: solid.columns,
      rows: solid.rows,
      offsetX: solid.offsetX,
      offsetZ: solid.offsetZ,
      cellStart: cellStart,
      floor: floor,
      ceiling: ceiling,
      area: Uint8List.fromList(areas),
      links: links,
    );
  }
}
