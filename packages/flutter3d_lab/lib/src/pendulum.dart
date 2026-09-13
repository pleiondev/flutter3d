import 'package:flutter3d_sim/flutter3d_sim.dart' show Portable;

/// `edu-04`'s own worked example: a gravity pendulum, simple enough that a
/// student changing one number — the length of the string — visibly changes
/// how the run unfolds, and small enough that this file owes nothing to
/// [flutter3d_physics]'s general rigid-body machinery for it.
///
/// Semi-implicit (symplectic) Euler, the same order of integrator
/// [GameSimulation] already steps everything else with: velocity updates
/// first, position from the updated velocity. Plain Euler drifts energy in
/// visibly over hundreds of steps; this does not, and a lab a student runs
/// for a full minute needs that.
final class PendulumSimulation {
  PendulumSimulation({
    required double lengthMeters,
    this.gravity = 9.81,
    this.damping = 0.02,
    double startAngle = 0.6,
  }) : _length = _checkedLength(lengthMeters),
       theta = startAngle,
       omega = 0.0;

  static double _checkedLength(double value) {
    if (value <= 0.0) {
      throw ArgumentError.value(
        value,
        'lengthMeters',
        'a pendulum needs a positive length',
      );
    }
    return value;
  }

  double _length;

  /// Metres per second squared. Earth's by default; a lab is free to teach
  /// the Moon's instead.
  final double gravity;

  /// Linear drag on the angular velocity — without it the swing never
  /// settles, which is a fine model of a vacuum and a poor model of a
  /// classroom demonstration.
  final double damping;

  /// Radians from vertical, positive to one side.
  double theta;

  /// Radians per second.
  double omega;

  /// The string's length, in metres — the one number `edu-04`'s panel
  /// changes. Settable rather than final: the panel sets it live, and the
  /// point of the lab is that the swing responds from that step on rather
  /// than only at the start of a fresh run.
  double get lengthMeters => _length;
  set lengthMeters(double value) => _length = _checkedLength(value);

  /// Advances the pendulum by [dt] seconds, fixed-step, the same convention
  /// `ai-01`'s `Playtest` and every genre's `GameSimulation` already use.
  void step(double dt) {
    final alpha = -(gravity / _length) * Portable.sin(theta) - damping * omega;
    omega += alpha * dt;
    theta += omega * dt;
  }

  /// Everything a run needs to tell two pendulums apart — fed to
  /// `StateDigest.of` the same way any genre's own state is, and to
  /// [Snapshot] as the state a run starts from.
  Map<String, Object?> get state => <String, Object?>{
    'theta': theta,
    'omega': omega,
    'length': _length,
  };
}
