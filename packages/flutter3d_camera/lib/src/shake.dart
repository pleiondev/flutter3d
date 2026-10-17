import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'shot.dart';

/// A jolt to the view: how big, how fast, how long, and where it came from.
///
/// A description, not an effect, so a table can say what an event feels like
/// and a test can assert it. An [ImpulseShake] turns it into motion.
final class CameraImpulse {
  /// An impulse [amplitude] metres wide and [angle] radians of turn at its
  /// start, rattling at [frequency] a second and gone after [seconds].
  ///
  /// With [at], it is felt in full by a camera standing on that point and
  /// fades to nothing [radius] metres from it. Without [at] it is felt in full
  /// everywhere — the player's own landing, a hit on the player.
  const CameraImpulse({
    this.amplitude = 0.15,
    this.angle = 0.0,
    this.frequency = 12.0,
    this.seconds = 0.5,
    this.at,
    this.radius = 30.0,
  });

  /// How far the eye is thrown at the start, in metres.
  final double amplitude;

  /// How far the view turns at the start, in radians, about the vertical and
  /// across. A turn reads as a blow to the head; a throw reads as the ground
  /// moving.
  final double angle;

  /// How many times a second it rattles. Low is a rumble, high a buzz.
  final double frequency;

  /// How long until it has died away, in seconds.
  final double seconds;

  /// Where it happened, or null for an impulse felt the same everywhere.
  final Vector3? at;

  /// How far from [at] it can still be felt, fading linearly to nothing, in
  /// metres.
  final double radius;

  /// How strongly a camera with its eye at [eye] feels it, nought to one.
  double strengthAt(Vector3 eye) {
    final from = at;
    if (from == null) return 1.0;
    if (radius <= 0.0) return 0.0;
    return (1.0 - from.distanceTo(eye) / radius).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'CameraImpulse(${amplitude}m, ${angle}rad, ${frequency}Hz, ${seconds}s)';
}

/// The view shaken by impulses: decaying noise added to a shot.
///
/// **The noise is seeded by the step, not by a clock.** An impulse's noise is
/// chosen by [seed], the step that published the event and its place among
/// that step's events, and played back against the time since it arrived —
/// so a replay of a run shakes the camera the same way the run did, and two
/// clients watching one step agree about it. The frames it is sampled at are
/// the display's, which is fine: it is the same curve, looked at at slightly
/// different moments. Nothing here is read by a step; a camera's shake is
/// the view's business only, and the noise uses `dart:math` freely for that
/// reason.
///
/// **It starts from still.** The noise is gradient noise, nought at whole
/// periods, and the first of them is the moment of the impulse: an impulse
/// that began at a random offset would teleport the camera on the frame it
/// arrived, which reads as a dropped frame and not as a blow.
final class ImpulseShake {
  /// A shake whose noise is chosen by [seed].
  ImpulseShake({this.seed = 0, this.motion = 1.0, this.limit = 16});

  /// Which noise. Two cameras with different seeds shake differently from
  /// the same impulses.
  final int seed;

  /// How much of the shake the player asked for, nought to one. Games save
  /// it with the camera's other motion setting, `a11y.cameraMotion`; nought is
  /// off, not broken.
  double motion;

  /// The most impulses at once; past it the oldest is dropped. A blast that
  /// throws thirty sparks must not cost thirty noises a frame.
  final int limit;

  final List<_Live> _live = <_Live>[];
  double _time = 0.0;

  /// Seconds since the shake was made, as [advance] counted them.
  double get time => _time;

  /// Whether anything is still shaking.
  bool get isShaking => _live.isNotEmpty;

  /// How many impulses are still being felt.
  int get count => _live.length;

  /// Adds [impulse], published by [step] as its [sequence]th event, felt by a
  /// camera whose eye is at [eye].
  ///
  /// Too far away, or with the motion setting at nought, it is not added.
  void impulse(
    CameraImpulse impulse, {
    required int step,
    int sequence = 0,
    Vector3? eye,
  }) {
    if (motion <= 0.0 || impulse.seconds <= 0.0) return;
    final strength = eye == null
        ? (impulse.at == null ? 1.0 : 0.0)
        : impulse.strengthAt(eye);
    if (strength <= 0.0) return;
    if (_live.length >= limit) _live.removeAt(0);
    _live.add(_Live(impulse, _time, _hash3(seed, step, sequence), strength));
  }

