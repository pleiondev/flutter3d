import 'dart:math' as math;

/// A full-screen flash that fades: how bright it is now, between nought and
/// whatever it was last fired at.
///
/// **How bright is the player's answer, not the game's.** A `Reaction` says
/// only *that* the screen should flash; the game fires this at the player's
/// own setting — nought for someone a flash on every hit would hurt — and a
/// HUD reads [value]. Faded by the step, so it lasts as long on a 120 Hz
/// display as on a 60 Hz one.
final class ScreenFlash {
  ScreenFlash({required this.fadePerSecond});

  /// How much of a full flash fades in a second: 4 is a quarter of a second
  /// from full to nothing.
  final double fadePerSecond;

  double _value = 0.0;

  /// How bright it is now, as a fraction of a full flash (one).
  double get value => _value;

  /// Lights it at [amount], the player's own setting for flashes.
  void fire(double amount) => _value = amount;

  /// Fades it by [dt] seconds. Called once a step.
  void fade(double dt) {
    if (_value > 0.0) _value = math.max(0.0, _value - dt * fadePerSecond);
  }

  /// Out at once, for a level change.
  void clear() => _value = 0.0;
}
