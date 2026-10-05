/// The way across a navigation mesh: which polygons, then which corners.
///
/// ## Two searches, one after the other
///
/// A* over the polygons finds the corridor — the chain of polygons from the
/// start to the goal, each sharing an edge with the next. The edges they share
/// are portals, and the funnel pulls a string through them from the start to
/// the goal; where the string bends round a portal's end is a corner a body
/// walks to. Inside the corridor every polygon is convex, so a straight line
/// from one corner to the next stays on the mesh.
///
/// ## Why the costs are whole numbers
///
/// A route has to be the same on every machine a run is replayed on, or an
/// agent turns left on one and right on the other. Each leg's length is a
/// square root, which IEEE 754 rounds exactly, and is then counted in whole
/// millimetres; the open list compares integers and breaks ties by the order
/// polygons were pushed, which is the mesh's own order. Nothing depends on
/// the iteration order of a map.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../cell_heap.dart';
import '../jump_links.dart';
import 'mesh_links.dart';
import 'navmesh.dart';

/// The polygons a route crosses and the corners a body walks between.
final class NavMeshRoute {
  const NavMeshRoute._(
    this.corridor,
    this.points, {
    required this.jumps,
    required this.complete,
  });

  /// The polygons from the start's to the last one reached, each sharing an
  /// edge with the next.
  final List<int> corridor;

  /// Where to walk: the start, every corner the route bends round, and the
  /// end. Two points when nothing is in the way.
  final List<Vector3> points;

  /// Where the route jumps: each `i` here makes the leg from `points[i]` to
  /// `points[i + 1]` a [NavMeshLink]'s flight rather than a walk. Empty for
  /// a route found without a reach.
  final List<int> jumps;

  /// False when the goal cannot be reached from the start. The route then
  /// ends at the point nearest the goal on the polygon nearest it, so a body
  /// that follows it gets as close as there is a way to — a monster at the
  /// foot of a step it cannot climb, not a monster standing still.
  final bool complete;

  /// How far a body walks along [points], in metres.
  double get length => Iterable<int>.generate(
    points.length - 1,
  ).fold(0.0, (sum, i) => sum + points[i].distanceTo(points[i + 1]));
}

/// The route from [from] to [to] over [mesh], or null when [from] is not over
/// any polygon.
///
/// [costOf] prices a metre of each area — see [NavArea] — and is never under
/// one, which keeps the straight distance to the goal a guess that never
/// overestimates; an area it prices at infinity is not walked at all.
///
/// [jumps] is the body's own reach: the mesh's [NavMesh.links] it takes are
/// the ones within it, each priced as the length of its flight. Without it
/// the route walks.
NavMeshRoute? findRoute(
  NavMesh mesh,
  Vector3 from,
  Vector3 to, {
  double Function(int area)? costOf,
  JumpReach? jumps,
}) {
  final start = mesh.polygonAt(from);
  if (start < 0) return null;
  final goal = mesh.polygonAt(to);
  final price = costOf ?? (_) => 1.0;

  final count = mesh.polygonCount;
  // Each polygon is entered at one point — the midpoint of the portal it was
  // last reached through more cheaply — and priced from there.
  final entry = Float64List(count * 3);
  final cost = Int64List(count)..fillRange(0, count, -1);
  final parent = Int32List(count)..fillRange(0, count, -1);
  // The link a polygon was last reached by, or −1 for a walk.
  final via = Int32List(count)..fillRange(0, count, -1);
  final closed = Uint8List(count);
  final open = CellHeap();

  void enter(int polygon, double x, double y, double z) {
    entry[polygon * 3] = x;
    entry[polygon * 3 + 1] = y;
    entry[polygon * 3 + 2] = z;
  }

  int millimetres(double dx, double dy, double dz) =>
      (math.sqrt(dx * dx + dy * dy + dz * dz) * 1000.0).round();

  int guess(int polygon) => millimetres(
    to.x - entry[polygon * 3],
    to.y - entry[polygon * 3 + 1],
    to.z - entry[polygon * 3 + 2],
  );

  enter(start, from.x, from.y, from.z);
  cost[start] = 0;
  open.push(start, guess(start));
  // Nearest the goal so far, by the guess, for a route that cannot arrive.
  var nearest = start;
  var nearestGuess = guess(start);

  final a = Vector3.zero();
  final b = Vector3.zero();
  while (!open.isEmpty) {
    final p = open.pop();
    if (closed[p] != 0) continue;
    closed[p] = 1;
    if (p == goal) break;
    final h = guess(p);
    if (h < nearestGuess) (nearest, nearestGuess) = (p, h);

    final perMetre = price(mesh.areaOf(p));
    final n = mesh.polygonVertexCount(p);
    for (var k = 0; k < n; k++) {
      final q = mesh.neighbourAt(p, k);
      if (q < 0 || closed[q] != 0) continue;
      if (price(mesh.areaOf(q)).isInfinite) continue;
      mesh.vertexAt(mesh.polygonVertex(p, k), a);
      mesh.vertexAt(mesh.polygonVertex(p, (k + 1) % n), b);
      final mx = (a.x + b.x) * 0.5;
      final my = (a.y + b.y) * 0.5;
      final mz = (a.z + b.z) * 0.5;
      final leg = millimetres(
        mx - entry[p * 3],
        my - entry[p * 3 + 1],
        mz - entry[p * 3 + 2],
      );
      final g = cost[p] + (leg * perMetre).round();
      if (cost[q] >= 0 && cost[q] <= g) continue;
      cost[q] = g;
      parent[q] = p;
      via[q] = -1;
      enter(q, mx, my, mz);
      open.push(q, g + guess(q));
    }

    if (jumps == null) continue;
    for (final i in mesh.linksFrom(p)) {
      final link = mesh.links[i];
      final q = link.to;
      if (closed[q] != 0 || price(mesh.areaOf(q)).isInfinite) continue;
      if (!jumps.takes(rise: link.rise, gap: link.gap)) continue;
      final run = millimetres(
        link.start.x - entry[p * 3],
        link.start.y - entry[p * 3 + 1],
        link.start.z - entry[p * 3 + 2],
      );
      final flight = millimetres(
        link.end.x - link.start.x,
        link.end.y - link.start.y,
        link.end.z - link.start.z,
      );
      final g = cost[p] + (run * perMetre).round() + flight;
      if (cost[q] >= 0 && cost[q] <= g) continue;
      cost[q] = g;
      parent[q] = p;
      via[q] = i;
      enter(q, link.end.x, link.end.y, link.end.z);
      open.push(q, g + guess(q));
    }
  }

  final complete = goal >= 0 && closed[goal] != 0;
  final last = complete ? goal : nearest;
  final corridor = <int>[];
  for (var p = last; p >= 0; p = parent[p]) {
    corridor.add(p);
  }
  final polygons = corridor.reversed.toList(growable: false);

  final end = Vector3.zero();
  if (complete) {
    end.setFrom(to);
  } else {
    mesh.closestPointOn(last, to, end);
  }

  // Walked stretches between jumps, each pulled tight on its own.
  final points = <Vector3>[];
  final jumpsAt = <int>[];
  var stretch = <int>[polygons.first];
  var stretchStart = from.clone();
  for (var i = 1; i < polygons.length; i++) {
    final link = via[polygons[i]];
    if (link < 0) {
      stretch.add(polygons[i]);
      continue;
    }
    points.addAll(
      _pullString(mesh, stretch, stretchStart, mesh.links[link].start.clone()),
    );
    jumpsAt.add(points.length - 1);
    stretch = <int>[polygons[i]];
    stretchStart = mesh.links[link].end.clone();
  }
  points.addAll(_pullString(mesh, stretch, stretchStart, end));

  return NavMeshRoute._(
    polygons,
    points,
    jumps: jumpsAt,
    complete: complete,
  );
}

