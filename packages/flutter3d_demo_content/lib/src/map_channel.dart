/// The strategy map's river bed: its course laid over the map's ground and
/// smoothed, its bed graded down it with its falls and their pools, its
/// fords where the ways between the halls cross it, its stones, and the
/// ground with all of that carved into it.
///
/// One definition for both grounds a map has: the water's, cell by cell
/// ([MapChannel.bed]), and the ground the map is drawn and walked on
/// ([MapWater.carve]), so the water can stand in a bed the ground has.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' as sim show Heightfield;
import 'package:vector_math/vector_math.dart';

import '../map_world.dart' show MapWater, RiverStone, nearestSeam;

/// [water]'s river laid over a map's ground, forded where the ways between
/// its halls — and from each to its nearest seam — cross it.
final class MapChannel {
  /// The river's course laid over the map, its bed graded down it, its
  /// fords laid where the ways between [halls] cross it and its stones placed:
  /// what [bed] shapes and the world's water fills.
  ///
  /// **The river runs in a bed of its own.** Left to the hillside as it
  /// is, the water from the spring spread into a film a few millimetres
  /// deep and ten metres wide, which from where the camera hangs is no water
  /// at all. A river has worn itself a bed; this ground has not. So the
  /// ground under the water is shaped: a bed laid a hand under the grass
  /// down the middle of the course, rising round on either side to banks
  /// over it, which the water stands in four metres wide and a foot deep.
  /// [bed] is that ground cell by cell, for the water; [bedAt] at any point,
  /// which [MapWater.carve] lays into the ground the map is drawn and walked
  /// on, so the bed is not the water's alone but the map's.
  ///
  /// **The view is given that bed.** It ends the water between a wet
  /// vertex and a dry one, as far across as the depth passes nought, and
  /// over the bed the depth falls smoothly to nought where the bed rises
  /// through the water: a shore as smooth as the bed.
  MapChannel(
    this.water,
    this._field,
    List<Building> halls,
    List<ResourceNode> seams,
  ) {
    final MapWater w = water;
    _terrain = <double>[
      for (var j = 0; j < w.nz; j++)
        for (var i = 0; i < w.nx; i++)
          _field.heightAt(w.x0 + (i + 0.5) * w.cell, w.z0 + (j + 0.5) * w.cell),
    ];
    _line = _trace();
    _down = <double>[0.0];
    for (var k = 1; k < _line.length; k++) {
      _down.add(_down.last + (_line[k] - _line[k - 1]).length);
    }
    _level = _grade();
    final double out =
        _fordHalfWide * math.sqrt(_bankHigh / _shoulder) + _bankWide;
    _reach = (
      x0: _line.map((Vector2 p) => p.x).reduce(math.min) - out,
      z0: _line.map((Vector2 p) => p.y).reduce(math.min) - out,
      x1: _line.map((Vector2 p) => p.x).reduce(math.max) + out,
      z1: _line.map((Vector2 p) => p.y).reduce(math.max) + out,
    );
    _fords.addAll(_crossings(halls, seams));
    stones = _lay();
  }

  /// What the map's water is.
  final MapWater water;

  final sim.Heightfield _field;

  /// The stones laid in the river.
  late final List<RiverStone> stones;

  /// Where down the course the ways between the halls ford it, m.
  List<double> get fords => List<double>.unmodifiable(_fords);

  /// Half the width of the river's bed, and of a ford's, m: where the bed
  /// has risen [_shoulder] over its middle. The water runs a little wider,
  /// as far as it is deep over the middle.
  static const double _halfWide = 1.7, _fordHalfWide = 3.0;

  /// How far over its middle the bed has risen at [_halfWide], m. It rises
  /// as the square of the way out from the middle, a bed worn round, so the
  /// water thins to nothing toward its edges and the edge is wherever the
  /// bed comes up through it, not where a cell stops.
  static const double _shoulder = 0.3;

  /// The banks the bed rises to, how far over its middle, and how far they
  /// run on flat past where it reaches them, m.
  ///
  /// **Higher than a step and the water over it.** Beside a step the water
  /// above it stands over the banks of the run below by as much as the step
  /// drops; banks a metre high let it out sideways there, off their outer
  /// edge onto the grass, and the core threw it down as rows of drops in a
  /// line beside the river like a fence.
  static const double _bankHigh = 1.6, _bankWide = 1.0;

  /// How far under the ground the middle of the bed is laid, m, so the
  /// water down it stands only a hand over the grass round it.
  static const double _sunk = 0.15;

