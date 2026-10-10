import 'input_state.dart';

/// The numbers a game lets somebody change while it runs — a jump height, a
/// gravity, an enemy's reaction time — each with the value it starts at.
///
/// **Changed through the input, read by the step.** Somebody drags a value in
/// an inspector; the editor calls `ext.flutter3d.cvar.set`, which calls
/// `InputState.tune`; the next step calls [readFrom] before it simulates and
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
///
/// **A map of names to numbers, and that is kept on purpose.** It is what an
/// inspector, a tape and a data plugin (a `.f3dplugin` that names a tunable
/// in text) all speak, and none of them can name a Dart type. Code that
/// declares its own tunables reaches them typed through [Tunable] instead —
/// `jump.of(tunables)` rather than `tunables['jump']` — and both read the
/// same table.
final class Tunables {
  Tunables(Map<String, double> defaults)
    : defaults = Map<String, double>.unmodifiable(defaults),
      _values = Map<String, double>.of(defaults);

  /// A table of [tunables], each starting at its [Tunable.initial]. Throws
  /// an [ArgumentError] for a name two of them share.
  factory Tunables.of(Iterable<Tunable<Object>> tunables) {
    final defaults = <String, double>{};
    for (final tunable in tunables) {
      if (defaults.containsKey(tunable.name)) {
        throw ArgumentError.value(
          tunable.name,
          'tunables',
          'two tunables are named alike',
        );
      }
      defaults[tunable.name] = tunable.initialValue;
    }
    return Tunables(defaults);
  }

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
  void readFrom(InputState input) {
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

/// One tunable by name and by type: what code that declares its own reads
/// instead of a string and a number.
///
/// ```dart
/// static final Tunable<double> jump = Tunable.number('jump', 7.5);
/// static final Tunable<int> lives = Tunable.whole('lives', 3);
/// static final Tunable<bool> fog = Tunable.flag('fog', initial: true);
///
/// final tunables = Tunables.of(<Tunable<Object>>[jump, lives, fog]);
/// // in the step, after tunables.readFrom(input):
/// final height = jump.of(tunables);
/// ```
///
/// **The table underneath is still numbers by name** ([Tunables]), because
/// that is what an inspector, a tape and a data plugin carry; this is the
/// typed door to it, not a second table. A whole number is held as a number
/// and rounded when read, a flag as nought or one.
final class Tunable<T extends Object> {
  Tunable._(this.name, this.initial, this._encode, this._decode);

  /// A number, as the table holds it.
  static Tunable<double> number(String name, double initial) =>
      Tunable<double>._(name, initial, _same, _same);

  /// A whole number: rounded when read, so a value an inspector dragged to
  /// 2.6 reads 3.
  static Tunable<int> whole(String name, int initial) =>
      Tunable<int>._(name, initial, _fromWhole, _toWhole);

  /// A flag: anything but nought reads true.
  static Tunable<bool> flag(String name, {bool initial = false}) =>
      Tunable<bool>._(name, initial, _fromFlag, _toFlag);

  /// Its name in the table, on the tape and in the inspector.
  final String name;

  /// What it starts at.
  final T initial;

  final double Function(T value) _encode;
  final T Function(double stored) _decode;

  /// [initial] as the table holds it: a plain number, in whatever unit the
  /// tunable means (a flag is nought or one).
  double get initialValue => _encode(initial);

  /// Its value in [tunables] now. Throws an [ArgumentError] when the table
  /// does not declare it.
  T of(Tunables tunables) => _decode(tunables[name]);

  /// Sets it to [value] from the next step on, through [input], so the
  /// change is on the tape with that step (`InputState.tune`).
  void set(InputState input, T value) => input.tune(name, _encode(value));

  static double _same(double value) => value;
  static double _fromWhole(int value) => value.toDouble();
  static int _toWhole(double stored) => stored.round();
  static double _fromFlag(bool value) => value ? 1.0 : 0.0;
  static bool _toFlag(double stored) => stored != 0.0;

  @override
  String toString() => 'Tunable<$T>($name)';
}
