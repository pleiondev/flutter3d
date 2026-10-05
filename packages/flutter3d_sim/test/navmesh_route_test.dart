/// Routes over a navigation mesh: the corridor A* finds and the corners the
/// funnel pulls out of it.
///
///     dart test test/navmesh_route_test.dart
///
/// The claim every route here has to meet is that a body walking straight
/// from each point to the next stays on the mesh; a corner cut through a
/// pillar or a wall breaks it. The rest is what each scene is for: a pillar
/// to go round, a doorway to go through, a step too tall, a ramp up, and mud
/// that is dearer than going round it.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Ten metres square, its top at nought.
List<Brush> _floor() => <Brush>[_box(-5, -1, -5, 5, 0, 5)];

/// The floor with a pillar two metres square in the middle of it.
List<Brush> _pillar() => <Brush>[..._floor(), _box(-1, 0, -1, 1, 3, 1)];

/// Two rooms either side of a wall, joined by a doorway two metres wide.
List<Brush> _rooms() => <Brush>[
  _box(-6, -1, -3, 6, 0, 3),
  _box(0, 0, -3, 0.5, 3, -1),
  _box(0, 0, 1, 0.5, 3, 3),
  _box(0, 2.5, -1, 0.5, 3, 1),
];

/// The two rooms with a dais a metre tall in the east one, too tall to
/// climb: a goal on it is reached by nothing.
List<Brush> _dais() => <Brush>[..._rooms(), _box(3, 0, -1, 5, 1, 1)];

/// The floor with a walkway two metres wide three metres over it.
List<Brush> _walkway() => <Brush>[..._floor(), _box(-1, 2.8, -5, 1, 3, 5)];

/// A floor and a step up from it taller than an agent climbs.
List<Brush> _tallStep() => <Brush>[
  _box(-2, -1, -4, 2, 0, 0),
  _box(-2, -1, 0, 2, 0.6, 4),
];

/// A floor, a ramp climbing a metre and a half over six, and the platform at
/// its top.
List<Brush> _ramp() => <Brush>[
  _box(-2, -1, -4, 2, 0, 0),
  Brush(
    centre: Vector3(0, 0.75, 3),
    size: Vector3(4, 1.5, 6),
    ramp: WedgeUphill.positiveZ,
  ),
  _box(-2, -1, 6, 2, 1.5, 10),
];

/// The floor with a strip of mud across most of it, x from −1 to 1, z from
/// −5 to 3: firm ground goes round its north end.
const int _mud = 2;
List<Brush> _mire() => <Brush>[
  _box(-5, -1, -5, -1, 0, 5),
  _box(1, -1, -5, 5, 0, 5),
  _box(-1, -1, 3, 1, 0, 5),
  Brush(centre: Vector3(0, -0.5, -1), size: Vector3(2, 1, 8), material: 'mud'),
];

int _areaOf(Brush brush) => brush.material == 'mud' ? _mud : NavArea.ground;

/// Whether `(x, z)` is on [mesh] in plan, allowing for the rounding of a
/// point that lies on an edge.
bool _onMesh(NavMesh mesh, double x, double z) {
  final at = Vector3(x, 0, z);
  final near = Vector3.zero();
  return Iterable<int>.generate(mesh.polygonCount).any((p) {
    mesh.closestPointOn(p, at, near);
    return (near.x - x).abs() < 1e-6 && (near.z - z).abs() < 1e-6;
  });
}

/// Every leg of [route], sampled every ten centimetres, is on the mesh.
void _expectWalkable(NavMesh mesh, NavMeshRoute route) {
  for (var i = 0; i + 1 < route.points.length; i++) {
    final a = route.points[i];
    final b = route.points[i + 1];
    final steps = (a.distanceTo(b) / 0.1).ceil();
    for (var s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final x = a.x + (b.x - a.x) * t;
      final z = a.z + (b.z - a.z) * t;
      expect(
        _onMesh(mesh, x, z),
        isTrue,
        reason: 'leg $i leaves the mesh at ($x, $z)',
      );
    }
  }
}

