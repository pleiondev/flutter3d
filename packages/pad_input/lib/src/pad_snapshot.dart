import 'pad_button.dart';

/// What a gamepad is doing, at one instant.
///
/// **Filled in rather than returned**, and reused between frames: this is read
/// once per frame for as long as the game runs, and a fresh object there is an
/// allocation on the only path that is guaranteed to be hot. The engine's
/// `SweepHit` and `GroundSample` are the same shape for the same reason.
///
/// A snapshot rather than a stream of events, which is the whole doctrine of
/// this package: a fixed-step simulation asks what the pad is doing *now*, and
/// a stream would push edge detection into every caller. It is also the only
/// shape the browser can serve honestly, because `navigator.getGamepads()` is
/// itself a poll.
final class PadSnapshot {
  /// Whether a pad was attached when this was filled in.
  ///
  /// A snapshot of a missing pad is all zeroes rather than stale values, which
  /// is what stops a controller whose battery died mid-corner from leaving the
  /// throttle where it was.
  bool connected = false;

  final Map<PadAxis, double> _axes = <PadAxis, double>{
    for (final axis in PadAxis.values) axis: 0.0,
  };
  final Set<String> _down = <String>{};
  final Map<String, double> _pressure = <String, double>{};

  double axis(PadAxis axis) => _axes[axis] ?? 0.0;

  bool down(PadButton button) => _down.contains(button.id);

  /// How hard a button is held, for the two that can answer.
  ///
  /// One for an ordinary button that is down, nought for one that is not, and
  /// the real travel for a trigger. Written this way round so a caller that does
  /// not care about triggers never has to know which buttons are analogue.
  double pressure(PadButton button) =>
      _pressure[button.id] ?? (down(button) ? 1.0 : 0.0);

  /// Every button held, for a rebinding screen listening for the next press.
  Iterable<PadButton> get held => _down.map((String id) => PadButton(id));

  // MARK: - Writing, from a backend

  void setAxis(PadAxis axis, double value) => _axes[axis] = value;

  void setDown(PadButton button, {required bool down, double? pressure}) {
    if (down) {
      _down.add(button.id);
    } else {
      _down.remove(button.id);
    }
    if (pressure != null) {
      _pressure[button.id] = pressure;
    } else {
      _pressure.remove(button.id);
    }
  }

  /// Back to a pad that is doing nothing, still attached.
  void clear() {
    for (final axis in PadAxis.values) {
      _axes[axis] = 0.0;
    }
    _down.clear();
    _pressure.clear();
  }

  /// Back to no pad at all.
  void disconnect() {
    clear();
    connected = false;
  }

  void copyFrom(PadSnapshot other) {
    connected = other.connected;
    for (final axis in PadAxis.values) {
      _axes[axis] = other._axes[axis] ?? 0.0;
    }
    _down
      ..clear()
      ..addAll(other._down);
    _pressure
      ..clear()
      ..addAll(other._pressure);
  }
}