/// Twice the signed area of `apex → a → b` in plan: positive when it turns
/// left, the way every polygon of the mesh runs.
double _turn(Vector3 apex, Vector3 a, Vector3 b) =>
    (a.x - apex.x) * (b.z - apex.z) - (a.z - apex.z) * (b.x - apex.x);

bool _samePlace(Vector3 a, Vector3 b) => a.x == b.x && a.z == b.z;

/// The corners of the shortest line from [start] to [end] through the
/// portals between [corridor]'s polygons.
///
/// The funnel is two legs from the apex, one to each side of the corridor.
/// Each portal narrows a leg if its end is inside the funnel; an end that
/// crosses the other leg means the line bends round that leg's end, which
/// becomes a corner and the new apex, and the walk starts again from the
/// portal where it was set.
List<Vector3> _pullString(
  NavMesh mesh,
  List<int> corridor,
  Vector3 start,
  Vector3 end,
) {
  // Facing out of a polygon across its edge `k`, corner `k + 1` is on the
  // left: the polygon turns left, so its inside is on the left of `k → k+1`.
  final portals = <(Vector3, Vector3)>[(start, start)];
  for (var i = 0; i + 1 < corridor.length; i++) {
    final p = corridor[i];
    final n = mesh.polygonVertexCount(p);
    final k = Iterable<int>.generate(
      n,
    ).firstWhere((k) => mesh.neighbourAt(p, k) == corridor[i + 1]);
    final left = Vector3.zero();
    final right = Vector3.zero();
    mesh.vertexAt(mesh.polygonVertex(p, (k + 1) % n), left);
    mesh.vertexAt(mesh.polygonVertex(p, k), right);
    portals.add((left, right));
  }
  portals.add((end, end));

  final points = <Vector3>[start];
  var apex = start;
  var left = start;
  var right = start;
  var apexAt = 0;
  var leftAt = 0;
  var rightAt = 0;
  for (var i = 1; i < portals.length; i++) {
    final (l, r) = portals[i];

    if (_turn(apex, right, r) >= 0.0) {
      if (_samePlace(apex, right) || _turn(apex, left, r) < 0.0) {
        (right, rightAt) = (r, i);
      } else {
        points.add(left.clone());
        (apex, apexAt) = (left, leftAt);
        (left, leftAt, right, rightAt) = (apex, apexAt, apex, apexAt);
        i = apexAt;
        continue;
      }
    }

    if (_turn(apex, left, l) <= 0.0) {
      if (_samePlace(apex, left) || _turn(apex, right, l) > 0.0) {
        (left, leftAt) = (l, i);
      } else {
        points.add(right.clone());
        (apex, apexAt) = (right, rightAt);
        (left, leftAt, right, rightAt) = (apex, apexAt, apex, apexAt);
        i = apexAt;
        continue;
      }
    }
  }
  if (!_samePlace(points.last, end)) points.add(end);
  return points;
}
