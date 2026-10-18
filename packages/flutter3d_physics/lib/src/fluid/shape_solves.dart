import 'dart:typed_data';

import 'capillary.dart';
import 'fluid_medium.dart';
import 'free_surface.dart';

/// The cells a surface's cross-section takes, and how many of its modes
/// are wanted: what its modes are worked out from, and all they depend on.
///
/// **The same cross-section, the same request.** The grid is laid on one
/// lattice at every height, so a straight-sided glass has one cross-section
/// all the way up and every tube of a bench the same one: equal requests
/// are one solve.
final class SurfaceModesRequest {
  /// A grid [columns] by [rows] cells [cell] metres square, [index] saying
  /// for each cell row by row which of the inside cells it is (−1 for one
  /// outside), and the lowest [count] modes of it.
  SurfaceModesRequest({
    required this.columns,
    required this.rows,
    required this.cell,
    required Int32List index,
    required this.count,
  }) : index = Int32List.fromList(index),
       _hash = Object.hash(columns, rows, cell, count, Object.hashAll(index));

  /// Cells across, and cells along.
  final int columns;

  /// Cells along the grid, a count.
  final int rows;

  /// A cell's side, in metres.
  final double cell;

  /// Which inside cell each cell of the grid is, row by row; −1 outside.
  final Int32List index;

  /// How many modes, lowest first.
  final int count;

  final int _hash;

  @override
  bool operator ==(Object other) {
    if (other is! SurfaceModesRequest ||
        other._hash != _hash ||
        other.columns != columns ||
        other.rows != rows ||
        other.cell != cell ||
        other.count != count ||
        other.index.length != index.length) {
      return false;
    }
    for (var i = 0; i < index.length; i++) {
      if (other.index[i] != index[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hash;
}

/// A cross-section's modes: each mode's shape over the inside cells,
/// orthonormal under the area, and its k², per square metre.
final class SurfaceModes {
  /// The [shapes] and their [k2].
  const SurfaceModes(this.shapes, this.k2);

  /// One value a cell for each mode, lowest first.
  final List<Float64List> shapes;

  /// Each mode's wavenumber squared, per square metre.
  final Float64List k2;
}

/// What a meniscus is worked out from: the liquid, the radius of the tube
/// at its surface, in metres, and the gravity, in metres per second
/// squared.
final class MeniscusRequest {
  /// The meniscus of [medium] in a tube of [radius] under [g].
  const MeniscusRequest({
    required this.medium,
    required this.radius,
    required this.g,
  });

  /// The liquid.
  final FluidMedium medium;

  /// The tube's radius at the surface, in metres.
  final double radius;

  /// How strong gravity is, in metres per second squared.
  final double g;

  @override
  bool operator ==(Object other) =>
      other is MeniscusRequest &&
      other.medium.density == medium.density &&
      other.medium.surfaceTension == medium.surfaceTension &&
      other.medium.contactAngle == medium.contactAngle &&
      other.radius == radius &&
      other.g == g;

  @override
  int get hashCode => Object.hash(
    medium.density,
    medium.surfaceTension,
    medium.contactAngle,
    radius,
    g,
  );
}

/// Where the once-only solves of a liquid's shapes are worked out: a
/// cross-section's modes ([FreeSurface]) and a meniscus ([TubeMeniscus]).
///
/// **Solved once, for every vessel alike.** The answers depend on nothing
/// but their request, so they are kept in [LiquidShapeCache.shared] and a
/// bench's six tubes ask once between them.
///
/// **By default, at once** ([immediate]). Another solver may work an
/// answer out elsewhere — on another isolate, so a cross-section not met
/// before does not stop a frame — and answer null until it has it; the
/// surface then keeps the modes it has and the vessel goes without its
/// meniscus for those steps. The answers are the same numbers, only when
/// they arrive differs, so a world that must replay to the bit takes only
/// a solver that [answersAtOnce] (`FluidWorld` refuses another).
///
/// **The interface only lives here.** `flutter3d_physics` is plain Dart and
/// starts no isolate; a solver in the background is another package's
/// (`flutter3d_physics_native`'s `BackgroundShapeSolver`).
abstract base class LiquidShapeSolver {
  /// A solver that works answers out at once unless a subclass says
  /// otherwise.
  const LiquidShapeSolver();

  /// The solver that works everything out when it is asked.
  static const LiquidShapeSolver immediate = _Immediate();

  /// Whether every answer is given when it is asked for: true here, false
  /// for a solver that may answer null.
  bool get answersAtOnce => true;

  /// [request]'s modes, or null while they are being worked out elsewhere.
  SurfaceModes? surfaceModes(SurfaceModesRequest request) =>
      LiquidShapeCache.shared.surfaceModes(request) ??
      LiquidShapeCache.shared.keepSurfaceModes(
        request,
        solveSurfaceModes(request),
      );

  /// [request]'s meniscus, or null while it is being worked out elsewhere.
  TubeMeniscus? meniscus(MeniscusRequest request) =>
      LiquidShapeCache.shared.meniscus(request) ??
      LiquidShapeCache.shared.keepMeniscus(request, solveMeniscus(request));
}

final class _Immediate extends LiquidShapeSolver {
  const _Immediate();
}

/// [request]'s meniscus, worked out now.
TubeMeniscus solveMeniscus(MeniscusRequest request) =>
    TubeMeniscus(medium: request.medium, radius: request.radius, g: request.g);

/// The answers kept, by their requests: read only once kept, and so shared
/// between every surface and vessel.
final class LiquidShapeCache {
  LiquidShapeCache._();

  /// The one every solver keeps its answers in.
  static final LiquidShapeCache shared = LiquidShapeCache._();

  /// At most this many of each are kept; past it the oldest go.
  static const int capacity = 512;

  final Map<SurfaceModesRequest, SurfaceModes> _modes = {};
  final Map<MeniscusRequest, TubeMeniscus> _menisci = {};

  /// The modes kept for [request], or null.
  SurfaceModes? surfaceModes(SurfaceModesRequest request) => _modes[request];

  /// Keeps [modes] for [request], and answers them.
  SurfaceModes keepSurfaceModes(
    SurfaceModesRequest request,
    SurfaceModes modes,
  ) {
    if (_modes.length >= capacity) _modes.remove(_modes.keys.first);
    return _modes[request] = modes;
  }

  /// The meniscus kept for [request], or null.
  TubeMeniscus? meniscus(MeniscusRequest request) => _menisci[request];

  /// Keeps [meniscus] for [request], and answers it.
  TubeMeniscus keepMeniscus(MeniscusRequest request, TubeMeniscus meniscus) {
    if (_menisci.length >= capacity) _menisci.remove(_menisci.keys.first);
    return _menisci[request] = meniscus;
  }

  /// Forgets everything kept: for a test that times a solve.
  void clear() {
    _modes.clear();
    _menisci.clear();
  }
}