  /// The most the bed falls a metre down the course, taken along the grid,
  /// m: the fall from one cell to the next, over the cell, may be no more
  /// than this. The view draws two neighbouring cells as one surface when
  /// they are less than four tenths of a cell apart, and as water falling
  /// from one to the other past that, so a bed falling more steeply runs
  /// water drawn as nothing at all. A quarter leaves room for the water's
  /// own waves: at three tenths the runs between the falls were drawn torn,
  /// cell by cell, wherever a wave stood up.
  static const double _steepest = 0.25;

  /// How far over the ground the bed is let stand before it falls back down
  /// to it over a step, m. Where the ground falls more steeply than
  /// [_steepest] the bed falls as steeply as it may and comes away from the
  /// ground; at this much it drops in one step, and the core throws the
  /// water off it as a sheet that churns the run below it white.
  static const double _mostOver = 0.75;

  /// The pool a fall digs at its foot: how much deeper than the run, m, and
  /// how far down the course it shallows back to it. Landing on a run a
  /// foot deep the water raced on thin and fast and stood up in a jump a
  /// stride below, which the view cuts as a fall; in a pool it lands deep
  /// and goes on slow.
  static const double _plunge = 0.25, _plungeLong = 1.5;

  /// How far a ford runs along the river either side of where the way
  /// crosses it, at its full width, and how far past that it narrows back
  /// to the river's, m; and how far its bar of gravel stands over the bed.
  static const double _fordLong = 2.0, _fordTaper = 3.0, _fordBar = 0.15;

  /// How far apart the stones in the river lie, m, and how far into it the
  /// first one is.
  static const double _stoneEvery = 4.5, _firstStone = 3.0;

  /// The river's course from the spring into the pond, a point every half
  /// metre or so; how far down it each point is, m; and the level its bed is
  /// laid at down its middle there.
  late final List<Vector2> _line;
  late final List<double> _down, _level;

  /// The pieces of [_line] the river falls over a step in: the bed is laid
  /// at the level of the point above to halfway along, and of the point
  /// below from there.
  final Set<int> _steps = <int>{};

  /// How far round the course the water's ground is shaped, and past that
  /// left as the ground is drawn.
  late final ({double x0, double z0, double x1, double z1}) _reach;

  /// Where down [_line] the ways between the halls ford it, m.
  final List<double> _fords = <double>[];

  /// The ground as it is drawn at the middle of each of the water's cells.
  late final List<double> _terrain;

  /// The course drawn through smoothly, a point every half metre or so.
  List<Vector2> _trace() {
    final List<Vector2> course = water.course;
    final List<Vector2> p = <Vector2>[course.first, ...course, course.last];
    const int pieces = 20;
    final dense = <Vector2>[
      for (var i = 1; i + 2 < p.length; i++)
        for (var k = 0; k < pieces; k++)
          _catmull(p[i - 1], p[i], p[i + 1], p[i + 2], k / pieces),
      course.last,
    ];
    return dense.fold(<Vector2>[], (List<Vector2> kept, Vector2 q) {
      if (kept.isEmpty || (q - kept.last).length >= water.cell) kept.add(q);
      return kept;
    });
  }

  /// The point [t] of the way from [b] to [c] on a curve through [a], [b],
  /// [c] and [d].
  static Vector2 _catmull(
    Vector2 a,
    Vector2 b,
    Vector2 c,
    Vector2 d,
    double t,
  ) =>
      (b * 2.0 +
          (c - a) * t +
          (a * 2.0 - b * 5.0 + c * 4.0 - d) * (t * t) +
          (b * 3.0 - a - c * 3.0 + d) * (t * t * t)) *
      0.5;

  /// The level of the bed down the middle of the course, point by point: a
  /// hand under the ground, falling with it as long as it falls no more
  /// steeply than [_steepest] lets the view draw, and where the ground
  /// falls faster, falling that steeply until it stands [_mostOver] over the
  /// ground and then dropping back to it in one step. Down the valley that
  /// is the ground's own fall; down the bank into the pond it is a run of
  /// short steep runs and small falls, as a stream comes down a hillside,
  /// each fall with a pool dug at its foot.
  List<double> _grade() {
    final level = <double>[
      _field.heightAt(_line.first.x, _line.first.y) - _sunk,
    ];
    for (var k = 1; k < _line.length; k++) {
      final Vector2 step = _line[k] - _line[k - 1];
      final double ground = _field.heightAt(_line[k].x, _line[k].y) - _sunk;
      final double laid = math.min(
        level.last,
        math.max(
          ground,
          level.last - _steepest * step.length2 / (step.x.abs() + step.y.abs()),
        ),
      );
      if (laid - ground > _mostOver) _steps.add(k);
      level.add(laid - ground > _mostOver ? ground : laid);
    }
    return <double>[
      for (var k = 0; k < level.length; k++)
        level[k] -
            _steps.fold<double>(0.0, (double most, int step) {
              final double past = (_down[k] - _down[step]) / _plungeLong;
              return past < 0.0 || past >= 1.0
                  ? most
                  : math.max(most, _plunge * (1.0 - past));
            }),
    ];
  }

