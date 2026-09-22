import 'dart:math' as math;
import 'dart:typed_data';

/// A grid of particles and the constraints between them, as flat arrays —
/// the shape every hot loop in this package walks without an allocation.
///
/// **Column-major in [cols]/[rows], row 0 pinned by [ClothMesh.grid].** A
/// particle's own index is `row * cols + col`; three consecutive doubles in
/// [positions]/[velocities] starting at `3 * index` are its own x/y/z.
final class ClothMesh {
  ClothMesh({
    required this.cols,
    required this.rows,
    required this.positions,
    required this.velocities,
    required this.invMass,
    required this.structuralPairs,
    required this.structuralRestLength,
    required this.bendPairs,
    required this.bendRestLength,
    required this.triangles,
  }) : particleCount = cols * rows;

  final int cols;
  final int rows;
  final int particleCount;

  /// `3 * particleCount` doubles, x/y/z per particle.
  final Float64List positions;

  /// `3 * particleCount` doubles. A pinned particle's own velocity is never
  /// written by the solver (its `invMass` is zero, so no force or
  /// correction ever reaches it) and stays whatever it was constructed
  /// with — zero, from [ClothMesh.grid].
  final Float64List velocities;

  /// One entry per particle; zero for a pinned particle, `1 / mass`
  /// otherwise. Every correction in the solver is scaled by this, which is
  /// the entire mechanism a pin works through — no separate pinned flag.
  final Float64List invMass;

  /// Structural (edge-length) constraints, particle index pairs.
  final Int32List structuralPairs;
  final Float64List structuralRestLength;

  /// Cross-edge bending constraints: for a pair of grid quads sharing an
  /// edge, the distance between the two corners the shared edge does not
  /// touch. Same pair/rest-length shape as [structuralPairs], solved with
  /// its own, softer compliance.
  final Int32List bendPairs;
  final Float64List bendRestLength;

  /// Three particle indices per triangle, for wind's own drag-along-normal
  /// force. Two triangles per grid quad.
  final Int32List triangles;

  /// A flat `cols * rows` grid of particles, `spacing` apart, lying in the
  /// XZ plane at `y = height` before gravity does anything to it — the top
  /// row (`row == 0`) pinned in place, so the sheet hangs rather than falls
  /// forever with nothing to react against.
  ///
  /// [pinCorners] pins the top row's own two ends only, instead of the
  /// whole row — a flag rather than a curtain. Both are real, common cloth
  /// setups; a curtain settles into a flatter, less oscillatory rest shape,
  /// which is what the test suite's own "comes to rest" checks lean on for
  /// a smaller number of steps.
  factory ClothMesh.grid({
    required int cols,
    required int rows,
    double spacing = 0.1,
    double height = 0,
    double mass = 0.05,
    bool pinCorners = false,
  }) {
    final particleCount = cols * rows;
    final positions = Float64List(3 * particleCount);
    final velocities = Float64List(3 * particleCount);
    final invMass = Float64List(particleCount);
    final invMassValue = mass <= 0 ? 0.0 : 1.0 / mass;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final i = row * cols + col;
        positions[3 * i] = col * spacing;
        positions[3 * i + 1] = height;
        positions[3 * i + 2] = row * spacing;
        final pinned = row == 0 && (!pinCorners || col == 0 || col == cols - 1);
        invMass[i] = pinned ? 0.0 : invMassValue;
      }
    }

    final structuralPairs = <int>[];
    final structuralRestLength = <double>[];
    void addStructural(int a, int b) {
      structuralPairs
        ..add(a)
        ..add(b);
      structuralRestLength.add(_distance(positions, a, b));
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final i = row * cols + col;
        if (col + 1 < cols) addStructural(i, i + 1);
        if (row + 1 < rows) addStructural(i, i + cols);
      }
    }

    final triangles = <int>[];
    for (var row = 0; row + 1 < rows; row++) {
      for (var col = 0; col + 1 < cols; col++) {
        final tl = row * cols + col;
        final tr = tl + 1;
        final bl = tl + cols;
        final br = bl + 1;
        // Two triangles per quad, wound the same way, sharing the tl-br
        // diagonal — the edge every bending constraint below crosses.
        triangles.addAll([tl, bl, br, tl, br, tr]);
      }
    }

    // Cross-edge bending: skip-one neighbours along each row and column,
    // which is exactly the pair of corners a quad's own two triangles do
    // not share when the quad next to it is folded along their common
    // edge — the "cross-edge" the row's own text names, without carrying
    // a full per-quad dihedral-angle constraint to get there.
    final bendPairs = <int>[];
    final bendRestLength = <double>[];
    void addBend(int a, int b) {
      bendPairs
        ..add(a)
        ..add(b);
      bendRestLength.add(_distance(positions, a, b));
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final i = row * cols + col;
        if (col + 2 < cols) addBend(i, i + 2);
        if (row + 2 < rows) addBend(i, i + 2 * cols);
      }
    }

    return ClothMesh(
      cols: cols,
      rows: rows,
      positions: positions,
      velocities: velocities,
      invMass: invMass,
      structuralPairs: Int32List.fromList(structuralPairs),
      structuralRestLength: Float64List.fromList(structuralRestLength),
      bendPairs: Int32List.fromList(bendPairs),
      bendRestLength: Float64List.fromList(bendRestLength),
      triangles: Int32List.fromList(triangles),
    );
  }

  static double _distance(Float64List p, int a, int b) {
    final dx = p[3 * a] - p[3 * b];
    final dy = p[3 * a + 1] - p[3 * b + 1];
    final dz = p[3 * a + 2] - p[3 * b + 2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}
