/// One sweep of Dijkstra from where the player is, read by everything that
/// wants to get there.
///
/// ## Why not A\* per monster
///
/// Because `monster_system.dart` already wrote down the fact that decides it:
/// *"Nothing targets anything but the player."* With one goal, thirty A\*
/// searches compute thirty prefixes of the same tree. One sweep outward from
/// the goal gives every agent in the level its direction as an array lookup,
/// and the sweep only has to run again when the player crosses into a
/// different cell.
///
/// The sweep runs *from* the goal, so the stored direction points along the
/// descent — the parent link, recorded while relaxing. Nothing has to be
/// gradient-sampled afterwards, and a cell that was never reached keeps a zero
/// direction, which is how "there is no way there from here" is reported.
///
/// ## Several goals, still one sweep
///
/// A game with four players has four things to chase, and four fields would be
/// four sweeps that each answer "how far to *this* one" when the question a
/// monster asks is "how far to the nearest". A Dijkstra seeded with every goal
/// at cost zero answers that one directly: the frontiers grow from all of them
/// at once and meet halfway, and each cell is claimed by whichever goal
/// reaches it first. Which goal that was is recorded while relaxing, beside
/// the direction, so [sourceAt] tells an agent both which way to walk and who
/// it is walking to from the same lookup. Following the descent never changes
/// the answer — a cell's parent was claimed by the same goal — so a monster
/// does not switch targets half way down a corridor.
///
/// One goal is the same sweep with one seed, which is what [update] is.
///
/// ## One field per class of body
///
/// A field refuses cells its agent does not fit in, both across
/// ([NavGrid.clearanceAt]) and up ([NavGrid.headroomAt]). A single shared field
/// would have to pick one body: too wide and it walls the small monsters out of
/// corridors they fit in, too narrow and it marches the big ones into gaps they
/// do not. [Navigation] keeps one field per class and builds them on demand,
/// which is usually two or three for a whole game.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cell_heap.dart';
import 'jump_links.dart';
import 'nav_grid.dart';

/// The distance to the goal from everywhere, and which way is downhill.
final class FlowField {
  FlowField(
    this.grid, {
    this.minClearance = 1,
    this.minHeadroom = 0.0,
    this.jump,
    this.jumpMargin = 0.0,
  }) : _cost = Int32List(grid.cellCount),
       _dx = Int8List(grid.cellCount),
       _dz = Int8List(grid.cellCount),
       _link = Int32List(grid.cellCount),
       _source = Int8List(grid.cellCount) {
    // A fresh `Int32List` is zeros, and zero is a real cost meaning "you are
    // standing on the goal". Before the first sweep nothing is reachable.
    _cost.fillRange(0, _cost.length, unreachable);
    _link.fillRange(0, _link.length, -1);
    _source.fillRange(0, _source.length, -1);
  }

  /// The most goals one sweep takes: [_source] is a byte per cell.
  static const int maxGoals = 127;

  final NavGrid grid;

  /// How wide the body is, in cells. See [NavGrid.clearanceForRadius].
  final int minClearance;

  /// How tall the body is, in metres. Zero accepts anything the grid baked.
  final double minHeadroom;

  /// How far the body jumps, or null for one that never leaves the ground.
  ///
  /// Only the grid's [NavGrid.jumpLinks] this reach takes join the sweep, so
  /// a field for a short hop routes round a gap the long one crosses — and a
  /// grid baked without links makes this a number nobody reads.
  final JumpReach? jump;

  /// Metres added to every link's gap before the reach is asked, and it is
  /// the body's width: a link is measured centre to centre between two edge
  /// cells, but a body's centre stops a radius short of each edge, so the
  /// distance it actually flies is the link's gap plus its own diameter.
  final double jumpMargin;

  /// The cells a jump starts from or lands on, for this field's reach.
  ///
  /// **Held apart from [fits] because an edge never fits.** The clearance
  /// transform seeds every cell beside a drop with one, which is exactly
  /// the cell a jump leaves from and the one it lands on, so a field that
  /// asked the usual question of a link's ends would refuse every link a
  /// body wider than half a cell could take. A link's end has to be walkable
  /// under this body's head and nothing more: standing at the edge is the
  /// whole point of it.
  final Set<int> _linkEnds = <int>{};

