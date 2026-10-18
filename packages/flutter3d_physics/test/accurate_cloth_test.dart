/// A sheet under the accurate profile: its rigid edges held to their
/// lengths, what it falls on kept out of it, and a spring's period the
/// spring's.
///
///     dart test test/accurate_cloth_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _accurate = ClothSettings(profile: SimulationProfile.accurate);

void main() {
  test('a falling sheet keeps every edge its length', () {
    final sheet = ClothMesh.grid(cols: 6, rows: 6, height: 1.0);
    for (var i = 0; i < 60; i++) {
      stepCloth(sheet, _accurate, 1 / 60);
    }
    final p = sheet.positions;
    var worst = 0.0;
    for (var k = 0; k < sheet.structuralRestLength.length; k++) {
      final a = sheet.structuralPairs[2 * k],
          b = sheet.structuralPairs[2 * k + 1];
      final d = math.sqrt(
        math.pow(p[3 * a] - p[3 * b], 2) +
            math.pow(p[3 * a + 1] - p[3 * b + 1], 2) +
            math.pow(p[3 * a + 2] - p[3 * b + 2], 2),
      );
      worst = math.max(worst, (d - sheet.structuralRestLength[k]).abs());
    }
    // Mutation: drop the projection after each step and the edges drift.
    expect(worst, lessThan(1e-9));
  });

  test('a sheet dropped on a ball stays outside it and comes to no harm', () {
    // Pinned at two corners, so it drapes and folds: the case whose
    // constraints say the same thing twice.
    final sheet = ClothMesh.grid(
      cols: 6,
      rows: 6,
      height: 1.0,
      pinCorners: true,
    );
    final ball = ClothObstacle(CollisionSphere(0.2), Vector3(0.25, 0.6, 0.25));
    for (var i = 0; i < 60; i++) {
      stepCloth(sheet, _accurate, 1 / 60, obstacles: <ClothObstacle>[ball]);
    }
    final p = sheet.positions;
    for (var i = 0; i < sheet.particleCount; i++) {
      final d = math.sqrt(
        math.pow(p[3 * i] - 0.25, 2) +
            math.pow(p[3 * i + 1] - 0.6, 2) +
            math.pow(p[3 * i + 2] - 0.25, 2),
      );
      expect(d, greaterThan(0.2), reason: 'particle $i inside the ball');
      expect(p[3 * i + 1].isFinite, isTrue);
    }
  });

  test("a compliant edge is a spring, and swings at the spring's period", () {
    // One particle of 0.05 kg on an edge of compliance 1e-3 m/N, no
    // gravity: a spring of 1000 N/m, ω = √(k/m), stretched by a centimetre.
    final mesh = ClothMesh.grid(cols: 1, rows: 2, spacing: 1.0);
    mesh.positions[5] = 1.01;
    final settings = _accurate.copyWith(
      gravity: 0.0,
      damping: 0.0,
      distanceCompliance: 1e-3,
      selfCollision: false,
    );
    const dt = 1 / 600;
    for (var i = 0; i < 600; i++) {
      stepCloth(mesh, settings, dt);
    }
    final omega = math.sqrt(1000.0 / 0.05);
    expect(mesh.positions[5], closeTo(1.0 + 0.01 * math.cos(omega), 1e-9));
  });
}
