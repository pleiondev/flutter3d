import 'dart:math' as math;
import 'dart:typed_data';

import '../level/heightfield.dart';
import '../save/game_random.dart';

/// [field] after scree has slid: wherever a sample stands more than
/// [talus] above a neighbour, part of the difference moves down to it, pass
/// after pass, until no slope is steeper than the rock would hold.
///
/// **Thermal erosion**, the slow one: frost splitting a cliff and the
/// pieces coming to rest at their angle. [talus] is the steepest step one
/// sample may stand above the next, in metres, and [rate] the share of the
/// excess that moves in a pass; [passes] of them. What moves is taken from
/// one sample and given to the others, so the ground's total is what it
/// was — a hill is reshaped, not worn away.
Heightfield erodeThermally(
  Heightfield field, {

  /// The steepest step between neighbours, in metres.
  double talus = 0.6,

  /// The 0..1 share of the excess over [talus] that moves in a pass.
  double rate = 0.5,
  int passes = 30,
}) {
  final w = field.columns;
  final h = field.rows;
  final heights = field.copyOfSamples();
  final moved = Float32List(w * h);
  const offsets = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];
  for (var pass = 0; pass < passes; pass++) {
    moved.fillRange(0, moved.length, 0.0);
    for (var z = 0; z < h; z++) {
      for (var x = 0; x < w; x++) {
        final here = heights[z * w + x];
        // The total excess over every neighbour lower by more than the
        // talus, shared out in proportion to each one's.
        var total = 0.0;
        var steepest = 0.0;
        for (final (dx, dz) in offsets) {
          final nx = x + dx, nz = z + dz;
          if (nx < 0 || nx >= w || nz < 0 || nz >= h) continue;
          final drop = here - heights[nz * w + nx];
          if (drop > talus) {
            total += drop - talus;
            steepest = math.max(steepest, drop - talus);
          }
        }
        if (total <= 0.0) continue;
        final away = rate * steepest / 2.0;
        moved[z * w + x] -= away;
        for (final (dx, dz) in offsets) {
          final nx = x + dx, nz = z + dz;
          if (nx < 0 || nx >= w || nz < 0 || nz >= h) continue;
          final drop = here - heights[nz * w + nx];
          if (drop > talus) {
            moved[nz * w + nx] += away * (drop - talus) / total;
          }
        }
      }
    }
    for (var i = 0; i < heights.length; i++) {
      heights[i] += moved[i];
    }
  }
  return _like(field, heights);
}

/// [field] after rain: [droplets] drops, each set down by [seed] somewhere
/// on the field, running downhill, picking up ground where it runs fast and
/// steep and leaving it where it slows — gullies cut into the slopes and
/// fans of silt at their feet.
///
/// **Hydraulic erosion, droplet by droplet**, after Hans Theobald Beyer's
/// particle model: a drop keeps [inertia] of the way it was going against
/// the slope under it, carries up to `capacity × speed × slope` of ground,
/// takes [erosion] of what it could still carry and gives back [deposition]
/// of what it carries over that, slows to the speed the drop it fell would
/// give it, and dries by [evaporation] a step for [life] steps. Whatever a
/// drop still carries when it dries, or runs off the field, is set down
/// where it is, so the ground's total is what it was.
///
/// The same seed, the same gullies: every chance comes from [GameRandom].
Heightfield erodeHydraulically(
  Heightfield field, {
  required int seed,
  int droplets = 4000,
  int life = 40,

  /// The 0..1 share of its old direction a drop keeps against the slope.
  double inertia = 0.05,

  /// A unitless multiplier: a drop carries `capacity × speed × slope`.
  double capacity = 4.0,

  /// The 0..1 share of what a drop could still carry that it takes.
  double erosion = 0.3,

  /// The 0..1 share of what a drop carries over its limit that it sets down.
  double deposition = 0.3,

  /// The 0..1 share of a drop's water that dries each step.
  double evaporation = 0.02,

  /// A unitless multiplier on the fall a drop's squared speed grows by.
  double gravity = 4.0,
}) {
  final w = field.columns;
  final h = field.rows;
  final heights = field.copyOfSamples();
  final random = GameRandom(seed);

  // Height and slope at a point between samples, bilinearly.
  ({double height, double gx, double gz}) at(double px, double pz) {
    final x = px.floor().clamp(0, w - 2);
    final z = pz.floor().clamp(0, h - 2);
    final u = px - x, v = pz - z;
    final a = heights[z * w + x], b = heights[z * w + x + 1];
    final c = heights[(z + 1) * w + x], d = heights[(z + 1) * w + x + 1];
    return (
      height:
          a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v,
      gx: (b - a) * (1 - v) + (d - c) * v,
      gz: (c - a) * (1 - u) + (d - b) * u,
    );
  }

  // Adds [amount] at a point, shared among its four samples by nearness.
  void add(double px, double pz, double amount) {
    final x = px.floor().clamp(0, w - 2);
    final z = pz.floor().clamp(0, h - 2);
    final u = (px - x).clamp(0.0, 1.0), v = (pz - z).clamp(0.0, 1.0);
    heights[z * w + x] += amount * (1 - u) * (1 - v);
    heights[z * w + x + 1] += amount * u * (1 - v);
    heights[(z + 1) * w + x] += amount * (1 - u) * v;
    heights[(z + 1) * w + x + 1] += amount * u * v;
  }

  for (var drop = 0; drop < droplets; drop++) {
    var px = random.nextDouble() * (w - 1);
    var pz = random.nextDouble() * (h - 1);
    var dx = 0.0, dz = 0.0;
    var speed = 1.0, water = 1.0, carried = 0.0;
    for (var step = 0; step < life; step++) {
      final here = at(px, pz);
      dx = dx * inertia - here.gx * (1 - inertia);
      dz = dz * inertia - here.gz * (1 - inertia);
      final length = math.sqrt(dx * dx + dz * dz);
      if (length < 1e-9) break;
      dx /= length;
      dz /= length;
      final nx = px + dx, nz = pz + dz;
      if (nx < 0 || nx > w - 1 || nz < 0 || nz > h - 1) break;
      final fall = here.height - at(nx, nz).height;
      final limit = math.max(-fall, 0.01) * speed * water * capacity;
      if (fall < 0.0 || carried > limit) {
        // Uphill, or more than it can hold: set some down — uphill, only
        // as much as fills the rise, so a drop cannot build a wall.
        final down = fall < 0.0
            ? math.min(-fall, carried)
            : (carried - limit) * deposition;
        carried -= down;
        add(px, pz, down);
      } else {
        final up = math.min((limit - carried) * erosion, fall);
        carried += up;
        add(px, pz, -up);
      }
      speed = math.sqrt(math.max(0.0, speed * speed + fall * gravity));
      water *= 1 - evaporation;
      px = nx;
      pz = nz;
    }
    add(px.clamp(0.0, w - 1.0), pz.clamp(0.0, h - 1.0), carried);
  }
  return _like(field, heights);
}

Heightfield _like(Heightfield field, Float32List heights) => Heightfield(
  columns: field.columns,
  rows: field.rows,
  cellSize: field.cellSize,
  heights: heights,
  origin: field.origin.clone(),
);
