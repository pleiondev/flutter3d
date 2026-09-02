/// The four lines of arithmetic every genre in this repository had written out
/// for itself, in some cases twice.
///
/// None of it is clever and that is the point: each one is short enough to
/// retype, which is exactly why it was retyped — seven times for the first of
/// them, across four packages — and short enough that the copies drifted in
/// ways nobody would notice until a body span the wrong way at the wrap point.
library;

import 'dart:math' as math;

const double _twoPi = 2.0 * math.pi;

/// The shortest way round from one angle to another, in radians.
///
/// **Seven copies before this existed**: `Interpolated`, `Playback` and
/// `ActorSystem` here, `AiDriver` and `ChaseCamera` in the racing package, and
/// twice in the platformer written as a `while` loop instead. The result is in
/// `(-π, π]`, so adding it to `from` never goes the long way about — which is a
/// body that spins once round the moment a heading crosses south, once a lap,
/// in front of whoever is watching.
///
/// **The `while` form is not equivalent, and that is why this one is the
/// modulo.** `while (delta > pi) delta -= twoPi;` never finishes if `delta` is
/// a NaN: the comparison is false, the loop is not entered — or, with the
/// condition the other way round, spins for ever. The modulo form returns a NaN
/// and lets the caller's own arithmetic carry it to something visible instead
/// of hanging the frame.
double shortestAngle(double from, double to) {
  var delta = (to - from) % _twoPi;
  if (delta > math.pi) {
    delta -= _twoPi;
  } else if (delta < -math.pi) {
    delta += _twoPi;
  }
  return delta;
}

/// Moves [value] towards [target] by at most [step], never past it.
///
/// Three copies before this existed: `Mover` here, `SphereVehicle` in the
/// racing package, and the tail of the platformer runner's own turn.
///
/// An infinite [step] arrives at the target rather than at a NaN, which is what
/// a mover with no speed limit asks for.
double approach(double value, double target, double step) {
  if (step.isInfinite) return target;
  final delta = target - value;
  if (delta.abs() <= step) return target;
  return value + (delta.isNegative ? -step : step);
}

/// [yaw], turned towards [wanted] by at most [step], the short way round.
///
/// Named for what it returns rather than for what it does, because
/// `ActorSystem` has a `turnTowards` of its own that turns an actor — and two
/// names one letter apart, one returning and one mutating, is the sort of pair
/// that gets called in the wrong place.
///
/// [shortestAngle] and [approach] composed, because the composition is what
/// three of the copies were: a monster facing the player, a runner facing where
/// it is going, a car's driver correcting its line. Written once so that the
/// wrap and the clamp cannot be got right in one place and wrong in another.
double turnedTowards(double yaw, double wanted, double step) =>
    yaw + approach(0.0, shortestAngle(yaw, wanted), step);

/// How much of the way to a target one step of [dt] seconds should carry, for
/// something that eases in at [rate] per second.
///
/// `1 - exp(-rate * dt)`, which was written out at six call sites across four
/// packages — two cameras, a suspension, a weapon's bob, the loop's own
/// interpolation and its pace meter.
///
/// **Not `rate * dt`, and the difference is the whole reason this is a
/// function.** A plain multiply is a spring whose stiffness depends on the
/// frame rate: the same camera lags differently at 60 and at 144, and past
/// `rate * dt > 1` it overshoots and rings. This form is the exact solution of
/// the same easing over the step, so a machine that drops frames gets the same
/// motion as one that does not — which is the property the whole fixed step
/// exists to protect.
///
/// A rate of nought never moves; a negative one is treated as nought rather
/// than as a body flying apart.
double easeFactor(double rate, double dt) {
  if (rate <= 0.0 || dt <= 0.0) return 0.0;
  return 1.0 - math.exp(-rate * dt);
}