void main() {
  group('on a flat floor', () {
    final mesh = NavMesh.bake(_floor());

    test('a route is a straight line from the start to the goal', () {
      final route = mesh.route(Vector3(-3, 0, -3), Vector3(3, 0, 2))!;
      expect(route.complete, isTrue);
      expect(route.points, hasLength(2));
      expect(route.points.first, Vector3(-3, 0, -3));
      expect(route.points.last, Vector3(3, 0, 2));
    });

    test('a start off the mesh has no route', () {
      expect(mesh.route(Vector3(20, 0, 0), Vector3(0, 0, 0)), isNull);
    });
  });

  group('a pillar in the way', () {
    final mesh = NavMesh.bake(_pillar());
    final from = Vector3(-3, 0, 0.5);
    final to = Vector3(3, 0, 0.5);
    final route = mesh.route(from, to)!;

    test('is walked round, not through', () {
      expect(route.complete, isTrue);
      // Mutation: swapping a portal's left and right ends lets the string
      // straighten across the pillar, and the route is two points through
      // it.
      expect(route.points.length, greaterThan(2));
      _expectWalkable(mesh, route);
    });

    test('by the near side, hugging its corners', () {
      // Round the north side, the nearer: a metre of pillar and a body's
      // radius of erosion put the corners at z = 1.5 at most.
      for (final p in route.points.skip(1).take(route.points.length - 2)) {
        expect(p.z, inInclusiveRange(1.0, 2.0));
        expect(p.x.abs(), inInclusiveRange(1.0, 2.0));
      }
      // Pulled tight round the corners rather than walked through the middle
      // of each polygon: longer than the straight line, not by much.
      expect(route.length, lessThan(7.0));
      expect(route.length, greaterThan(from.distanceTo(to)));
    });
  });

  group('two rooms and a doorway', () {
    final mesh = NavMesh.bake(_rooms());

    test('the route goes through the doorway', () {
      final route = mesh.route(Vector3(-4, 0, -2), Vector3(4, 0, 2))!;
      expect(route.complete, isTrue);
      _expectWalkable(mesh, route);
      // The wall is at x from 0 to 0.5; wherever the route crosses it, it
      // is inside the doorway, a body's radius from its jambs.
      for (var i = 0; i + 1 < route.points.length; i++) {
        final a = route.points[i];
        final b = route.points[i + 1];
        if ((a.x - 0.25).sign == (b.x - 0.25).sign) continue;
        final z = a.z + (b.z - a.z) * (0.25 - a.x) / (b.x - a.x);
        expect(z, inInclusiveRange(-0.7, 0.7));
      }
    });
  });

  group('a dais nobody can climb', () {
    final mesh = NavMesh.bake(_dais());

    test('is walked to from the next room, as close as the floor goes', () {
      final route = mesh.route(Vector3(-4, 0, 0), Vector3(4, 1, 0))!;
      expect(route.complete, isFalse);
      // Mutation: never moving the nearest polygon on from the start's
      // leaves the route in the west room.
      expect(route.points.last.x, inInclusiveRange(2.0, 3.0));
      expect(route.points.last.y, closeTo(0.0, 0.11));
      _expectWalkable(mesh, route);
    });
  });

  group('a walkway over the floor', () {
    final mesh = NavMesh.bake(_walkway());

    test('a point is on the floor it is nearest in height', () {
      final up = mesh.polygonAt(Vector3(0, 3.1, 0));
      final down = mesh.polygonAt(Vector3(0, 0.1, 0));
      expect(up, isNonNegative);
      expect(down, isNonNegative);
      // Mutation: taking the first polygon over the point, whatever its
      // height, puts both on the same floor.
      expect(mesh.heightAt(up, 0, 0), closeTo(3.0, 0.11));
      expect(mesh.heightAt(down, 0, 0), closeTo(0.0, 0.11));
    });
  });

  group('a step too tall to climb', () {
    final mesh = NavMesh.bake(_tallStep());

    test('ends the route at its foot, as near the goal as there is a way', () {
      final route = mesh.route(Vector3(0, 0, -3), Vector3(0, 0.6, 2))!;
      // Mutation: reporting an unreached goal as reached, or ending the
      // route on the goal regardless, puts the end up on the step.
      expect(route.complete, isFalse);
      expect(route.points.last.y, closeTo(0.0, 0.11));
      expect(route.points.last.z, closeTo(-0.5, 0.26));
      expect(route.points.last.x, closeTo(0.0, 1e-9));
      _expectWalkable(mesh, route);
    });
  });

  group('a ramp', () {
    final mesh = NavMesh.bake(_ramp());

    test('is walked up to the platform at its top', () {
      final route = mesh.route(Vector3(0, 0, -3), Vector3(0, 1.5, 8))!;
      expect(route.complete, isTrue);
      _expectWalkable(mesh, route);
    });

    test('the floor before it and the platform after it are flat', () {
      // The floor, the ramp and the platform bake as one polygon whose
      // corners are at the floor's far end and the platform's; read off the
      // corners alone, the floor two metres from the ramp is a sixth of a
      // metre up and the platform two short of its end is as much down.
      // Mutation: answering with the corners' guess and not the column's
      // floor.
      final floor = mesh.polygonAt(Vector3(0, 0, -2));
      final platform = mesh.polygonAt(Vector3(0, 1.5, 8));
      expect(mesh.heightAt(floor, 0, -2), closeTo(0.0, 1e-9));
      expect(mesh.heightAt(platform, 0, 8), closeTo(1.5, 1e-9));
    });

    test('a point over it stands on the ramp at the ramp\'s height', () {
      // Halfway up: three metres in, three quarters of a metre high. A
      // column's floor is where the ramp is at the column's centre, rounded
      // up to a voxel: out by a cell's rise and a voxel at most.
      final at = Vector3(0, 0.75, 3);
      final p = mesh.polygonAt(at);
      expect(p, isNonNegative);
      // Mutation: taking the first corner's height for the whole polygon
      // rather than the fan's triangle puts it at the foot or the top.
      expect(mesh.heightAt(p, 0, 3), closeTo(0.75, 0.125 + 0.1 + 1e-9));
    });
  });

  group('mud across most of the floor', () {
    final mesh = NavMesh.bake(_mire(), areaOf: _areaOf);
    final from = Vector3(-3, 0, -2);
    final to = Vector3(3, 0, -2);

    test('is crossed when it costs what ground costs', () {
      final route = mesh.route(from, to)!;
      expect(route.complete, isTrue);
      expect(route.points, hasLength(2));
    });

    test('is walked round when a metre of it costs ten', () {
      final route = mesh.route(
        from,
        to,
        costOf: (area) => area == _mud ? 10.0 : 1.0,
      )!;
      expect(route.complete, isTrue);
      // Round the north end, some fourteen metres, against six with two of
      // them in mud: twelve at four a metre, twenty-four at ten.
      // The mud's own edge is not eroded — it is walkable, only dear — so
      // the route bends at its corner, z = 3.
      // Mutation: leaving the price out of a leg's cost goes through.
      expect(
        route.points.map((p) => p.z).reduce((a, b) => a > b ? a : b),
        greaterThanOrEqualTo(3.0),
      );
      expect(route.corridor.where((p) => mesh.areaOf(p) == _mud), isEmpty);
      _expectWalkable(mesh, route);
    });

    test('is never entered when it is priced at infinity', () {
      // From a start beside the mud to a goal on it: the route stops short.
      final route = mesh.route(
        from,
        Vector3(0, 0, -2),
        costOf: (area) => area == _mud ? double.infinity : 1.0,
      )!;
      expect(route.complete, isFalse);
      expect(route.corridor.where((p) => mesh.areaOf(p) == _mud), isEmpty);
    });
  });
}