  /// Where on the line, [down] metres from the spring.
  Vector2 pointAt(double down) {
    final int k = _segmentAt(down);
    final double t = (down - _down[k]) / (_down[k + 1] - _down[k]);
    return _line[k] + (_line[k + 1] - _line[k]) * t.clamp(0.0, 1.0);
  }

  int _segmentAt(double down) {
    var k = 0;
    while (k + 2 < _line.length && _down[k + 1] < down) {
      k++;
    }
    return k;
  }

  /// How much of a ford there is [down] metres down the line, nought to
  /// one: all of it within [_fordLong] of where a way crosses, and less
  /// and less over [_fordTaper] past that, along a half wave so the bar
  /// rises out of the bed and the banks open out with no corner in either.
  double _fordAt(double down) => _fords.fold(0.0, (double most, double at) {
    final double past = ((down - at).abs() - _fordLong) / _fordTaper;
    return math.max(
      most,
      past <= 0.0
          ? 1.0
          : past >= 1.0
          ? 0.0
          : 0.5 + 0.5 * Portable.cos(math.pi * past),
    );
  });

  /// The stones in the river: one every [_stoneEvery] metres, a little to
  /// one side of the middle and then the other, each a little bigger or
  /// smaller than the last: the water parts round them, and where it is
  /// slow they are what shows it moving. None on a step, where they would
  /// stand in the falling sheet, none in the pond, and none in a ford.
  List<RiverStone> _lay() => <RiverStone>[
    for (var n = 0; _firstStone + n * _stoneEvery < _down.last - 2.0; n++)
      ?_stoneAt(n),
  ];

  /// The [n]th stone down the river, if it has a place.
  RiverStone? _stoneAt(int n) {
    final double down = _firstStone + n * _stoneEvery;
    final Vector2 middle = pointAt(down);
    final double level = _nearest(middle.x, middle.y).level;
    final bool clear =
        level > water.pondLevel &&
        _fordAt(down) == 0.0 &&
        _steps.every((int k) => (_down[k] - down).abs() > 1.2);
    if (!clear) return null;
    final Vector2 at = middle + _across(down) * (n.isEven ? 0.9 : -0.8);
    return (
      at: Vector3(at.x, level, at.y),
      down: down,
      size: 0.5 + 0.12 * Portable.sin(n * 2.3),
      level: level,
    );
  }

  /// Square to the line at [down], to its left.
  Vector2 _across(double down) {
    final int k = _segmentAt(down);
    final Vector2 along = (_line[k + 1] - _line[k])..normalize();
    return Vector2(along.y, -along.x);
  }

  /// How far `(x, z)` is from the line, how far down the line the nearest
  /// point of it is, m, and the level of the bed's middle there: a step's
  /// level above it to halfway along the step's piece, and below it past
  /// that, so the step is a sharp edge square across the river.
  ({double away, double down, double level}) _nearest(double x, double z) {
    var nearest = double.infinity;
    var down = 0.0, level = 0.0;
    for (var k = 0; k + 1 < _line.length; k++) {
      final double ax = _line[k].x, az = _line[k].y;
      final double bx = _line[k + 1].x - ax, bz = _line[k + 1].y - az;
      final double t = (((x - ax) * bx + (z - az) * bz) / (bx * bx + bz * bz))
          .clamp(0.0, 1.0);
      final double dx = x - ax - bx * t, dz = z - az - bz * t;
      final double d2 = dx * dx + dz * dz;
      if (d2 < nearest) {
        nearest = d2;
        down = _down[k] + t * (_down[k + 1] - _down[k]);
        level = _steps.contains(k + 1)
            ? (t < 0.5 ? _level[k] : _level[k + 1])
            : _level[k] + t * (_level[k + 1] - _level[k]);
      }
    }
    return (away: math.sqrt(nearest), down: down, level: level);
  }

