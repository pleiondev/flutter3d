/// Throwing a solid onto a mark through the world's own air: the velocity
/// the physics core's flight of it brings it down where it was aimed.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'simulation.dart' show Solid;

/// What a throw has to be for the core's own flight to bring a solid down on
/// its mark.
///
/// **Flown, not worked out on paper.** The core moves a body under its
/// world's gravity and drags it through its air, ½ρC_dA|u|u with the drag
/// of its shape (`NativeWorld.setDrag`), so a vacuum's formula throws a
/// light or large solid short and a game that aims by one keeps a number
/// to make up the difference. [aim] throws the solid in a world of its own
/// with the same gravity, air and wind — no ground, nothing else in it — at
/// the step the game steps at, and finds the speed whose flight comes down
/// through the mark's height at the mark: so the throw in the game's world,
/// which flies the same way, lands there too, until something in its way
/// stops it.
abstract final class Ballistics {
  /// The velocity, m/s, that throws [solid] from [from] at [elevation]
  /// radians over the level, heading for [to], so that the core's flight
  /// of it in [world]'s air comes down through [to]'s height at [to].
  ///
  /// The wind is [world]'s where the throw starts, the same along the
  /// flight; a wind across the heading carries the solid aside, and the
  /// throw is aimed at the mark's distance along it, not corrected for
  /// that. [step] is the step the game steps its world at: the flight is
  /// flown at it, so the throw lands where the game's flight of it does.
  ///
  /// Throws an [ArgumentError] when [to] is straight over or under
  /// [from], or when [elevation] cannot reach [to]'s height even in a
  /// vacuum; a [StateError] when no speed carries [solid] so far through
  /// the air at that elevation.
  static Vector3 aim(
    NativeWorld world,
    Solid solid, {
    required Vector3 from,
    required Vector3 to,
    required double elevation,
    double step = 1.0 / 60.0,
  }) {
    final flat = Vector3(to.x - from.x, 0.0, to.z - from.z);
    final reach = flat.length;
    if (!(reach > 0.0)) {
      throw ArgumentError.value(to, 'to', 'straight over or under the throw');
    }
    flat.scale(1.0 / reach);
    final (:sin, :cos) = Portable.sinCos(elevation);
    final along = flat * cos + Vector3(0.0, sin, 0.0);
    final rise = to.y - from.y;
    final g = world.gravityMagnitude;
    // In a vacuum, v² = g·D² / (2·cos²θ·(D·tanθ − h)): where the search
    // starts, and how short of it the air can only make the throw.
    final lift = reach * sin / cos - rise;
    if (!(lift > 0.0) || !(cos > 0.0)) {
      throw ArgumentError.value(
        elevation,
        'elevation',
        'too low to reach a mark ${rise.toStringAsFixed(2)} m higher',
      );
    }
    final vacuum = math.sqrt(g * reach * reach / (2.0 * cos * cos * lift));

    final air = NativeWorld()
      ..gravity = world.gravity
      ..setAir(temperature: world.airTemperature, density: world.airDensity)
      ..wind = world.windAt(from);
    try {
      double past(double speed) =>
          _flight(air, solid, from, along * speed, flat, to.y, step) - reach;
      var lo = vacuum, hi = vacuum;
      var fLo = past(lo), fHi = fLo;
      if (fLo.abs() < 1e-4) return along * vacuum;
      if (fLo > 0.0) {
        // Carried further than a vacuum would: a tail wind.
        while (fLo > 0.0) {
          hi = lo;
          fHi = fLo;
          lo *= 0.75;
          fLo = past(lo);
        }
      } else {
        for (var grown = 0; fHi < 0.0; grown++) {
          if (grown == 40) {
            throw StateError(
              'no throw at ${elevation.toStringAsFixed(3)} rad carries this '
              'solid ${reach.toStringAsFixed(2)} m through the air',
            );
          }
          lo = hi;
          fLo = fHi;
          hi *= 1.5;
          fHi = past(hi);
        }
      }
      // Regula falsi, Illinois: the distance flown rises with the speed.
      var speed = hi;
      var side = 0;
      for (var i = 0; i < 64; i++) {
        speed = (lo * fHi - hi * fLo) / (fHi - fLo);
        final f = past(speed);
        if (f.abs() < 1e-4 || hi - lo < 1e-9) break;
        if (f < 0.0) {
          lo = speed;
          fLo = f;
          if (side == -1) fHi *= 0.5;
          side = -1;
        } else {
          hi = speed;
          fHi = f;
          if (side == 1) fLo *= 0.5;
          side = 1;
        }
      }
      return along * speed;
    } finally {
      air.dispose();
    }
  }

  /// How far along [heading] [solid] thrown from [from] at [velocity]
  /// comes down through [height], flown in [air] at [step]; nought when it
  /// never comes down through it.
  static double _flight(
    NativeWorld air,
    Solid solid,
    Vector3 from,
    Vector3 velocity,
    Vector3 heading,
    double height,
    double step,
  ) {
    final body = air.addBody(position: from, mass: solid.mass);
    try {
      final parts = solid.parts;
      if (parts != null) {
        air.setCompound(body, air.createCompound(parts));
      } else {
        air.setShape(body, solid.shape);
      }
      air
        ..setMaterial(body, solid.material)
        ..setVelocity(body, velocity);
      if (solid.rounding > 0) air.setRounding(body, solid.rounding);
      var before = from.clone();
      // A minute and a half of flight is further than anything a game
      // throws by hand or by charge.
      for (var t = 0.0; t < 90.0; t += step) {
        air.step(step);
        final now = air.localPositionOf(body);
        if (now.y <= height && air.velocityOf(body).y < 0.0) {
          final share = (before.y - height) / (before.y - now.y);
          final at = before + (now - before) * share.clamp(0.0, 1.0);
          return (at - from).dot(heading);
        }
        before = now;
      }
      return 0.0;
    } finally {
      air.removeBody(body);
    }
  }
}
