import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'layers.dart';
import 'track.dart';

/// What was found under a car: where the ground is, which way it faces, and
/// what it is called.
///
/// Filled in rather than returned, and reused between steps: this is asked once
/// per car per step at least, and often four times more when the car has wheels.
final class GroundSample {
  /// How far along the track the car is, in metres. Feed this back as the hint
  /// on the next step — that is what keeps the answer on the right part of a
  /// track that folds back beside itself.
  double s = 0.0;

  /// How far to the side of the centre line, along [TrackFrame.right].
  ///
  /// Measured along the road's own sideways axis, which on a cambered corner is
  /// tilted — so for a car in the air this mixes in some of its height, by the
  /// height above the road times the sine of the camber. On the road, where it
  /// is read, that term is nothing; a car five metres up over a corner banked
  /// seven degrees reads about sixty centimetres wide of where it is, which is
  /// well inside the width of the track it is not currently on.
  double lateral = 0.0;

  /// The height of the ground here.
  double height = 0.0;

  /// Which way the ground faces. A cambered corner leans this into the turn,
  /// which is most of what makes one feel like a corner.
  final Vector3 normal = Vector3(0.0, 1.0, 0.0);

  /// What the ground is called, or null where nothing has said.
  String? surface;

  /// Whether this is the road, as opposed to the shoulder beside it or whatever
  /// the level has built out there.
  bool onRoad = false;

  /// Whether the track has a wall on this side here.
  bool barrier = false;

  /// How far the road runs either side of the centre line, so that whoever is
  /// driving can tell how far past the edge it has strayed.
  ///
  /// Zero off the track entirely, where the road has no edge to be past.
  double halfWidth = 0.0;

  /// The direction [lateral] is measured along, so that a car pushed back by a
  /// wall knows which way back is.
  final Vector3 lateralAxis = Vector3(1.0, 0.0, 0.0);
}

/// Where a car asks what is underneath it.
///
/// An interface with one implementation today, because the car is written
/// against the question and not against the track: the same car has to be
/// drivable on a test fixture that is one flat plane, and later on whatever a
/// second kind of track turns out to be. The alternative — a car that reaches
/// into a [TrackSpline] directly — makes every vehicle test build a circuit.
abstract interface class GroundField {
  /// Finds the ground under [position], searching near [nearHint] metres along
  /// the track.
  ///
  /// Returns false when there is nothing under the car at all, which is a fall
  /// and not a driving surface.
  bool sample(Vector3 position, double nearHint, GroundSample out);
}

/// The track's answer to that question: the road worked out from the curve, and
/// anything off it handed to the collision world.
///
/// The road itself is not collision geometry — see [TrackSpline] for why — so
/// this is where the road ends and the ordinary world begins. Inside the ribbon
/// of tarmac and its shoulders the answer comes from the curve and is smooth by
/// construction; outside it, a ray goes down into whatever the level built, and
/// if that finds nothing the car is in the air over nothing.
final class TrackField implements GroundField {
  TrackField({
    required this.track,
    this.world,
    this.searchWindow = 30.0,
    this.probeAbove = 3.0,
    this.probeBelow = 60.0,
    this.offTrackMask = defaultProbeMask,
  });

  /// What the off-track ray is allowed to hit.
  ///
  /// **Everything except the cars**, and that exclusion is not a nicety. The ray
  /// starts above the car and points down, so the first thing in its way is the
  /// car's own body: it reads the top of its own collider as the ground,
  /// settles up towards it, and reads a little higher next step. A car that
  /// stands on itself climbs at about twenty metres a second, on the road, in a
  /// straight line, while reporting that it is on the ground — which is what it
  /// did.
  ///
  /// Every car rather than only the one asking, because standing on somebody
  /// else's roof is not better.
  static const int defaultProbeMask =
      Layers.all & ~(RacingLayers.vehicle | RacingLayers.roadTrigger);

  final TrackSpline track;

  /// The level around the track: scenery, run-off, whatever has been built off
  /// the racing surface. Absent in a test that is only interested in the road.
  final CollisionWorld? world;

  /// How far either side of the hint to look for the car's place on the track.
  ///
  /// Wide enough to cover a step at any speed a car reaches, narrow enough that
  /// the far side of a hairpin is outside it. A car doing ninety metres a second
  /// moves one and a half metres per step, so this is twenty steps of slack.
  final double searchWindow;

  /// How far above the car the off-track ray starts, so that a car resting on
  /// the ground still has ground beneath the ray's origin.
  final double probeAbove;

  /// How far down the off-track ray reaches before giving up and calling it a
  /// fall.
  final double probeBelow;

  final int offTrackMask;

  @override
  bool sample(Vector3 position, double nearHint, GroundSample out) {
    final s = track.centre.closestS(
      position,
      nearS: nearHint,
      window: searchWindow,
    );
    track.frameAt(s, _frame);

    final toCar = position - _frame.position;
    final lateral = toCar.dot(_frame.right);
    final halfWidth = track.widthAt(s) / 2.0;

    out
      ..s = s
      ..lateral = lateral;

    if (lateral.abs() <= halfWidth + track.shoulder) {
      // On the ribbon. The surface is the centre line displaced sideways, so its
      // height falls out of the frame without touching the collision world.
      out
        ..height = _frame.position.y + _frame.right.y * lateral
        ..onRoad = lateral.abs() <= halfWidth
        ..surface = track.surfaceAt(s, lateral)
        ..barrier = track.barrierAt(s, left: lateral < 0.0)
        ..halfWidth = halfWidth;
      out.normal.setFrom(_frame.up);
      out.lateralAxis.setFrom(_frame.right);
      return true;
    }

    out
      ..onRoad = false
      ..barrier = false
      ..halfWidth = 0.0;
    out.lateralAxis.setFrom(_frame.right);
    return _probeWorld(position, out);
  }

  /// Off the track entirely: whatever the level built out here, if anything.
  bool _probeWorld(Vector3 position, GroundSample out) {
    final world = this.world;
    if (world == null) {
      out.surface = null;
      return false;
    }

    _origin
      ..setFrom(position)
      ..y += probeAbove;
    _ray.reset();

    final hit = world.raycast(
      _origin,
      _down,
      probeAbove + probeBelow,
      _ray,
      mask: offTrackMask,
    );
    if (!hit) {
      out.surface = null;
      return false;
    }

    out.height = _ray.point.y;
    out.normal.setFrom(_ray.normal);
    // The same way the platformer's runner reads what it is standing on: the
    // collider carries the brush it came from, and the brush carries the word.
    final under = _ray.collider?.userData;
    out.surface = under is Brush ? under.surface : null;
    return true;
  }

  final TrackFrame _frame = TrackFrame();
  final RayHit _ray = RayHit();
  final Vector3 _origin = Vector3.zero();
  final Vector3 _down = Vector3(0.0, -1.0, 0.0);
}
