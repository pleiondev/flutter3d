/// The moves a grid cannot express: a jump across a gap, a jump up onto a
/// ledge.
///
/// ## What the grid says, and what it cannot
///
/// [NavGrid.canMove] is a walk: a rise of at most a step, a drop of at most
/// a fall. Everything a platformer is made of lives outside that — the pit
/// between two platforms, the ledge a metre up — and a flow field over the
/// grid alone reports every one of them as "no way there". So an enemy that
/// chases the player along a level built of gaps stands at the first edge
/// and waits.
///
/// A jump link is one extra edge: from a cell at an edge, across cells the
/// walk refuses, to a cell on the far side, with the rise and the horizontal
/// gap written on it. The field treats it as a step of its own cost, and a
/// brain steering along the field is told when the next step is a jump.
///
/// ## Baked from the geometry, taken by the body
///
/// Links are baked once from the grid with the most capable [JumpReach] a
/// level's bodies will have, and each records the rise and gap it needs. A
/// field for a particular body filters them by that body's own reach, so a
/// heavy guard with a short hop is never sent across a gap the light one
/// clears — the same one-grid-many-fields arrangement the clearance and
/// headroom filters already use.
///
/// ## What is deliberately not here
///
/// No check for headroom along the arc, so a link can pass under a lintel
/// too low for the jump's apex; no landing on a moving platform, since the
/// grid is baked from architecture; and no link that needs a run-up longer
/// than the take-off cell, because the reach assumes the body leaves the
/// ground at its running speed.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart' show MovementTuning;

import 'nav_grid.dart';

/// How far a body can jump, from the three numbers that decide it.
///
/// A value class rather than the whole `MovementTuning`, because this package
/// is asked by a field that keys its cache on it, and two bodies that jump
/// alike should share a field however else they differ.
final class JumpReach {
  const JumpReach({
    required this.jumpSpeed,
    required this.gravity,
    required this.runSpeed,
  }) : assert(gravity > 0.0, 'a body that never comes down does not land');

  /// The reach of a body that moves by [tuning], at its walking pace.
  factory JumpReach.of(MovementTuning tuning) => JumpReach(
    jumpSpeed: tuning.jumpSpeed,
    gravity: tuning.gravity,
    runSpeed: tuning.walkSpeed,
  );

  /// Upward speed at take-off, metres per second.
  final double jumpSpeed;

  /// Metres per second squared, positive.
  final double gravity;

  /// Horizontal speed carried through the air. Air control is not modelled:
  /// the body leaves the ground at this speed and keeps it.
  final double runSpeed;

  /// The highest ledge this reach lands on: `v² / 2g`.
  double get maxRise => jumpSpeed * jumpSpeed / (2.0 * gravity);

  /// The horizontal distance covered while landing [rise] metres above the
  /// take-off (negative for below), or null when the apex is lower than that.
  ///
  /// The later root of `rise = v·t − ½g·t²`: the body passes the landing
  /// height on the way up and again on the way down, and it is the way down
  /// that lands.
  double? gapFor(double rise) {
    final discriminant = jumpSpeed * jumpSpeed - 2.0 * gravity * rise;
    if (discriminant < 0.0) return null;
    final t = (jumpSpeed + math.sqrt(discriminant)) / gravity;
    return runSpeed * t;
  }

  /// Whether a jump of [gap] metres landing [rise] metres higher is within
  /// this reach.
  bool takes({required double rise, required double gap}) {
    final reach = gapFor(rise);
    return reach != null && reach >= gap;
  }

  @override
  bool operator ==(Object other) =>
      other is JumpReach &&
      other.jumpSpeed == jumpSpeed &&
      other.gravity == gravity &&
      other.runSpeed == runSpeed;

  @override
  int get hashCode => Object.hash(jumpSpeed, gravity, runSpeed);

  @override
  String toString() =>
      'JumpReach(v=$jumpSpeed, g=$gravity, run=$runSpeed, '
      'maxRise=${maxRise.toStringAsFixed(2)})';
}

