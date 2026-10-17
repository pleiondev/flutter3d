import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';

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
///
/// **The equation is the full one**, θ'' = −(g/L)·sin θ − c·θ', not the
/// small-angle θ'' = −(g/L)·θ, so its period is not quite the textbook's
/// T₀ = 2π√(L/g): a swing grows slower as it grows wider, T ≈ T₀·(1 + θ₀²/16
/// + 11θ₀⁴/3072). From the lab's 0.6 rad that is 2.3 % longer than T₀; from
/// 0.9 rad, 5.3 %. A student timing a swing from the default start against
/// T₀ is two per cent out for that reason, not for the integrator's.
final class PendulumSimulation {
  PendulumSimulation({
    required double lengthMeters,
    this.gravity = standardGravity,
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

  /// Metres per second squared: the pendulum's world's. [standardGravity],
  /// the Earth's, by default; a lab is free to teach the Moon's instead.
  final double gravity;

  /// Linear drag on the angular velocity, 1/s: the angular deceleration per
  /// radian a second of swing, c in θ'' = −(g/L)·sin θ − c·θ'. The swing's
  /// amplitude decays as e^(−c t / 2), so the default 0.02 halves it in about
  /// 69 seconds. Without it the swing never settles, which is a fine model
  /// of a vacuum and a poor model of a classroom demonstration.
  final double damping;

  /// Radians from vertical, positive to one side.
  double theta;

  /// Radians per second.
  double omega;

  /// The string's length, in metres — the one number `edu-04`'s panel
  /// changes. Settable rather than final: the panel sets it live, and the
  /// point of the lab is that the swing responds from that step on rather
  /// than only at the start of a fresh run.
  ///
  /// **A change mid-swing keeps the bob's angular momentum about the
  /// pivot**, m·L²·ω, as a string drawn in or let out through the pivot
  /// does — nothing pushes the bob along its arc while the string slides —
  /// so [omega] is rescaled by (L / L′)²: shortened to half, the swing turns
  /// four times as fast, which is why a child on a swing pumps by standing
  /// up at the bottom. Keeping ω as it was would make energy out of nothing
  /// whenever the string was let out.
  double get lengthMeters => _length;
  set lengthMeters(double value) {
    final next = _checkedLength(value);
    if (next == _length) return;
    final ratio = _length / next;
    omega *= ratio * ratio;
    _length = next;
  }

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