  /// The water's ground, cell by cell: the river's bed worn round down the
  /// course and closed round at the spring, rising to banks either side,
  /// widening and lifted to a bar where a way fords it, a stone standing in
  /// it here and there, and the ground as it is drawn everywhere else.
  List<double> bed() {
    final MapWater w = water;
    return <double>[
      for (var j = 0; j < w.nz; j++)
        for (var i = 0; i < w.nx; i++)
          bedAt(
            w.x0 + (i + 0.5) * w.cell,
            w.z0 + (j + 0.5) * w.cell,
            _terrain[i + j * w.nx],
          ),
    ];
  }

  double bedAt(double x, double z, double ground) {
    if (x < _reach.x0 || x > _reach.x1 || z < _reach.z0 || z > _reach.z1) {
      return ground;
    }
    final (:away, :down, :level) = _nearest(x, z);
    // A ford: the bed lifted a hand and worn wider and flatter, so the
    // river spreads over it shallow and quick instead of keeping to its
    // middle a foot deep.
    final double ford = _fordAt(down);
    final double half = _halfWide + (_fordHalfWide - _halfWide) * ford;
    final double middle = level + _fordBar * ford;
    final double across = away / half;
    final double rise = _shoulder * across * across;
    final double trough =
        away < half * math.sqrt(_bankHigh / _shoulder) + _bankWide
        ? middle + math.min(rise, _bankHigh)
        : double.negativeInfinity;
    // A stone: a round hump in the bed under the one drawn, a little lower
    // than it, that the water runs round.
    final double stone = stones.fold(double.negativeInfinity, (
      double most,
      RiverStone b,
    ) {
      final double r = 0.8 * b.size;
      final double dx = x - b.at.x, dz = z - b.at.z;
      final double d2 = (dx * dx + dz * dz) / (r * r);
      return d2 < 1.0
          ? math.max(most, b.level + (0.1 + 0.6 * b.size) * (1.0 - d2))
          : most;
    });
    final double bed = math.max(ground, math.max(trough, stone));
    // Where the course runs out into the pond it is the pond's floor: banks
    // standing out of it would be a pier, and held just under its surface
    // they were a pale shelf, square at its corners.
    return ground < water.pondLevel ? ground : bed;
  }

  /// Where the ways between the halls cross the river, m down it: the way
  /// an army takes from each hall to each hall of another side, and the
  /// path each hall's crowd wears to its seam.
  List<double> _crossings(List<Building> halls, List<ResourceNode> seams) {
    Vector2 flat(Vector3 at) => Vector2(at.x, at.z);
    final ways = <(Vector2, Vector2)>[
      for (final Building a in halls)
        for (final Building b in halls)
          if (a.side < b.side) (flat(a.center), flat(b.center)),
      for (final Building a in halls)
        if (nearestSeam(a, seams) case final ResourceNode seam)
          (flat(a.center), flat(seam.at)),
    ];
    double cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;
    final crossings = <double>[
      for (final (Vector2 p, Vector2 q) in ways)
        for (var k = 0; k + 1 < _line.length; k++)
          if (_crossing(p, q - p, _line[k], _line[k + 1] - _line[k], cross)
              case final double t)
            _down[k] + t * (_down[k + 1] - _down[k]),
    ]..sort();
    // Not at the spring or the mouth, not on the falls, and one ford for
    // ways that cross close together.
    return <double>[
      for (var i = 0; i < crossings.length; i++)
        if (crossings[i] > _fordLong + 2.0 &&
            crossings[i] < _down.last - _fordLong - 2.0 &&
            _steps.every(
              (int k) => (_down[k] - crossings[i]).abs() > _fordLong + 2.0,
            ) &&
            (i == 0 || crossings[i] - crossings[i - 1] > 3.0 * _fordLong))
          crossings[i],
    ];
  }

  /// How far along the line's piece from [a] by [ab] the way from [p] by
  /// [pq] crosses it, nought to one, or null if it does not.
  static double? _crossing(
    Vector2 p,
    Vector2 pq,
    Vector2 a,
    Vector2 ab,
    double Function(Vector2, Vector2) cross,
  ) {
    final double turn = cross(pq, ab);
    if (turn.abs() < 1e-9) return null;
    final double u = cross(a - p, ab) / turn;
    final double t = cross(a - p, pq) / turn;
    return u >= 0.0 && u <= 1.0 && t >= 0.0 && t <= 1.0 ? t : null;
  }
}
