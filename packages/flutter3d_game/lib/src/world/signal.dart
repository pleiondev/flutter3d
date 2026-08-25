import 'mechanism.dart';

/// A mechanism that does nothing itself and switches something else on.
///
/// Buttons and trigger volumes are the same thing wearing different clothes:
/// both watch for a condition and relay. Everything except the condition lives
/// here — the target, the once-only latch, the relay itself — so adding a third
/// kind of switch is a class with one method.
abstract base class Signal extends Mechanism {
  Signal({
    super.name,
    required this.target,
    this.once = false,
  });

  /// The [Mechanism.name] this switches on.
  final String target;

  /// Whether it works only the first time. A trap door should not rearm; a
  /// lift call button should.
  final bool once;

  bool _spent = false;

  /// Whether this has already fired and will not fire again.
  bool get isSpent => _spent;

  /// The latch, and nothing else.
  ///
  /// **This is what a save used to lose.** A once-only trigger — the plate in
  /// front of a gate, the volume that fires a cutscene — was not in anybody's
  /// `switch`, so reloading gave it back and it fired a second time. A player
  /// who saved past a one-shot and came back found it waiting.
  @override
  Map<String, Object?> save() => <String, Object?>{'spent': _spent};

  @override
  void restore(Map<String, Object?> from) => _spent = from['spent'] == true;

  /// Passes the activation on to [target].
  ///
  /// The latch closes only on a genuine [Activated]: a player who walked into a
  /// locked door's trigger without the key has not used up their one chance.
  ActivationOutcome fire(Activation by) {
    if (_spent) return const NothingToDo();
    final outcome = world.activate(target, by);
    if (once && outcome is Activated) _spent = true;
    return outcome;
  }
}
