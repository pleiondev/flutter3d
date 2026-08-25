/// A named point inside a fixed step, which a game announces as it reaches it.
///
/// **A value class over a string, for the same reason `GameAction` is one.** The
/// engine cannot name the interesting moments in a step it does not own: a
/// shooter has an "after the weapons fired" and a racer does not, and an enum
/// here would mean the day a genre wanted its own phase it had to edit this
/// package. Two shared ones are declared because every genre has them; the rest
/// belong to whichever package owns the step.
final class StepPhase {
  const StepPhase(this.name);

  /// The top of the step, after the last one's latches are cleared and before
  /// any input is read.
  static const StepPhase begin = StepPhase('begin');

  /// The bottom, after the world has settled and the game state is resolved.
  static const StepPhase end = StepPhase('end');

  final String name;

  @override
  bool operator ==(Object other) => other is StepPhase && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'StepPhase($name)';
}

/// Work an application adds to a step it does not own.
typedef StepSystem = void Function(double dt);

/// Systems an application adds to a genre's step, by phase.
///
/// **The plugin boundary for behaviour, and the last of the three.** Reading a
/// model has `ModelDecoder`, reading a material has `MaterialDecoder`, and this
/// is the one for the simulation itself: a game that wants a rule the genre
/// package never imagined — a curse that ticks, a score that decays, a bespoke
/// hazard — registers it here instead of forking `step`.
///
/// **Announced by the genre, not enforced by this class.** `WorldStep` reached
/// the same conclusion about the six calls it holds and for the same reason: a
/// single `run(dt)` with the game in the middle could not be written honestly,
/// because the platformer steps its actors before the index and the shooter
/// steps them after everything, and both arguments are good. So a phase here is
/// a point a genre *says* it has reached, and what this class contributes is
/// that everything hanging off that point runs in a defined order.
///
/// ## The order is the whole of the contract
///
/// A step reaches for no clock and no loose dice (ARCHITECTURE.md §9.3), and a system added
/// here is part of the step: two runs of the same tape must call the same
/// systems in the same order or the determinism the tape rests on is gone. So
/// systems run by [SystemRegistration.order] and then by the order they were
/// added — never by whatever order a hash map happens to hand back, which Dart
/// does not promise is the same from one run to the next.
///
/// [order] exists because "added first" is not always the answer: a system that
/// must observe what every other system did cannot be registered before code it
/// does not know about. Ties are broken by registration, so the common case
/// needs no numbers at all.
final class StepSystems {
  final Map<String, List<SystemRegistration>> _byPhase =
      <String, List<SystemRegistration>>{};
  int _added = 0;

  /// Whether anything is registered. A genre checks this to skip announcing.
  bool get isEmpty => _byPhase.isEmpty;

  /// Adds [system] to [phase], returning the handle that removes it again.
  ///
  /// Lower [order] runs first; equal orders run in the order they were added.
  SystemRegistration add(
    StepPhase phase,
    StepSystem system, {
    int order = 0,
    String? label,
  }) {
    final registration = SystemRegistration._(
      phase: phase,
      system: system,
      order: order,
      sequence: _added++,
      label: label,
    );
    final list = _byPhase.putIfAbsent(phase.name, () => <SystemRegistration>[]);
    // Inserted in place rather than sorted on every run: a step runs sixty
    // times a second and registration happens when a level loads.
    var at = list.length;
    while (at > 0 && _before(registration, list[at - 1])) {
      at--;
    }
    list.insert(at, registration);
    return registration;
  }

  /// Removes a system added earlier. Removing one that is already gone is not
  /// an error — a level torn down twice should not be.
  void remove(SystemRegistration registration) {
    _byPhase[registration.phase.name]?.remove(registration);
  }

  void clear() => _byPhase.clear();

  /// Runs everything registered for [phase]. Called by the genre's `step`.
  ///
  /// **Iterated over a copy**, so a system that adds or removes one — a rule
  /// that fires once and unregisters itself is the ordinary case — does not
  /// mutate the list being walked.
  void run(StepPhase phase, double dt) {
    final list = _byPhase[phase.name];
    if (list == null || list.isEmpty) return;
    for (final registration in List<SystemRegistration>.of(list)) {
      registration.system(dt);
    }
  }

  /// What is registered for [phase], in the order it will run. For tests and
  /// for a diagnostic overlay that answers "what is running in this step".
  List<SystemRegistration> forPhase(StepPhase phase) =>
      List<SystemRegistration>.unmodifiable(
          _byPhase[phase.name] ?? const <SystemRegistration>[]);

  static bool _before(SystemRegistration a, SystemRegistration b) =>
      a.order != b.order ? a.order < b.order : a.sequence < b.sequence;
}

/// One registered system, and the handle that removes it.
final class SystemRegistration {
  const SystemRegistration._({
    required this.phase,
    required this.system,
    required this.order,
    required this.sequence,
    this.label,
  });

  final StepPhase phase;
  final StepSystem system;
  final int order;

  /// When this was added, used only to break ties in [order].
  final int sequence;

  /// A name for a diagnostic overlay. Nothing depends on it.
  final String? label;

  @override
  String toString() => 'SystemRegistration(${label ?? 'unnamed'} '
      'in ${phase.name}, order $order)';
}
