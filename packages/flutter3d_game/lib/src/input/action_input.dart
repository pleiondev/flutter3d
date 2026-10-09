import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'action_map.dart';
import 'bindings.dart';

/// Turns what sources are doing into action values, for the bindings of an
/// [ActionMap] that are not buttons.
///
/// **The arithmetic every device shares**, which is why it is not in any of
/// them: `DesktopInput` reports a key going down, `PadInput` a button, an
/// axis and a stick, and from there the composites, the dead zones, the
/// sensitivity and the inversion are the same sums whichever device spoke.
/// Buttons stay where they were — the devices press and release them through
/// [ActionMap.buttons] as they always have.
///
/// ## Two sources on one action
///
/// The largest wins: `I` held on the keyboard and the pad's stick half way
/// on the same lift give the lift at one, not at one and a half and not at
/// whichever reported last. A pair is compared by its length.
final class ActionInput {
  ActionInput({required this.state, required this.map});

  final InputState state;
  final ActionMap map;

  /// Digital sources that are down.
  final Set<InputSource> _down = <InputSource>{};

  /// The last reading of each one-number analogue source.
  final Map<InputSource, double> _analogue = <InputSource, double>{};

  /// The last reading of each two-number analogue source.
  final Map<InputSource, (double, double)> _pairs =
      <InputSource, (double, double)>{};

  /// The actions this has written, so [letGo] clears exactly those.
  final Set<InputAction<Object>> _written = <InputAction<Object>>{};

  /// Whether [source] reaches an action through this — see [ActionMap.routes].
  bool routes(InputSource source) => map.routes(source);

  /// [source] went down. Repeats are ignored: a key's auto-repeat is not a
  /// second press.
  void sourceDown(InputSource source) {
    if (_down.add(source)) _resolveFor(source);
  }

  void sourceUp(InputSource source) {
    if (_down.remove(source)) _resolveFor(source);
  }

  /// [source] reads [value] — a trigger, one axis of a stick.
  void sourceValue(InputSource source, double value) {
    if (_analogue[source] == value) return;
    _analogue[source] = value;
    _resolveFor(source);
  }

  /// [source] reads ([x], [y]) — a whole stick.
  void sourcePair(InputSource source, double x, double y) {
    if (_pairs[source] == (x, y)) return;
    _pairs[source] = (x, y);
    _resolveFor(source);
  }

  /// Motion since the last call on [source], shaped by its binding to
  /// [action] — the mouse's sensitivity and inverted look — or as it came
  /// when no binding names that source.
  (double, double) shapeDelta(
    DualAxisAction action,
    InputSource source,
    double dx,
    double dy,
  ) {
    for (final binding in map.axisBindings) {
      if (binding case DualAxisBinding(
        action: final bound,
        source: final from,
        :final tuning,
      ) when bound == action && from == source) {
        return tuning.shapeDelta(dx, dy);
      }
    }
    return (dx, dy);
  }

  /// Lets go of every source and every action this wrote — a pad unplugged,
  /// a window that lost focus.
  void letGo() {
    _down.clear();
    _analogue.clear();
    _pairs.clear();
    for (final action in _written) {
      switch (action) {
        case final AxisAction axis:
          state.clearAxis(axis);
        case final DualAxisAction pair:
          state.clearDualAxis(pair);
        case GameAction():
      }
    }
    _written.clear();
  }

  void _resolveFor(InputSource source) {
    final actions = <InputAction<Object>>{
      for (final binding in map.axisBindings)
        if (binding.sources.contains(source)) binding.action,
    };
    actions.forEach(_resolve);
  }

  double _held(InputSource source) => _down.contains(source) ? 1.0 : 0.0;

  void _resolve(InputAction<Object> action) {
    final bindings = map.axisBindings.where((b) => b.action == action);
    switch (action) {
      case final AxisAction axis:
        final value = bindings.fold<double>(0.0, (best, binding) {
          final v = switch (binding) {
            AxisComposite(:final negative, :final positive) =>
              _held(positive) - _held(negative),
            AxisBinding(:final source, :final tuning) => tuning.shape(
              _analogue[source] ?? 0.0,
            ),
            _ => 0.0,
          };
          return v.abs() > best.abs() ? v : best;
        });
        _written.add(axis);
        state.setAxis(axis, value);
      case final DualAxisAction pair:
        if (pair.isDelta) return; // Motion goes through [shapeDelta].
        final (x, y) = bindings.fold<(double, double)>((0.0, 0.0), (
          best,
          binding,
        ) {
          final v = switch (binding) {
            DualAxisComposite(
              :final up,
              :final down,
              :final left,
              :final right,
            ) =>
              _unit(_held(right) - _held(left), _held(up) - _held(down)),
            DualAxisBinding(:final source, :final tuning) =>
              switch (_pairs[source]) {
                (final x, final y) => tuning.shapePair(x, y),
                null => (0.0, 0.0),
              },
            _ => (0.0, 0.0),
          };
          return _length(v) > _length(best) ? v : best;
        });
        _written.add(pair);
        state.setDualAxis(pair, x, y);
      case GameAction():
      // Buttons are the devices' own, through [ActionMap.buttons].
    }
  }

  static double _length((double, double) v) =>
      math.sqrt(v.$1 * v.$1 + v.$2 * v.$2);

  /// No longer than one, so a diagonal of two keys is not faster than one.
  static (double, double) _unit(double x, double y) {
    final length = _length((x, y));
    return length > 1.0 ? (x / length, y / length) : (x, y);
  }
}
