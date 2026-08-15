import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../track.dart';
import '../vehicle/vehicle_controller.dart';

/// The numbers that make one driver different from another.
final class AiTuning {
  const AiTuning({
    this.lookAheadPerSpeed = 0.55,
    this.minLookAhead = 12.0,
    this.steerGain = 2.2,
    this.corneringGrip = 14.0,
    this.brakeHorizon = 45.0,
    this.brakeMargin = 1.1,
    this.rubberBandPer100m = 0.07,
    this.rubberBandClamp = 0.22,
    this.avoidRange = 22.0,
    this.avoidWidth = 3.2,
    this.avoidOffset = 3.0,
    this.skill = 1.0,
  });

  /// How far ahead to aim, per metre per second of speed.
  ///
  /// A fixed distance cannot work: near enough to be accurate in a hairpin is
  /// near enough to weave on a straight, and far enough to be smooth on a
  /// straight is far enough to cut the hairpin entirely.
  final double lookAheadPerSpeed;

  final double minLookAhead;

  /// How hard the wheel is turned per radian of error.
  final double steerGain;

  /// How much cornering the driver believes it has, in metres per second
  /// squared.
  ///
  /// Deliberately below what the tyres can actually do. A driver that believed
  /// the true figure would be at the limit in every corner and off the road at
  /// the first bump.
  final double corneringGrip;

  /// How far up the road to look for something to brake for.
  final double brakeHorizon;

  /// How far over the corner speed the driver lets itself get before braking,
  /// rather than lifting.
  final double brakeMargin;

  /// How much faster a driver goes for every hundred metres it is behind the
  /// player, as a fraction of its pace.
  final double rubberBandPer100m;

  /// The most the rubber band may change a driver's pace, either way.
  ///
  /// The reason there is a limit at all: a field that can always catch up is a
  /// field the player cannot beat, and one that can always be caught is a field
  /// the player cannot lose to. Both read as the race being fake, which it is.
  final double rubberBandClamp;

  /// How far ahead to look for a car to go round.
  final double avoidRange;

  /// How close alongside counts as being in the way.
  final double avoidWidth;

  /// How far to move over for one.
  final double avoidOffset;

  /// How good this driver is, from nought to one. Scales the pace it aims for.
  final double skill;

  AiTuning copyWith({double? skill}) => AiTuning(
        lookAheadPerSpeed: lookAheadPerSpeed,
        minLookAhead: minLookAhead,
        steerGain: steerGain,
        corneringGrip: corneringGrip,
        brakeHorizon: brakeHorizon,
        brakeMargin: brakeMargin,
        rubberBandPer100m: rubberBandPer100m,
        rubberBandClamp: rubberBandClamp,
        avoidRange: avoidRange,
        avoidWidth: avoidWidth,
        avoidOffset: avoidOffset,
        skill: skill ?? this.skill,
      );
}

/// Drives a car round the track.
///
/// ## Aiming, not following
///
/// The driver does not steer towards the nearest point on the racing line — it
/// steers towards a point some distance up it, and how far up depends on how
/// fast it is going. That one choice is the difference between a car that
/// weaves down every straight hunting for a line it is already on, and a car
/// that reads as being driven.
///
/// ## Braking for what is coming
///
/// The fastest a car holds a bend is the square root of its grip over the
/// bend's curvature, and the curve knows its own curvature — so the driver
/// looks up the road, finds the worst of it within the horizon, and works out
/// what it may be doing by then. Braking for the corner it is *in* is what a
/// driver does when it has already gone in too fast.
///
/// ## The rubber band, kept honest
///
/// A driver behind the player is allowed to go a little faster and one ahead a
/// little slower, both by a hard-limited amount. This is the standard trick and
/// the standard trap: unlimited, it makes the field impossible to escape and
/// impossible to lose to, and a player can feel that within two laps. The limit
/// is what keeps it a nudge rather than a fix.
///
/// ## What it does not do
///
/// It carries no state between steps except what it is told, so a field of
/// eight drivers is one of these and eight calls, and a replay of a race
/// reproduces exactly.
final class AiDriver {
  AiDriver({required this.track, this.tuning = const AiTuning()});

  final TrackSpline track;
  final AiTuning tuning;

