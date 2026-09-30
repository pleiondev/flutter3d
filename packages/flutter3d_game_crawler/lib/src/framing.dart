/// Where a shared view has to be for every hero to be in it, and how far any
/// of them may walk.
///
/// ## Why this is the simulation's and not the camera's
///
/// The arcade rule is that nobody walks off the screen: the heroes share one
/// view, and one of them heading for the exit cannot drag it away from the
/// three still fighting. That is a rule about where a hero may *go*, so it is
/// part of the step, and the step has to give the same answer on every
/// machine and after every load. A camera that eases towards where it wants
/// to be has state the save does not carry and a window whose shape the
/// player chooses — neither of which may decide where a hero can stand.
///
/// So the rule is read off the *framing*: a function of where the heroes are
/// and of numbers the game fixes, with nothing remembered between steps. The
/// camera eases towards the same framing and draws it; the playfield's
/// [FramingTuning.aspect] is the game's, and a wider window shows more at the
/// sides without letting anybody walk into it.
///
/// ## The footprint
///
/// The eye sits south of the heroes and looks north and down at
/// [FramingTuning.pitch]. What it sees of flat ground is a trapezoid, narrow
/// at the near edge. The bounds are the rectangle inside it: the full depth,
/// and the near edge's width. Every length in it grows in proportion to the
/// height, so it is worked out once for a height of one metre and scaled.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// The numbers a shared top-down view is made of.
final class FramingTuning {
  const FramingTuning({
    this.pitch = 1.1,
    this.fieldOfView = 0.9,
    this.aspect = 16.0 / 9.0,
    this.minHeight = 10.0,
    this.maxHeight = 22.0,
    this.margin = 2.0,
  }) : assert(
         pitch + fieldOfView / 2.0 < 1.5707963267948966,
         'the near edge of the view would be behind the eye',
       ),
       assert(pitch - fieldOfView / 2.0 > 0.0, 'the view would see the sky');

  /// How far the view tilts down from the horizon, in radians. Sixty-three
  /// degrees: steep enough to see round the walls, shallow enough that a hero
  /// has a silhouette.
  final double pitch;

  /// The vertical field of view, in radians.
  final double fieldOfView;

  /// The playfield's width over its height. The game's, not the window's.
  final double aspect;

  /// The closest the eye comes, however close together the heroes are.
  final double minHeight;

  /// The furthest it goes. The heroes can spread no further than this shows.
  final double maxHeight;

  /// Metres kept clear between a hero and the edge of the view.
  final double margin;
}

/// The view the living heroes need, recomputed every step.
final class CrawlFraming {
  CrawlFraming([this.tuning = const FramingTuning()])
    : _near = 1.0 / Portable.tan(tuning.pitch + tuning.fieldOfView / 2.0),
      _far = 1.0 / Portable.tan(tuning.pitch - tuning.fieldOfView / 2.0),
      _halfWidth =
          Portable.cos(tuning.fieldOfView / 2.0) /
          Portable.sin(tuning.pitch + tuning.fieldOfView / 2.0) *
          Portable.tan(tuning.fieldOfView / 2.0) *
          tuning.aspect,
      _ahead = 1.0 / Portable.tan(tuning.pitch);

  final FramingTuning tuning;

  // Per metre of height: how far ahead of the eye's foot the near and far
  // edges of the view touch the ground, how wide the near edge is either side
  // of the middle, and how far ahead the middle of the picture lands.
  final double _near;
  final double _far;
  final double _halfWidth;
  final double _ahead;

  final Vector3 _centre = Vector3.zero();
  double _height = 0.0;
  bool _framed = false;

  /// The middle of the heroes, on the ground they stand on.
  Vector3 get centre => _centre;

  /// How high the eye has to be for all of them, within the tuning's limits.
  double get height => _height;

  /// Whether anything has been framed yet. Before, the bounds hold nobody in.
  bool get isFramed => _framed;

  /// Where the eye wants to be, and what it looks at, written into [eye] and
  /// [target].
  void view(Vector3 eye, Vector3 target) {
    final behind = (_near + _far) / 2.0 * _height;
    eye.setValues(_centre.x, _centre.y + _height, _centre.z + behind);
    target.setValues(_centre.x, _centre.y, eye.z - _ahead * _height);
  }

  /// Frames [feet], the living heroes' feet. An empty list changes nothing:
  /// the last heroes to fall are where the view stays.
  void frame(List<Vector3> feet) {
    if (feet.isEmpty) return;
    var minX = feet.first.x;
    var maxX = minX;
    var minZ = feet.first.z;
    var maxZ = minZ;
    var floor = feet.first.y;
    for (final at in feet) {
      if (at.x < minX) minX = at.x;
      if (at.x > maxX) maxX = at.x;
      if (at.z < minZ) minZ = at.z;
      if (at.z > maxZ) maxZ = at.z;
      if (at.y < floor) floor = at.y;
    }
    _centre.setValues((minX + maxX) / 2.0, floor, (minZ + maxZ) / 2.0);
    final across = ((maxX - minX) / 2.0 + tuning.margin) / _halfWidth;
    final deep = ((maxZ - minZ) / 2.0 + tuning.margin) / ((_far - _near) / 2.0);
    final wanted = across > deep ? across : deep;
    _height = wanted < tuning.minHeight
        ? tuning.minHeight
        : (wanted > tuning.maxHeight ? tuning.maxHeight : wanted);
    _framed = true;
  }

  /// How far either side of [centre] a hero may stand, across and along.
  ///
  /// At the *furthest* the view goes, not where it is: the heroes may spread
  /// until the view can open no further, and it is only then that the edge
  /// holds anybody back.
  double get reachX => _halfWidth * tuning.maxHeight - tuning.margin;
  double get reachZ => (_far - _near) / 2.0 * tuning.maxHeight - tuning.margin;

  /// Takes out the part of [wish] and of [velocity] that would carry a hero
  /// standing at [at] past the edge of the view within the next [dt].
  ///
  /// **The velocity as well as the wish**, because the edge is a wall and not
  /// a suggestion: a hero at full speed who merely stops pushing slides on
  /// for a third of a metre while friction takes the speed away, and a third
  /// of a metre past the edge is off the screen. Looking a step ahead is what
  /// keeps the overshoot under one step's travel.
  ///
  /// Only the outward part: a hero at the edge can still walk along it or
  /// back in, and one who is somehow outside is never pushed — walking brings
  /// them back.
  void holdIn(Vector3 at, Vector3 wish, Vector3 velocity, double dt) {
    if (!_framed) return;
    final dx = at.x + velocity.x * dt - _centre.x;
    final dz = at.z + velocity.z * dt - _centre.z;
    if ((dx >= reachX && velocity.x > 0.0) ||
        (dx <= -reachX && velocity.x < 0.0)) {
      velocity.x = 0.0;
    }
    if ((dz >= reachZ && velocity.z > 0.0) ||
        (dz <= -reachZ && velocity.z < 0.0)) {
      velocity.z = 0.0;
    }
    if ((dx >= reachX && wish.x > 0.0) || (dx <= -reachX && wish.x < 0.0)) {
      wish.x = 0.0;
    }
    if ((dz >= reachZ && wish.z > 0.0) || (dz <= -reachZ && wish.z < 0.0)) {
      wish.z = 0.0;
    }
  }
}
