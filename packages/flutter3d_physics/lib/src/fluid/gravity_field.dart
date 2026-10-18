import 'dart:math' as math;

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

/// Gravity that is not the same everywhere: what a `FluidWorld` asks where
/// each vessel, drop and parcel of a stream is.
///
/// **Two ways to say it.** [AttractorGravity] is the law itself — a uniform
/// part and the pull of each [Attractor] — and [SampledGravity] reads a
/// field of the shared field contract (S3), a grid of `f3d.gravity` in
/// m/s², three values a cell, that a subsystem, a plugin or
/// [AttractorGravity.writeField] wrote. The same field a renderer or a
/// solver of another package reads, so the liquids fall by the gravity
/// the rest of the world is shown and stepped with.
///
/// **Extended outside this package**: `abstract base`, so a member a minor
/// adds arrives with a default.
abstract final class GravityField {
  const GravityField();

  /// The quantity a gravity field holds, by its id in the field contract.
  static const String quantity = 'f3d.gravity';

  /// The gravity at [point], m/s²: a vector of the caller's own.
  Vector3 at(Vector3 point);
}

/// Gravity as a uniform part and the pull of every [Attractor] in it,
/// added.
///
/// **Newton's law for each**: g = μ·r̂/r², μ = G·M the attractor's standard
/// gravitational parameter, pointing at it. Inside an attractor of
/// [Attractor.radius], uniform in density, it falls off to nought at the
/// middle as μ·r/R³ (the shell outside pulls equally every way), so a drop
/// that passes through one is not flung off by a pull growing without
/// bound.
final class AttractorGravity extends GravityField {
  /// [uniform] everywhere, m/s² (nought when not given), and the pull of
  /// each of [attractors].
  AttractorGravity({Vector3? uniform, List<Attractor>? attractors})
    : uniform = uniform?.clone() ?? Vector3.zero(),
      attractors = attractors ?? <Attractor>[];

  /// Metres per second squared, everywhere.
  final Vector3 uniform;

  /// What pulls, each by its own law; a list the caller may change.
  final List<Attractor> attractors;

  @override
  Vector3 at(Vector3 point) {
    final g = uniform.clone();
    for (final a in attractors) {
      final dx = a.position.x - point.x;
      final dy = a.position.y - point.y;
      final dz = a.position.z - point.z;
      final r2 = dx * dx + dy * dy + dz * dz;
      if (r2 <= 0.0) continue;
      final r = math.sqrt(r2);
      final k = r < a.radius
          ? a.mu / (a.radius * a.radius * a.radius)
          : a.mu / (r2 * r);
      g
        ..x += dx * k
        ..y += dy * k
        ..z += dz * k;
    }
    return g;
  }

  /// This gravity as a field of the field contract: [declaration]'s grid,
  /// three values a cell, each cell its middle's gravity. Throws an
  /// [ArgumentError] for a declaration that does not hold
  /// [GravityField.quantity] three values a cell.
  HostField writeField(FieldDeclaration declaration) {
    _checkDeclaration(declaration);
    final field = HostField(declaration);
    final grid = declaration.grid;
    for (var z = 0; z < grid.depth; z++) {
      for (var y = 0; y < grid.height; y++) {
        for (var x = 0; x < grid.width; x++) {
          final p = declaration.transform.worldOf(
            FieldCoordinate(x.toDouble(), y.toDouble(), z.toDouble()),
          );
          final g = at(Vector3(p.x, p.y, p.z));
          for (var k = 0; k < 3; k++) {
            field.setValueAt(x, y, z, g[k], component: k);
          }
        }
      }
    }
    return field;
  }
}

/// Gravity read off a field of the field contract: a grid of
/// [GravityField.quantity], three values a cell, blended between the eight
/// cells about a point and held at the edge cells' values past the grid.
final class SampledGravity extends GravityField {
  /// The gravity [field] holds. Throws an [ArgumentError] for a field that
  /// does not hold [GravityField.quantity] three values a cell.
  SampledGravity(this.field) {
    _checkDeclaration(field.declaration);
  }

  /// The field read, as its writer keeps it: a change to its values is
  /// read at the next step.
  final HostField field;

  @override
  Vector3 at(Vector3 point) {
    final p = WorldPosition(point.x, point.y, point.z);
    return Vector3(
      field.sample(p),
      field.sample(p, component: 1),
      field.sample(p, component: 2),
    );
  }
}

void _checkDeclaration(FieldDeclaration declaration) {
  if (declaration.quantity != GravityField.quantity ||
      declaration.grid.components != 3) {
    throw ArgumentError.value(
      declaration.id,
      'declaration',
      'a gravity field holds ${GravityField.quantity}, three values a cell, '
          'not ${declaration.quantity} in ${declaration.grid.components}',
    );
  }
  if (declaration.unit != Unit.meterPerSecondSquared) {
    throw ArgumentError.value(
      declaration.unit,
      'declaration',
      'a gravity field is in m/s²',
    );
  }
}

/// A mass that pulls: where it is, how hard, and how big.
final class Attractor {
  /// An attractor at [position] of standard gravitational parameter [mu],
  /// m³/s², [radius] metres across its middle.
  Attractor({required this.position, required this.mu, this.radius = 0.0});

  /// An attractor of [mass] kilograms, by Newton's constant.
  factory Attractor.ofMass({
    required Vector3 position,
    required double mass,
    double radius = 0.0,
  }) => Attractor(
    position: position,
    mu: gravitationalConstant * mass,
    radius: radius,
  );

  /// Newton's G, m³/(kg·s²) (CODATA 2018).
  static const double gravitationalConstant = 6.67430e-11;

  /// Where it is; move it and the field moves with it.
  final Vector3 position;

  /// G·M, cubic metres per second squared.
  final double mu;

  /// Metres: inside it the pull falls to nought at the middle.
  final double radius;
}