  /// Fills [out] with what this driver wants to do.
  ///
  /// [playerGap] is how far ahead of this car the player is, in metres round
  /// the lap — negative when the player is behind. Zero turns the rubber band
  /// off, which is what a time trial or a test wants.
  void drive(
    VehicleController self,
    VehicleInput out, {
    List<VehicleController> others = const <VehicleController>[],
    double playerGap = 0.0,
  }) {
    final at = self.trackDistance;
    final speed = self.speed;

    final lookAhead =
        math.max(tuning.minLookAhead, speed * tuning.lookAheadPerSpeed);
    final offset = _avoidanceOffset(self, others, at);

    // Where to point the car: up the road, and moved over if somebody is there.
    track.frameAt(at + lookAhead, _frame);
    _aim
      ..setFrom(_frame.position)
      ..addScaled(_frame.right, offset);

    _toAim
      ..setFrom(_aim)
      ..sub(self.position);
    final wanted = math.atan2(_toAim.x, _toAim.z);
    final error = _shortestDelta(self.headingYaw, wanted);

    final pace = _pace(at, playerGap);

    out
      // Negated for the same reason the car negates it — see `_steer` in
      // `SphereVehicle`. The error is in heading, which rises anticlockwise;
      // the wheel is in the driver's terms, where positive is right.
      ..steer = (-error * tuning.steerGain).clamp(-1.0, 1.0)
      ..throttle = speed < pace ? 1.0 : 0.0
      ..brake = speed > pace * tuning.brakeMargin ? 1.0 : 0.0
      ..handbrake = false
      ..boost = false;
  }

  /// How fast this driver is willing to be, here and now.
  double _pace(double at, double playerGap) {
    // The worst bend within the horizon, not the one underneath: a driver that
    // brakes for the corner it is in has already arrived too fast.
    var sharpest = 0.0;
    for (var ahead = 0.0; ahead <= tuning.brakeHorizon; ahead += 5.0) {
      final bend = track.centre.curvatureAt(at + ahead).abs();
      if (bend > sharpest) sharpest = bend;
    }

    final ceiling = sharpest < 1e-4
        ? double.infinity
        : math.sqrt(tuning.corneringGrip / sharpest);

    var pace = ceiling * tuning.skill;

    // And the nudge. A positive gap is the player up the road, which makes the
    // number bigger; the clamp is what keeps it a nudge.
    if (playerGap != 0.0) {
      final band = (playerGap / 100.0 * tuning.rubberBandPer100m)
          .clamp(-tuning.rubberBandClamp, tuning.rubberBandClamp);
      pace *= 1.0 + band;
    }

    return pace;
  }

  /// How far to move over to avoid whoever is in the way, in metres.
  ///
  /// A lateral offset on the line rather than a plan: the driver is on a track,
  /// there are two ways round anything, and the only question is which side.
  /// Anything more is a path planner solving a problem a track does not have.
  double _avoidanceOffset(
    VehicleController self,
    List<VehicleController> others,
    double at,
  ) {
    if (others.isEmpty) return 0.0;

    track.frameAt(at, _here);
    final myLateral = _lateralOf(self.position, _here);

    for (final other in others) {
      if (identical(other, self)) continue;

      final gap = _forwardGap(at, other.trackDistance);
      if (gap <= 0.0 || gap > tuning.avoidRange) continue;

      final theirLateral = _lateralOf(other.position, _here);
      if ((theirLateral - myLateral).abs() > tuning.avoidWidth) continue;

      // Round whichever side has more road. Steering into the wall to overtake
      // is worse than following.
      final room = track.widthAt(at) / 2.0;
      final leftRoom = theirLateral + room;
      final rightRoom = room - theirLateral;
      final target = leftRoom > rightRoom
          ? theirLateral - tuning.avoidOffset
          : theirLateral + tuning.avoidOffset;

      return target.clamp(-room + 1.0, room - 1.0);
    }
    return 0.0;
  }

  double _lateralOf(Vector3 position, TrackFrame frame) {
    _offset
      ..setFrom(position)
      ..sub(frame.position);
    return _offset.dot(frame.right);
  }

  /// How far ahead [other] is, in metres round the lap, wrapping.
  double _forwardGap(double from, double other) {
    final length = track.length;
    var gap = (other - from) % length;
    if (gap > length / 2) gap -= length;
    return gap;
  }

  static double _shortestDelta(double from, double to) {
    const twoPi = 2.0 * math.pi;
    var delta = (to - from) % twoPi;
    if (delta > math.pi) {
      delta -= twoPi;
    } else if (delta < -math.pi) {
      delta += twoPi;
    }
    return delta;
  }

  final TrackFrame _frame = TrackFrame();
  final TrackFrame _here = TrackFrame();
  final Vector3 _aim = Vector3.zero();
  final Vector3 _toAim = Vector3.zero();
  final Vector3 _offset = Vector3.zero();
}
