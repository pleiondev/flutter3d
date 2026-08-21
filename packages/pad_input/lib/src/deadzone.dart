import 'dart:math' as math;

/// How much of a stick's travel is thrown away as rest.
///
/// **Every gamepad reports a stick that is not quite centred.** A worn thumb
/// stick at rest reads a few hundredths off zero, and a game that believes it
/// walks the player into a wall while nobody is touching the controller. So the
/// middle of the travel is discarded.
///
/// ## Radial, and rescaled — the two ways this is written wrongly
///
/// **Radial**, not per-axis: applying a dead zone to x and y separately carves a
/// square hole out of a round stick, so a stick pushed diagonally by a little is
/// live while the same distance straight up is dead. The magnitude is what rests
/// near zero, so the magnitude is what is tested.
///
/// **Rescaled**, so that the first live value is nought and not the dead zone
/// itself. Without the rescale a stick leaving a 0.15 zone jumps straight to
/// 0.15, and that discontinuity reads as the character twitching into motion —
/// which is the single most common way a dead zone is got wrong, and it looks
/// like a physics bug rather than an input one.
///
/// A trigger is one-sided and gets the same treatment along its single axis.
final class Deadzone {
  const Deadzone({this.stick = 0.15, this.trigger = 0.06})
      : assert(stick >= 0.0 && stick < 1.0),
        assert(trigger >= 0.0 && trigger < 1.0);

  /// The fraction of a stick's travel that counts as centred.
  ///
  /// **The default is a starting point, not a measurement.** A number for a
  /// dead zone can only be chosen with a controller in hand, and the acceptance
  /// for this package says so: the player gets a slider, and what it should
  /// default to is settled by moving it.
  final double stick;

  /// The same for a trigger, which rests at zero and only travels one way.
  final double trigger;

  Deadzone copyWith({double? stick, double? trigger}) => Deadzone(
        stick: stick ?? this.stick,
        trigger: trigger ?? this.trigger,
      );

  /// Applies the stick dead zone to a pair of axes, writing the result back.
  ///
  /// In place because this runs once per stick per frame and a fresh pair of
  /// doubles on that path is an allocation nobody needs.
  void applyToStick(List<double> xy) {
    final x = xy[0];
    final y = xy[1];
    final magnitude = math.sqrt(x * x + y * y);
    if (magnitude <= stick || magnitude <= 0.0) {
      xy[0] = 0.0;
      xy[1] = 0.0;
      return;
    }
    // The rescale: the live range is remapped onto the whole of nought to one,
    // and the direction is untouched.
    final wanted = math.min(1.0, (magnitude - stick) / (1.0 - stick));
    final scale = wanted / magnitude;
    xy[0] = x * scale;
    xy[1] = y * scale;
  }

  /// Applies the trigger dead zone to one value in `[0, 1]`.
  double applyToTrigger(double value) {
    if (value <= trigger) return 0.0;
    return math.min(1.0, (value - trigger) / (1.0 - trigger));
  }
}
