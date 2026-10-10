import '../save/game_random.dart';

/// One tile wave function collapse may put in a cell: what each of its four
/// sides offers its neighbour, and how often it is chosen against the
/// others.
///
/// Two cells side by side agree when the sockets they turn to each other
/// are the same word — a doorway against a doorway, a wall against a wall —
/// which is the whole of the adjacency a tile set has to state.
final class WfcTile {
  const WfcTile(this.name, {required this.sockets, this.weight = 1.0});

  /// What the tile is called, for whoever turns a solved grid into a level.
  final String name;

  /// North (−z), east (+x), south (+z) and west (−x), in that order.
  final List<String> sockets;

  /// How likely it is against the others a cell could still be.
  final double weight;
}

/// Fills a [width] × [height] grid with [tiles] so that every pair of
/// neighbours agrees, and the sides facing out of the grid offer [edge] —
/// or answers null where the choices made ran into a cell nothing fits.
///
/// **Wave function collapse, in its plainest form.** Every cell starts able
/// to be any tile; the cell with the fewest choices left is decided, by
/// weight, from [random]; and what that rules out of its neighbours, and
/// theirs, is carried through until nothing more changes. A grid whose
/// tiles can always meet does not fail; one that can is the caller's to
/// try again, with the next seed.
///
/// **The same seed, the same grid**, on every platform: the choices come
/// from [GameRandom], ties between cells go to the lowest index, and
/// nothing else is consulted. A level built from it is a level a replay
/// can build again.
///
/// [fixed] decides cells before anything else: a cell index to the tile
/// index it must be — a start room where the generator wants one.
List<int>? collapse({
  required int width,
  required int height,
  required List<WfcTile> tiles,
  required GameRandom random,
  String? edge,
  Map<int, int> fixed = const <int, int>{},
}) {
  assert(tiles.isNotEmpty && tiles.length <= 30, 'a mask per cell');
  assert(
    tiles.every((WfcTile tile) => tile.sockets.length == 4),
    'every tile has four sides: north, east, south and west',
  );
  final count = width * height;
  final all = (1 << tiles.length) - 1;
  // Which tiles each cell may still be, one bit per tile.
  final possible = List<int>.filled(count, all);

  // Which tiles may stand on each side of each tile: `meets[side][tile]`, a
  // mask of the tiles whose opposite side offers the same socket.
  final meets = <List<int>>[
    for (var side = 0; side < 4; side++)
      <int>[
        for (final tile in tiles)
          tiles.indexed.fold(
            0,
            (int mask, (int, WfcTile) other) =>
                other.$2.sockets[(side + 2) % 4] == tile.sockets[side]
                ? mask | (1 << other.$1)
                : mask,
          ),
      ],
  ];

  int neighbour(int cell, int side) {
    final x = cell % width;
    final z = cell ~/ width;
    return switch (side) {
      0 => z > 0 ? cell - width : -1,
      1 => x < width - 1 ? cell + 1 : -1,
      2 => z < height - 1 ? cell + width : -1,
      _ => x > 0 ? cell - 1 : -1,
    };
  }

  final pending = <int>[];
  // What [cell] being among [possible] allows on its [side].
  int allowedBeside(int cell, int side) {
    var mask = 0;
    for (var t = 0; t < tiles.length; t++) {
      if (possible[cell] & (1 << t) != 0) mask |= meets[side][t];
    }
    return mask;
  }

  bool settle() {
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      for (var side = 0; side < 4; side++) {
        final next = neighbour(cell, side);
        if (next < 0) continue;
        final narrowed = possible[next] & allowedBeside(cell, side);
        if (narrowed == possible[next]) continue;
        if (narrowed == 0) return false;
        possible[next] = narrowed;
        pending.add(next);
      }
    }
    return true;
  }

  // The outside: a side facing out of the grid offers [edge].
  if (edge != null) {
    for (var cell = 0; cell < count; cell++) {
      for (var side = 0; side < 4; side++) {
        if (neighbour(cell, side) >= 0) continue;
        var mask = 0;
        for (var t = 0; t < tiles.length; t++) {
          if (tiles[t].sockets[side] == edge) mask |= 1 << t;
        }
        possible[cell] &= mask;
      }
      if (possible[cell] == 0) return null;
      pending.add(cell);
    }
  }
  for (final MapEntry(key: cell, value: tile) in fixed.entries) {
    possible[cell] &= 1 << tile;
    if (possible[cell] == 0) return null;
    pending.add(cell);
  }
  if (!settle()) return null;

  int choices(int mask) {
    var n = 0;
    for (var m = mask; m != 0; m &= m - 1) {
      n++;
    }
    return n;
  }

  while (true) {
    // The undecided cell with the fewest choices; the first such, by index.
    var cell = -1;
    var fewest = 1 << 30;
    for (var c = 0; c < count; c++) {
      final n = choices(possible[c]);
      if (n > 1 && n < fewest) {
        fewest = n;
        cell = c;
      }
    }
    if (cell < 0) break;

    // One of its choices, by weight.
    final options = <int>[
      for (var t = 0; t < tiles.length; t++)
        if (possible[cell] & (1 << t) != 0) t,
    ];
    final total = options.fold(
      0.0,
      (double sum, int t) => sum + tiles[t].weight,
    );
    var roll = random.nextDouble() * total;
    var chosen = options.last;
    for (final t in options) {
      roll -= tiles[t].weight;
      if (roll < 0.0) {
        chosen = t;
        break;
      }
    }
    possible[cell] = 1 << chosen;
    pending.add(cell);
    if (!settle()) return null;
  }

  return <int>[for (final mask in possible) mask.bitLength - 1];
}
