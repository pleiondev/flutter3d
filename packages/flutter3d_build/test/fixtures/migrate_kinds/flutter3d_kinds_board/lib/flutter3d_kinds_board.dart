// A second engine package for the migration kinds: a board game's pieces.
// 0.8: `class Unit` here; `BoardUnit` since, the name `Unit` taken by
// `flutter3d_kinds`'s unit of measurement.

final class BoardUnit {
  const BoardUnit(this.side);
  final int side;
}