  /// Moves the shake on by [dt] seconds and drops what has died away.
  void advance(double dt) {
    if (dt > 0.0) _time += dt;
    _live.removeWhere(
      (_Live live) => _time - live.start >= live.impulse.seconds,
    );
  }

  /// Adds the shake to [shot]: throws the eye and the target together, then
  /// turns the view about the eye.
  void apply(CameraShot shot) {
    if (_live.isEmpty || motion <= 0.0) return;
    var dx = 0.0, dy = 0.0, dz = 0.0, yaw = 0.0, pitch = 0.0;
    for (final live in _live) {
      final age = _time - live.start;
      final left = 1.0 - age / live.impulse.seconds;
      if (left <= 0.0) continue;
      // Squared, so it dies away rather than stopping: a linear fade ends on
      // a visible step down to nothing.
      final envelope = left * left * live.strength * motion;
      final phase = age * live.impulse.frequency;
      final throw_ = live.impulse.amplitude * envelope;
      final turn = live.impulse.angle * envelope;
      dx += _noise(live.seed, 0, phase) * throw_;
      dy += _noise(live.seed, 1, phase) * throw_;
      dz += _noise(live.seed, 2, phase) * throw_;
      yaw += _noise(live.seed, 3, phase) * turn;
      pitch += _noise(live.seed, 4, phase) * turn;
    }

    shot.eye
      ..x += dx
      ..y += dy
      ..z += dz;
    shot.target
      ..x += dx
      ..y += dy
      ..z += dz;
    if (yaw == 0.0 && pitch == 0.0) return;

    final look = shot.target - shot.eye;
    final reach = look.length;
    if (reach <= 1e-9) return;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final x = look.x * c + look.z * s;
    final z = -look.x * s + look.z * c;
    shot.target.setValues(
      shot.eye.x + x,
      shot.eye.y + look.y + math.tan(pitch) * reach,
      shot.eye.z + z,
    );
  }

  /// Drops every impulse. For a cut: a camera that arrives still shaking
  /// reports an event that has been undone.
  void clear() => _live.clear();
}

final class _Live {
  _Live(this.impulse, this.start, this.seed, this.strength);

  final CameraImpulse impulse;

  /// The shake's clock when the impulse began, in seconds.
  final double start;
  final int seed;

  /// How strongly the camera felt it when it began, nought to one.
  final double strength;
}

// --------------------------------------------------------------- the noise

/// One-dimensional gradient noise for one [axis] of an impulse, in about
/// `[-1, 1]`, nought at every whole [t].
double _noise(int seed, int axis, double t) {
  final i = t.floor();
  final f = t - i;
  final g0 = _gradient(seed, axis, i);
  final g1 = _gradient(seed, axis, i + 1);
  final s = f * f * (3.0 - 2.0 * f);
  // Each gradient times the distance to its lattice point, eased across.
  return 2.0 * (g0 * f * (1.0 - s) + g1 * (f - 1.0) * s);
}

double _gradient(int seed, int axis, int i) {
  final h = _hash3(seed, axis, i);
  return (h & 0xffff) / 32767.5 - 1.0;
}

/// Three integers to one, the same in a browser as on a device.
///
/// **Multiplied in sixteen-bit halves.** A browser's integers are doubles,
/// exact to 53 bits, and a 32-bit by 32-bit product is not: multiplied whole,
/// the noise of a replay would be one shape on a phone and another on the
/// web.
int _hash3(int a, int b, int c) {
  var h = 0x811c9dc5;
  for (final v in <int>[a, b, c]) {
    h = _mul32(h ^ (v & 0xffffffff), 0x01000193);
    h ^= h >> 15;
    h = _mul32(h, 0x2c1b3c6d);
    h ^= h >> 12;
  }
  return h & 0xffffffff;
}

int _mul32(int a, int b) {
  final x = a & 0xffffffff;
  final y = b & 0xffffffff;
  final low = (x & 0xffff) * y;
  final high = (((x >> 16) * y) & 0xffff) << 16;
  return (low + high) & 0xffffffff;
}
