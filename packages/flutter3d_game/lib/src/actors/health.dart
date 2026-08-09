/// How much punishment something can take.
///
/// Small enough to look trivial, and it is not: the one thing it has to get
/// right is that death happens exactly once. Eight shotgun pellets landing in
/// the same monster on the same step is one death, and a health class that
/// reports the transition on every subsequent hit produces eight death
/// animations, eight corpses and eight counts towards the level's kill total.
final class Health {
  Health(this.maximum, {double? current, this.armour = 0.0})
      : assert(maximum > 0.0),
        _current = current ?? maximum;

  final double maximum;
  double _current;

  /// Absorbs part of the damage and is spent doing so.
  double armour;

  /// Fraction of incoming damage armour takes, while it lasts.
  static const double armourShare = 1.0 / 3.0;

  double get current => _current;
  bool get isAlive => _current > 0.0;
  bool get isDead => !isAlive;

  /// Whether the death transition has already been reported.
  bool _mourned = false;

  /// Applies [amount] and returns true on the hit that killed — once, and only
  /// for that hit.
  bool damage(double amount) {
    if (amount <= 0.0 || _mourned) return false;

    var remaining = amount;
    if (armour > 0.0) {
      final absorbed = _min(armour, amount * armourShare);
      armour -= absorbed;
      remaining -= absorbed;
    }

    _current -= remaining;
    if (_current > 0.0) return false;

    _current = 0.0;
    _mourned = true;
    return true;
  }

  /// Tops up, never past the maximum. Returns how much was actually given, so
  /// a pickup can refuse to be consumed when it would do nothing.
  double heal(double amount) {
    if (amount <= 0.0 || _mourned) return 0.0;
    final given = _min(amount, maximum - _current);
    _current += given;
    return given;
  }

  /// Brings something back to life, for a respawn.
  void revive({double? to}) {
    _current = to ?? maximum;
    _mourned = false;
  }

  static double _min(double a, double b) => a < b ? a : b;
}