  final Int32List _cost;
  final Int8List _dx;
  final Int8List _dz;

  /// The link a cell's downhill step is, as an index into the grid's list,
  /// or `-1` when the step is a walk and [_dx]/[_dz] say where.
  final Int32List _link;

  /// Which goal, by its index in the list the sweep was given, a cell's
  /// cheapest route ends at, or `-1` for a cell no route reaches.
  final Int8List _source;

  /// Integer costs, because a Dijkstra over floats accumulates a different
  /// total along paths of equal length and then picks between them by rounding
  /// error. 10 and 14 are the usual pair: 14/10 is within half a percent of √2.
  static const int _straight = 10;
  static const int _diagonal = 14;
  static const int unreachable = 1 << 29;

  /// What a jump costs over and above its distance: two cells' worth, so a
  /// walk of the same length is preferred and a link is taken only where the
  /// walk is longer or does not exist. A body in the air is a body that
  /// cannot turn, and the field should not ask that of it for nothing.
  static const int _jumpPenalty = 2 * _straight;

  /// The cell the field currently flows towards, or `-1` when the last goal
  /// was somewhere no body of this class can be.
  ///
  /// With several goals, the first one's; [goalCells] has all of them.
  int get goalCell => _goalCells.isEmpty ? -1 : _goalCells.first;

  /// Every goal's cell, in the order the goals were given, `-1` for one no
  /// body of this class can reach the neighbourhood of.
  List<int> get goalCells => List<int>.unmodifiable(_goalCells);
  final List<int> _goalCells = <int>[];

  /// Whether any goal resolved to a cell, which is whether the sweep ran.
  bool _swept = false;

  /// Where [update] resolves its goals before comparing them with the last
  /// sweep's, kept so that a step in which nobody crossed a cell allocates
  /// nothing.
  final List<int> _resolved = <int>[];
  final List<Vector3> _single = <Vector3>[Vector3.zero()];

  final Vector3 _center = Vector3.zero();
  final CellHeap _heap = CellHeap();

  bool fits(int index) =>
      grid.isWalkable(index) &&
      (grid.clearanceAt(index) >= minClearance || _linkEnds.contains(index)) &&
      grid.headroomAt(index) >= minHeadroom;

  /// Whether this field's body takes [link] — by reach, with the body's own
  /// width added to the gap, and with both ends under its head.
  bool takesLink(JumpLink link) {
    final reach = jump;
    return reach != null &&
        reach.takes(rise: link.rise, gap: link.gap + jumpMargin) &&
        grid.isWalkable(link.from) &&
        grid.isWalkable(link.to) &&
        grid.headroomAt(link.from) >= minHeadroom &&
        grid.headroomAt(link.to) >= minHeadroom;
  }

  /// Cost to the goal in tenths of a cell, or [unreachable].
  ///
  /// Steering reads the direction, not the cost, so nothing here calls this. It
  /// is for a tool that draws the field — a level editor colouring cells by
  /// distance, which is how an unreachable pocket behind a wall somebody meant
  /// to make a door is found before a player finds it.
  int costAt(int index) => _cost[index];

  /// How far it is to the goal by walking, in world units, or `null` when
  /// there is no way at all.
  ///
  /// Recorded because it is free: a walking-distance field is what "everything
  /// within twenty metres of the noise wakes up" needs, and the sweep has
  /// already computed it.
  double? walkingDistanceTo(Vector3 world) {
    final cell = grid.cellAt(world);
    if (cell < 0) return null;
    final cost = _cost[cell];
    if (cost >= unreachable) return null;
    return cost * grid.cellSize / _straight;
  }

  /// Which goal the cheapest route from [from] ends at, as an index into the
  /// list the last sweep was given, or `-1` when no route does — off the grid,
  /// walled off, or before any sweep.
  ///
  /// With one goal this is `0` or `-1`, and says no more than [descend] does.
  int sourceAt(Vector3 from) {
    final cell = grid.cellAt(from);
    return cell < 0 ? -1 : _source[cell];
  }

  /// Re-sweeps towards [goal]. Cheap to call every step: it returns without
  /// doing anything while the goal stays in the same cell.
  void update(Vector3 goal) => updateAll(_one(goal));

