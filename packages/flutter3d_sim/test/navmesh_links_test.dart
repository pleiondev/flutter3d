/// Jumps between polygons of a navigation mesh, and routes that take them.
///
///     dart test test/navmesh_links_test.dart
///
/// A link is only worth having where walking does not get there, and only
/// where the body can actually make the jump: across a pit, up onto a
/// ledge, down off it. Through a wall, round a pillar or across the floor a
/// body already walks, there must be none — a link there sends an agent
/// leaping at a wall, or hopping where it could have stepped.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Two platforms either side of a pit a metre and a half wide.
List<Brush> _pit() => <Brush>[
  _box(-6, -1, -2, -0.75, 0, 2),
  _box(0.75, -1, -2, 6, 0, 2),
];

/// The same, three and a half metres wide: past [_reach] on the flat, and
/// within what it covers dropping a fall's depth, so the scan looks across
/// it and the reach has to refuse it.
List<Brush> _widePit() => <Brush>[
  _box(-6, -1, -2, -1.75, 0, 2),
  _box(1.75, -1, -2, 6, 0, 2),
];

/// The pit, with its far side half a metre nearer along the north half:
/// the jump across is shorter there than where the scan meets it first.
List<Brush> _notchedPit() => <Brush>[
  _box(-6, -1, -2, -0.75, 0, 2),
  _box(1.25, -1, -2, 6, 0, 0),
  _box(0.75, -1, 0, 6, 0, 2),
];

/// A floor and a ledge eight tenths of a metre up from it: past a step,
/// within a jump.
List<Brush> _ledge() => <Brush>[
  _box(-4, -1, -2, 0, 0, 2),
  _box(0, -1, -2, 4, 0.8, 2),
];

/// Two rooms either side of a wall three metres tall, with no door.
List<Brush> _wall() => <Brush>[
  _box(-5, -1, -2, 5, 0, 2),
  _box(-0.25, 0, -2, 0.25, 3, 2),
];

/// Ten metres square with a pillar in the middle: one floor, walked
/// everywhere.
List<Brush> _pillar() => <Brush>[
  _box(-5, -1, -5, 5, 0, 5),
  _box(-1, 0, -1, 1, 3, 1),
];

/// Clears three and a half metres on the flat and lands nine tenths of a
/// metre up.
const JumpReach _reach = JumpReach(jumpSpeed: 6, gravity: 20, runSpeed: 6);

/// Clears a metre on the flat: not the pit.
const JumpReach _hop = JumpReach(jumpSpeed: 6, gravity: 20, runSpeed: 1.6);

void main() {
  group('a pit', () {
    final walked = NavMesh.bake(_pit());
    final jumped = NavMesh.bake(_pit(), jumps: _reach);
    final from = Vector3(-4, 0, 0);
    final to = Vector3(4, 0, 0);

    test('is no way across for a mesh baked without a reach', () {
      expect(walked.links, isEmpty);
      expect(walked.route(from, to, jumps: _reach)!.complete, isFalse);
    });

    test('is linked both ways for one baked with a reach', () {
      final sides = jumped.links.map((l) => (l.start.x < 0, l.end.x < 0));
      expect(sides, containsAll(<(bool, bool)>[(true, false), (false, true)]));
      for (final link in jumped.links) {
        expect(link.rise, closeTo(0.0, 1e-9));
        expect(link.end.z, link.start.z);
        expect(_reach.takes(rise: link.rise, gap: link.gap), isTrue);
      }
    });

    test('is jumped by a route given the reach, once, across the pit', () {
      final route = jumped.route(from, to, jumps: _reach)!;
      expect(route.complete, isTrue);
      expect(route.jumps, hasLength(1));
      final i = route.jumps.single;
      expect(route.points[i].x, lessThan(-0.75));
      expect(route.points[i + 1].x, greaterThan(0.75));
    });

    test('is not jumped by a body whose reach falls short', () {
      // Mutation: taking every link the mesh has, whatever the body's reach,
      // sends the short hop into the pit.
      final route = jumped.route(from, to, jumps: _hop)!;
      expect(route.complete, isFalse);
      expect(route.jumps, isEmpty);
    });

    test('narrower further along is jumped where it is narrowest', () {
      final mesh = NavMesh.bake(_notchedPit(), jumps: _reach);
      final pairs = mesh.links.map((l) => (l.from, l.to)).toList();
      expect(pairs.toSet(), hasLength(pairs.length), reason: 'one per pair');
      final across = mesh.links.where((l) => l.start.x < 0).toList();
      expect(across, isNotEmpty);
      // Three metres between where a body may stand at the north end, three
      // and a half at the south, both within the reach. Mutation: keeping
      // the longer of two jumps between one pair keeps the first the scan
      // met, at the south end.
      for (final link in across) {
        expect(link.gap, closeTo(3.0, 1e-9));
        expect(link.end.z, greaterThan(0.0));
      }
    });

    test('too wide for the reach is not linked at all', () {
      // Mutation: linking whatever the scan lands on, without asking the
      // reach, links it.
      expect(NavMesh.bake(_widePit(), jumps: _reach).links, isEmpty);
    });

    test('is not jumped by a route given no reach at all', () {
      expect(jumped.route(from, to)!.complete, isFalse);
    });

    test('bakes the same links from the brushes in another order', () {
      expect(
        NavMesh.bake(_pit().reversed, jumps: _reach).digest,
        jumped.digest,
      );
      // Mutation: leaving the links out of the digest makes the two meshes
      // one number.
      expect(jumped.digest, isNot(walked.digest));
    });
  });

  group('a ledge', () {
    final mesh = NavMesh.bake(_ledge(), jumps: _reach);

    test('is jumped up onto, and down off', () {
      final up = mesh.route(
        Vector3(-3, 0, 0),
        Vector3(3, 0.8, 0),
        jumps: _reach,
      )!;
      expect(up.complete, isTrue);
      expect(up.jumps, hasLength(1));
      expect(
        up.points[up.jumps.single + 1].y - up.points[up.jumps.single].y,
        closeTo(0.8, 0.11),
      );
      final down = mesh.route(
        Vector3(3, 0.8, 0),
        Vector3(-3, 0, 0),
        jumps: _reach,
      )!;
      expect(down.complete, isTrue);
      expect(down.jumps, hasLength(1));
    });

    test('is too high for a reach that does not clear it', () {
      const low = JumpReach(jumpSpeed: 3, gravity: 20, runSpeed: 6);
      final route = mesh.route(
        Vector3(-3, 0, 0),
        Vector3(3, 0.8, 0),
        jumps: low,
      )!;
      expect(route.complete, isFalse);
    });
  });

  test('a wall taller than the reach is no link', () {
    // Mutation: not looking for something solid at the body's height lets
    // the scan fly through the wall and land in the other room.
    expect(NavMesh.bake(_wall(), jumps: _reach).links, isEmpty);
  });

  test('one floor walked everywhere has no links on it', () {
    // Mutation: counting the eroded strip by the pillar as a gap links the
    // floor to itself round every corner.
    expect(NavMesh.bake(_pillar(), jumps: _reach).links, isEmpty);
  });
}
