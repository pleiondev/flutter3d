import 'dart:collection';
import 'dart:math' as math;

/// What is running on somebody, and for how much longer.
///
/// **Every genre wants this and the shooter had written it.** A power-up is a
/// name and a countdown: a platformer's shield, a racer's boost, a crypt's
/// berserk are the same bookkeeping asked three times, and two of the three had
/// nothing. It lives here rather than in a genre because none of it is about
/// weapons, or running, or driving.
///
/// **Names rather than an enum**, which is the same reading the boundary audit
/// gave everything else: what powers a game has is the game's list, and this
/// only counts down what it is handed. See `doc/boundary-0.5.0.md`.
///
/// **Refreshed rather than stacked.** Picking up a second of something already
/// running sets the clock to whichever is longer instead of adding — so a
/// player who hoards four of them gets thirty seconds and not two minutes,
/// which is the difference between a power-up and a savings account.
final class Powers {
  /// Seconds left on each, by name. Empty when nothing is running.
  Map<String, double> get remaining =>
      UnmodifiableMapView<String, double>(_running);
  final Map<String, double> _running = <String, double>{};

  /// Whether [power] is running.
  bool has(String power) => (_running[power] ?? 0.0) > 0.0;

  /// How much longer [power] has, or zero when it is not running.
  double remainingOf(String power) => _running[power] ?? 0.0;

  /// Starts or refreshes one. Never stacks; see the class doc.
  void empower(String power, double seconds) {
    if (seconds <= 0.0) return;
    _running[power] = math.max(_running[power] ?? 0.0, seconds);
  }

  /// Ends one now, whatever was left on it.
  void revoke(String power) => _running.remove(power);

  /// Counts everything down and drops what has run out.
  ///
  /// Returns the names that ended this step, so a game can say so — which is
  /// the moment a player notices, and the one a countdown on a HUD cannot
  /// report because it is at nought on the frame after as well.
  List<String> step(double dt) {
    if (_running.isEmpty || dt <= 0.0) return const <String>[];
    List<String>? ended;
    // Over a copy of the names: expiring one removes it.
    for (final power in _running.keys.toList(growable: false)) {
      final left = _running[power]! - dt;
      if (left > 0.0) {
        _running[power] = left;
        continue;
      }
      _running.remove(power);
      (ended ??= <String>[]).add(power);
    }
    return ended ?? const <String>[];
  }

  /// Forgets everything, for a run starting over.
  void clear() => _running.clear();

  Map<String, Object?> save() => <String, Object?>{..._running};

  void restore(Object? from) {
    _running.clear();
    if (from is! Map) return;
    for (final entry in from.entries) {
      final name = entry.key;
      final left = entry.value;
      if (name is String && left is num && left > 0.0) {
        _running[name] = left.toDouble();
      }
    }
  }
}
