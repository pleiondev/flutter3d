import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show RetiredParticles;

/// Liquid spilt on the bench that has come to rest there, as a film over a
/// grid of cells [cell] metres square: no longer particles, only how much
/// lies in each cell and what is dissolved in all of it.
///
/// **The volume is kept, not guessed.** Every particle that lands here adds
/// its volume to the cell under it, and a cell is drawn as deep as what it
/// holds over its area; what lands off the edge of the top is counted in
/// [offTheTop] and drawn nowhere, as liquid run off a table is. So
/// [volume] is every cubic metre retired here, and the bench's world still
/// counts the same.
final class Puddles {
  Puddles({
    required this.cell,
    required this.minX,
    required this.maxX,
    required this.minZ,
    required this.maxZ,
  });

  /// A cell's side, in metres.
  final double cell;

  /// The top's extent: what comes to rest outside it has run off.
  final double minX;
  final double maxX;
  final double minZ;
  final double maxZ;

  final Map<int, double> _cells = {};
  final Map<String, double> _amounts = {};
  double _onTop = 0.0;
  double _off = 0.0;

  /// Cubic metres lying on the top.
  double get onTop => _onTop;

  /// Cubic metres that came to rest past its edge, which is off the table.
  double get offTheTop => _off;

  /// Every cubic metre retired here, on the top or off it.
  double get volume => _onTop + _off;

  /// How many cells are wet.
  int get wetCells => _cells.length;

  /// What is dissolved in it all, as concentrations: one mixture, since a
  /// film this thin shows no colour of its own worth telling apart.
  Map<String, double> get concentrations => {
    if (volume > 0.0)
      for (final e in _amounts.entries) e.key: e.value / volume,
  };

  /// Lays [gone] down where each particle and each drop came to rest.
  void add(RetiredParticles gone) {
    gone.amounts.forEach((key, amount) {
      _amounts[key] = (_amounts[key] ?? 0.0) + amount;
    });
    for (final p in gone.positions) {
      _lay(p, gone.particleVolume);
    }
    for (final drop in gone.drops) {
      _lay(drop.position, drop.volume);
    }
  }

  void _lay(Vector3 p, double volume) {
    if (p.x < minX || p.x > maxX || p.z < minZ || p.z > maxZ) {
      _off += volume;
      return;
    }
    final key = _key((p.x / cell).floor(), (p.z / cell).floor());
    _cells[key] = (_cells[key] ?? 0.0) + volume;
    _onTop += volume;
  }

  static const int _span = 1 << 15;
  static const int _half = 1 << 14;
  static int _key(int i, int k) => (i + _half) * _span + (k + _half);

  /// How deep cell (i, k) is, in metres: nought where it is dry.
  double _depth(int i, int k) => (_cells[_key(i, k)] ?? 0.0) / (cell * cell);

  /// The film as a mesh: a quad per wet cell, each corner as high as the
  /// four cells round it are deep on average, so a lone cell is a low
  /// mound and a puddle's edge comes down to the bench. [lift] keeps it
  /// clear of the top it lies on.
  MeshData mesh({double lift = 0.0002}) {
    final builder = MeshBuilder(VertexLayout.standard);
    final corners = <int, int>{};
    double height(int i, int k) =>
        0.25 *
        (_depth(i - 1, k - 1) +
            _depth(i, k - 1) +
            _depth(i - 1, k) +
            _depth(i, k));
    int corner(int i, int k) => corners.putIfAbsent(_key(i, k), () {
      // The slope from the corners either side, for the normal.
      final dx = (height(i + 1, k) - height(i - 1, k)) / (2.0 * cell);
      final dz = (height(i, k + 1) - height(i, k - 1)) / (2.0 * cell);
      return builder.addVertex(
        position: Vector3(i * cell, lift + height(i, k), k * cell),
        normal: Vector3(-dx, 1.0, -dz)..normalize(),
        texcoord: Vector2.zero(),
      );
    });
    for (final key in _cells.keys) {
      final i = key ~/ _span - _half;
      final k = key % _span - _half;
      final a = corner(i, k);
      final b = corner(i + 1, k);
      final c = corner(i + 1, k + 1);
      final d = corner(i, k + 1);
      // Counter-clockwise seen from above.
      builder
        ..addTriangle(a, d, c)
        ..addTriangle(a, c, b);
    }
    return builder.build();
  }

  /// The deepest a cell is, in metres.
  double get deepest =>
      _cells.values.fold(0.0, (m, v) => math.max(m, v / (cell * cell)));
}
