import 'input_state.dart';

/// The numbers a game lets somebody change while it runs — a jump height, a
/// gravity, an enemy's reaction time — each with the value it starts at.
///
/// **Changed through the input, read by the step.** Somebody drags a value in
/// an inspector; the editor calls `ext.flutter3d.cvar.set`, which calls
/// `InputState.tune`; the next step calls [take] before it simulates and
/// reads the new value through `[]`. The change is on the tape with that step,
/// so a replay changes it at the same moment, and a run tuned while it was
/// played reproduces like any other.
///
/// **Part of the state, so part of the snapshot.** A rewind to before a
/// change has to come back with the old value, or the replay from there runs
/// with a value it did not have. Put [toJson] into the game's snapshot and
/// hand it back to [restore].
///
/// A name the table does not declare is ignored, not added: a stale
/// inspector naming a tunable an edit has since removed should not grow the
/// state of every run it is sent to.
final class Tunables {
  Tunables(Map<String, double> defaults)
    : defaults = Map<String, double>.unmodifiable(defaults),
      _values = Map<String, double>.of(defaults);

  /// What each tunable starts at.
  final Map<String, double> defaults;

  final Map<String, double> _values;

  /// The value of [name] now. Throws for a name the table does not declare,
  /// which is a typo in the step rather than something to default past.
  double operator [](String name) =>
      _values[name] ??
      (throw ArgumentError.value(name, 'name', 'no such tunable'));

  /// Every tunable and its value now.
  Map<String, double> get values => Map<String, double>.unmodifiable(_values);

  /// Takes the tunables [input] set this step. Call once per step, before
  /// anything reads a value, the same place a step reads the rest of its
  /// input.
  void take(InputState input) {
    for (final MapEntry(key: name, :value) in input.tunesThisStep.entries) {
      if (_values.containsKey(name)) _values[name] = value;
    }
  }

  /// The values that differ from [defaults], for a snapshot: a run nobody
  /// tuned adds nothing to its saves.
  Map<String, Object?> toJson() => <String, Object?>{
    for (final MapEntry(key: name, :value) in _values.entries)
      if (value != defaults[name]) name: value,
  };

  /// Puts back what [toJson] wrote; anything it does not name returns to its
  /// default.
  void restore(Map<String, Object?> json) {
    for (final MapEntry(key: name, value: fallback) in defaults.entries) {
      _values[name] = switch (json[name]) {
        final num saved => saved.toDouble(),
        _ => fallback,
      };
    }
  }
}
