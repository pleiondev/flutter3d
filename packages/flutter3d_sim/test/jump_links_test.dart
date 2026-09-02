/// A route that exists only through the air.
///
///     dart test test/jump_links_test.dart
///
/// Two platforms with a pit between them, and a ledge a metre up: the grid
/// alone reports no way across either, a field with a reach that clears them
/// routes through a jump, and a field for a body whose hop is too short is
/// back to no way at all. The arithmetic of the reach is pinned first, since
/// everything else is only as right as it is.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _slab(double x0, double x1, double top, {double z = 0.0}) => Brush(
  centre: Vector3((x0 + x1) / 2, top - 0.5, z),
  size: Vector3(x1 - x0, 1.0, 6.0),
);

/// The shipped body: 8 m/s up, 24 m/s² down, 6 m/s along. Apex 1.33 m,
/// two thirds of a second in the air at the same height, four metres of gap.
const _runner = JumpReach(jumpSpeed: 8.0, gravity: 24.0, runSpeed: 6.0);

/// A body that barely leaves the ground.
const _hopper = JumpReach(jumpSpeed: 3.0, gravity: 24.0, runSpeed: 6.0);

void main() {
  group('a reach', () {
    test('lands a gap of run speed times the flight time', () {
      // Same height: t = 2v/g = 0.667 s, gap = 6 × 0.667 = 4 m.
      expect(_runner.gapFor(0.0), closeTo(4.0, 1e-9));
      expect(_runner.takes(rise: 0.0, gap: 3.9), isTrue);
      expect(_runner.takes(rise: 0.0, gap: 4.1), isFalse);
    });

    test('reaches higher for a shorter gap and further for a drop', () {
      expect(_runner.maxRise, closeTo(8.0 * 8.0 / 48.0, 1e-9));
      expect(_runner.gapFor(_runner.maxRise), closeTo(2.0, 1e-9));
      expect(_runner.gapFor(_runner.maxRise + 0.01), isNull);
      expect(_runner.gapFor(-2.0)!, greaterThan(4.0));
    });
  });

  group('across a pit', () {
    // Platform A from x = -10 to 0, a two-metre pit, platform B from 2 to 12.
    final level = <Brush>[_slab(-10.0, 0.0, 0.0), _slab(2.0, 12.0, 0.0)];

    test('the grid alone has no way over', () {
      final grid = NavGrid.bake(level);
      final field = FlowField(grid)..rebuild(Vector3(10.0, 0.0, 0.0));

      expect(grid.jumpLinks, isEmpty);
      expect(field.walkingDistanceTo(Vector3(-8.0, 0.0, 0.0)), isNull);
    });

    test('a bake with a reach finds the links, both ways', () {
      final grid = NavGrid.bake(level, jumps: _runner);

      expect(grid.jumpLinks, isNotEmpty);
      // The link recorded what it needs: level, and a gap of a few cells.
      for (final link in grid.jumpLinks) {
        expect(link.rise, closeTo(0.0, 1e-6));
        expect(link.gap, greaterThan(2.0));
        expect(link.gap, lessThanOrEqualTo(4.0));
      }
      final fromA = grid.jumpLinks.where(
        (l) => grid.centreOfCell(l.from).x < 0.0,
      );
      final fromB = grid.jumpLinks.where(
        (l) => grid.centreOfCell(l.from).x > 2.0,
      );
      expect(fromA, isNotEmpty, reason: 'A to B');
      expect(fromB, isNotEmpty, reason: 'B to A');
    });

    test('a body that clears it is routed through the air', () {
      final grid = NavGrid.bake(level, jumps: _runner);
      final field = FlowField(grid, jump: _runner)
        ..rebuild(Vector3(10.0, 0.0, 0.0));
      final out = Vector3.zero();
      final start = Vector3(-8.0, 0.0, 0.0);

      expect(field.walkingDistanceTo(start), isNotNull);
      expect(field.descend(start, out), isTrue);
      expect(out.x, greaterThan(0.0), reason: 'towards the pit');
      // Walking east along A the next step is a walk until the edge, where
      // it becomes the jump.
      expect(field.jumpAt(start), isNull);
      final edge = Vector3(-0.25, 0.0, 0.0);
      final link = field.jumpAt(edge);
      expect(link, isNotNull);
      expect(grid.centreOfCell(link!.to).x, greaterThan(2.0));
      expect(field.descend(edge, out), isTrue);
      expect(out.x, greaterThan(0.9), reason: 'aimed at the landing');
    });

    test('a body whose hop is too short is not offered the link', () {
      final grid = NavGrid.bake(level, jumps: _runner);
      final field = FlowField(grid, jump: _hopper)
        ..rebuild(Vector3(10.0, 0.0, 0.0));

      expect(field.walkingDistanceTo(Vector3(-8.0, 0.0, 0.0)), isNull);
      expect(field.jumpAt(Vector3(-0.25, 0.0, 0.0)), isNull);
    });

    test('and neither is a body that never jumps', () {
      final grid = NavGrid.bake(level, jumps: _runner);
      final field = FlowField(grid)..rebuild(Vector3(10.0, 0.0, 0.0));

      expect(field.walkingDistanceTo(Vector3(-8.0, 0.0, 0.0)), isNull);
    });

    test('a walk of the same length is preferred to a jump', () {
      // A third slab bridges the pit on the far side of z, so there is a walk
      // round as well as the jump across. The walk from the middle of A to the
      // middle of B is a long way round; from right beside the bridge it is
      // not, and there the field walks.
      final bridged = <Brush>[...level, _slab(-1.0, 3.0, 0.0, z: 4.0)];
      final grid = NavGrid.bake(bridged, jumps: _runner);
      final field = FlowField(grid, jump: _runner)
        ..rebuild(Vector3(2.5, 0.0, 4.0));

      expect(field.jumpAt(Vector3(-0.25, 0.0, 4.0)), isNull);
    });
  });

  group('onto a ledge', () {
    // Floor at 0 from -10 to 0, a ledge one metre up from 0 to 10.
    final level = <Brush>[_slab(-10.0, 0.0, 0.0), _slab(0.0, 10.0, 1.0)];

    test('is a jump up and a walk down', () {
      final grid = NavGrid.bake(level, jumps: _runner);
      final up = FlowField(grid, jump: _runner)
        ..rebuild(Vector3(8.0, 1.0, 0.0));
      final down = FlowField(grid, jump: _runner)
        ..rebuild(Vector3(-8.0, 0.0, 0.0));

      final foot = Vector3(-0.25, 0.0, 0.0);
      expect(up.walkingDistanceTo(foot), isNotNull);
      final link = up.jumpAt(foot);
      expect(link, isNotNull);
      expect(link!.rise, closeTo(1.0, 1e-6));

      final lip = Vector3(0.25, 1.0, 0.0);
      expect(down.walkingDistanceTo(lip), isNotNull);
      expect(down.jumpAt(lip), isNull, reason: 'a metre down is a drop');
    });

    test('too high a ledge is a wall', () {
      final tall = <Brush>[_slab(-10.0, 0.0, 0.0), _slab(0.0, 10.0, 2.0)];
      final grid = NavGrid.bake(tall, jumps: _runner);
      final field = FlowField(grid, jump: _runner)
        ..rebuild(Vector3(8.0, 2.0, 0.0));

      expect(grid.jumpLinks.where((l) => l.rise > 0.5), isEmpty);
      expect(field.walkingDistanceTo(Vector3(-8.0, 0.0, 0.0)), isNull);
    });
  });

  test('two bakes of the same level are the same links', () {
    final level = <Brush>[_slab(-10.0, 0.0, 0.0), _slab(2.0, 12.0, 0.5)];
    final a = NavGrid.bake(level, jumps: _runner).jumpLinks;
    final b = NavGrid.bake(level, jumps: _runner).jumpLinks;

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].from, b[i].from);
      expect(a[i].to, b[i].to);
      expect(a[i].gap, b[i].gap);
    }
  });

  test('navigation keeps one field per reach', () {
    final level = <Brush>[_slab(-10.0, 0.0, 0.0), _slab(2.0, 12.0, 0.0)];
    final navigation = Navigation.bake(Level(brushes: level), jumps: _runner)
      ..update(Vector3(10.0, 0.0, 0.0));
    final out = Vector3.zero();

    expect(
      navigation.steer(
        Vector3(-8.0, 0.0, 0.0),
        out,
        radius: 0.3,
        jump: _runner,
      ),
      isTrue,
    );
    expect(
      navigation.steer(Vector3(-8.0, 0.0, 0.0), out, radius: 0.3),
      isFalse,
    );
    expect(
      navigation.jumpAhead(
        Vector3(-0.25, 0.0, 0.0),
        radius: 0.3,
        jump: _runner,
      ),
      isNotNull,
    );
    expect(navigation.fields, hasLength(2));
  });
}