  /// Re-sweeps towards the nearest of [goals]. Cheap to call every step: it
  /// returns without doing anything while every goal stays in its cell.
  void updateAll(List<Vector3> goals) {
    _checkCount(goals);
    _resolved.clear();
    for (final goal in goals) {
      _resolved.add(_resolveGoal(goal));
    }
    if (_sameCells(_resolved, _goalCells)) return;
    rebuildAll(goals);
  }

  /// Re-sweeps unconditionally. Call this when the level itself changed.
  void rebuild(Vector3 goal) => rebuildAll(_one(goal));

  /// Re-sweeps towards the nearest of [goals] unconditionally.
  void rebuildAll(List<Vector3> goals) {
    _checkCount(goals);
    _cost.fillRange(0, _cost.length, unreachable);
    _dx.fillRange(0, _dx.length, 0);
    _dz.fillRange(0, _dz.length, 0);
    _link.fillRange(0, _link.length, -1);
    _source.fillRange(0, _source.length, -1);
    _goalCells.clear();
    for (final goal in goals) {
      _goalCells.add(_resolveGoal(goal));
    }
    _swept = _goalCells.any((int cell) => cell >= 0);
    if (!_swept) return;

    final columns = grid.columns;
    final rows = grid.rows;
    final reach = jump;
    final links = grid.jumpLinks;
    if (reach != null && _linkEnds.isEmpty) {
      for (final link in links) {
        if (!takesLink(link)) continue;
        _linkEnds
          ..add(link.from)
          ..add(link.to);
      }
    }
    _heap.clear();
    for (var index = 0; index < _goalCells.length; index++) {
      final cell = _goalCells[index];
      // Two goals in one cell: the first keeps it, which is what a tie
      // anywhere else in the sweep does too.
      if (cell < 0 || _cost[cell] == 0) continue;
      _cost[cell] = 0;
      _source[cell] = index;
      _heap.push(cell, 0);
    }

    while (!_heap.isEmpty) {
      final cell = _heap.pop();
      final cost = _heap.poppedCost;
      if (cost > _cost[cell]) continue;

      final cx = cell % columns;
      final cz = cell ~/ columns;

      // The jumps that land here, relaxed backwards to their take-offs: a
      // body standing at the take-off is one jump from this cell. Filtered by
      // this field's own reach, so the link says what it needs and the body
      // says whether it has it.
      if (reach != null) {
        for (final index in grid.linksInto(cell)) {
          final link = links[index];
          if (!takesLink(link)) continue;
          final from = link.from;
          final cost2 =
              cost +
              (link.gap / grid.cellSize * _straight).round() +
              _jumpPenalty;
          if (cost2 >= _cost[from]) continue;
          _cost[from] = cost2;
          _dx[from] = 0;
          _dz[from] = 0;
          _link[from] = index;
          _source[from] = _source[cell];
          _heap.push(from, cost2);
        }
      }

      for (var dz = -1; dz <= 1; dz++) {
        final nz = cz + dz;
        if (nz < 0 || nz >= rows) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dz == 0) continue;
          final nx = cx + dx;
          if (nx < 0 || nx >= columns) continue;

          final next = nz * columns + nx;
          if (!fits(next)) continue;
          // The sweep runs outward from the goal, but the agent will walk the
          // other way — so the height rule is asked in the direction of
          // travel. Climbing up to a ledge and dropping off it are different
          // limits, and asking backwards would let a monster path up a cliff.
          if (!grid.canMove(next, cell)) continue;

          final diagonal = dx != 0 && dz != 0;
          if (diagonal) {
            // A diagonal needs both of its sides open, or an agent cuts the
            // corner of a wall and grinds along it — which is precisely the
            // behaviour this whole file exists to remove.
            final sideA = nz * columns + cx;
            final sideB = cz * columns + nx;
            if (!fits(sideA) || !fits(sideB)) continue;
            if (!grid.canMove(sideA, cell) || !grid.canMove(sideB, cell)) {
              continue;
            }
          }
          final cost2 = cost + (diagonal ? _diagonal : _straight);

          if (cost2 >= _cost[next]) continue;
          _cost[next] = cost2;
          // Towards the cell it was reached from: that is downhill.
          _dx[next] = -dx;
          _dz[next] = -dz;
          _link[next] = -1;
          _source[next] = _source[cell];
          _heap.push(next, cost2);
        }
      }
    }
  }

  /// The direction to walk from [from], written into [out] as a horizontal
  /// unit vector.
  ///
  /// False when there is nothing to say — off the grid, no route to the goal,
  /// or already in the goal's own cell. A caller that gets false should walk
  /// straight at its target: within one cell that *is* the right answer, and
  /// steering by the field there would have an agent circling a cell centre
  /// half a metre from the player.
  bool descend(Vector3 from, Vector3 out) {
    if (!_swept) return false;
    final cell = grid.cellAt(from);
    if (cell < 0) return false;
    // A goal's own cell, whichever goal: nothing else costs nothing.
    if (_cost[cell] == 0) return false;
    if (_cost[cell] >= unreachable) return false;

    final linked = _link[cell];
    if (linked >= 0) {
      // Downhill from here is through the air: aim at the landing, and let
      // [jumpAt] tell the caller that walking there will not do.
      grid.centerOf(grid.jumpLinks[linked].to, _center);
      out.setValues(_center.x - from.x, 0.0, _center.z - from.z);
      if (out.length2 < 1e-8) return false;
      out.normalize();
      return true;
    }

    final dx = _dx[cell];
    final dz = _dz[cell];
    // **Belt and braces, and it is worth saying so.** A cell cheaper than
    // `unreachable` was relaxed, and relaxing records a direction — so the only
    // cell with a cost and no direction is the goal's own, which the line above
    // has already sent away. Mutating this to `return true` breaks no test,
    // because there is no way to reach it. It stays because the alternative,
    // if the sweep ever does leave such a cell, is an agent walking along
    // whatever the previous caller left in `out`.
    if (dx == 0 && dz == 0) return false;

    final next = (grid.cellZ(cell) + dz) * grid.columns + grid.cellX(cell) + dx;
    grid.centerOf(next, _center);
    // Towards the next cell's centre rather than along the raw eight-way
    // offset: an agent that walks the offsets moves in staircases, and one
    // that aims at centres moves in a line whenever the cells are in one.
    out.setValues(_center.x - from.x, 0.0, _center.z - from.z);
    if (out.length2 < 1e-8) return false;
    out.normalize();
    return true;
  }

  /// The jump the field's next step from [from] is, or null when the next step
  /// is a walk — or there is no step at all, for the reasons [descend] gives.
  ///
  /// A brain that steers by [descend] asks this beside it: the direction says
  /// where, and this says that the body has to leave the ground to get there.
  JumpLink? jumpAt(Vector3 from) {
    if (!_swept) return null;
    final cell = grid.cellAt(from);
    if (cell < 0 || _cost[cell] == 0) return null;
    final linked = _link[cell];
    return linked < 0 ? null : grid.jumpLinks[linked];
  }

  List<Vector3> _one(Vector3 goal) {
    _single.first.setFrom(goal);
    return _single;
  }

  void _checkCount(List<Vector3> goals) {
    if (goals.length > maxGoals) {
      throw ArgumentError.value(
        goals.length,
        'goals',
        'a sweep takes at most $maxGoals goals',
      );
    }
  }

  static bool _sameCells(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The goal's own cell, or the nearest one a body of this class fits in.
  ///
  /// The search matters: the player standing in a doorway a tank cannot enter
  /// would otherwise make every tank in the level stop, when what they should
  /// do is come as close as they fit and wait there.
  int _resolveGoal(Vector3 goal) {
    final direct = grid.cellAt(goal);
    if (direct >= 0 && fits(direct)) return direct;
    if (grid.isEmpty) return -1;

    final gx = ((goal.x - grid.originX) / grid.cellSize).floor();
    final gz = ((goal.z - grid.originZ) / grid.cellSize).floor();
    for (var ring = 1; ring <= 6; ring++) {
      var best = -1;
      var bestDistance = 0;
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (dx.abs() != ring && dz.abs() != ring) continue;
          final nx = gx + dx;
          final nz = gz + dz;
          if (nx < 0 || nx >= grid.columns || nz < 0 || nz >= grid.rows) {
            continue;
          }
          final index = nz * grid.columns + nx;
          if (!fits(index)) continue;
          final d = dx * dx + dz * dz;
          if (best < 0 || d < bestDistance) {
            best = index;
            bestDistance = d;
          }
        }
      }
      if (best >= 0) return best;
    }
    return -1;
  }
}