/// One jump the grid allows: from a cell, to a cell, and what it costs a body.
final class JumpLink {
  const JumpLink({
    required this.from,
    required this.to,
    required this.rise,
    required this.gap,
  });

  /// The take-off cell, and the landing cell.
  final int from;
  final int to;

  /// Floor height of [to] less floor height of [from]. Positive is up.
  final double rise;

  /// Horizontal metres between the two cells' centres.
  final double gap;

  @override
  String toString() =>
      'JumpLink($from -> $to, rise ${rise.toStringAsFixed(2)}, '
      'gap ${gap.toStringAsFixed(2)})';
}

/// Finds every jump [reach] can make between cells of [grid].
///
/// From each walkable cell, in each of the eight directions, the scan steps
/// outward across cells the walk refuses — no floor, or a rise or drop
/// outside [NavGrid.canMove] — until it meets a cell the walk would accept
/// as a landing or runs out of reach. A cell the walk could have reached
/// directly earns no link, because a link there is only a more expensive
/// step; and a scan that meets a wall — a rise beyond the reach — stops,
/// since nothing beyond a wall is reached by jumping at it.
///
/// Deterministic: cells and directions in a fixed order, so two bakes of the
/// same grid are the same list.
List<JumpLink> bakeJumpLinks(NavGrid grid, JumpReach reach) {
  final links = <JumpLink>[];
  if (grid.isEmpty) return links;

  final columns = grid.columns;
  final rows = grid.rows;
  final cell = grid.cellSize;
  final maxRise = reach.maxRise;
  // The farthest any jump lands, in cells: a drop of the grid's own maximum
  // fall is the longest flight the scan is allowed to consider.
  final longest = reach.gapFor(-grid.maxFall) ?? reach.gapFor(0.0) ?? 0.0;
  final maxCells = (longest / cell).ceil();
  if (maxCells < 1) return links;

  const directions = <(int, int)>[
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
  ];

  for (var cz = 0; cz < rows; cz++) {
    for (var cx = 0; cx < columns; cx++) {
      final from = cz * columns + cx;
      if (!grid.isWalkable(from)) continue;
      final fromFloor = grid.floorAt(from);

      for (final (dx, dz) in directions) {
        final stride = cell * math.sqrt((dx * dx + dz * dz).toDouble());
        // The first cell out decides whether this is an edge at all: a cell
        // the walk takes is not one, and a link past it would only be a
        // longer way of walking.
        var crossedRefusal = false;
        for (var k = 1; k <= maxCells; k++) {
          final nx = cx + dx * k;
          final nz = cz + dz * k;
          if (nx < 0 || nx >= columns || nz < 0 || nz >= rows) break;
          final to = nz * columns + nx;
          final walkable = grid.isWalkable(to);
          final rise = walkable ? grid.floorAt(to) - fromFloor : 0.0;

          if (walkable && grid.canMove(from, to)) {
            // Reachable by walking from the take-off cell itself. As the
            // first cell out, this direction is no edge; further out, it is
            // the landing the walk refused to reach directly, so it earns the
            // link — only if something between was actually refused.
            if (k == 1) break;
            if (!crossedRefusal) break;
            final gap = stride * k;
            if (reach.takes(rise: rise, gap: gap)) {
              links.add(JumpLink(from: from, to: to, rise: rise, gap: gap));
            }
            break;
          }

          if (walkable && rise > grid.stepHeight) {
            // A ledge. Reachable by jumping when the reach clears it, and a
            // wall — nothing beyond it is reached by jumping at it — when it
            // does not.
            final gap = stride * k;
            if (rise <= maxRise && reach.takes(rise: rise, gap: gap)) {
              links.add(JumpLink(from: from, to: to, rise: rise, gap: gap));
            }
            break;
          }

          // No floor, or a drop too far to walk down: the gap continues.
          // A drop the reach cannot land past its own limit ends the scan
          // rather than seeding a link onto a cell it would not survive.
          if (walkable && rise < -grid.maxFall) break;
          crossedRefusal = true;
        }
      }
    }
  }
  return links;
}
