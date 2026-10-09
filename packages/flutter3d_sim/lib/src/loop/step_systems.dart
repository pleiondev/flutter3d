import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show orderByConstraints;

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

/// What a [StepSystem] is told about the step it is running inside.
///
/// **One object rather than a parameter list, so this can grow.** A function
/// type is frozen the moment it is published: widening
/// `void Function(double dt)` to pass anything else — the step's index, the
/// events buffer, the phase it is in — is a breaking change for every system
/// anybody has written. Adding a field here is not.
///
/// **Reused between calls, never held.** One instance per [StepSystems], its
/// fields rewritten before each call, because a step runs several phases sixty
/// times a second and a fresh object per call would be an allocation on a path
/// this package refuses to allocate on. A system that keeps one keeps a
/// reference to whatever the next phase writes into it — copy what you need.
final class StepContext {
  StepContext._();

  /// Seconds this step advances the world by. Fixed; see `EngineLoop.stepSeconds`.
  double dt = 0.0;

  /// Which phase is running. A system registered for two phases can tell them
  /// apart without being registered twice with two closures.
  StepPhase phase = const StepPhase('');
}

/// Work an application adds to a step it does not own.
typedef StepSystem = void Function(StepContext step);

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
/// A step reaches for no clock and no loose dice (ARCHITECTURE.md §9.3), and a
/// system added here is part of the step: two runs of the same tape must call
/// the same systems in the same order or the determinism the tape rests on is
/// gone. So systems run in the order they were added, moved only by named
/// `after` and `before` constraints — **the same rule the engine's loop
/// orders its own systems by** (`LoopRegistry.addSystem`), sorted by the same
/// `orderByConstraints` — and never by whatever order a hash map happens to
/// hand back.
///
/// A constraint names another system's [SystemRegistration.label] in the same
/// phase. One naming a system that is not registered is ignored, so "before
/// the fire rule" from a rule that works with or without it needs no check; a
/// cycle is an error naming every member of it.
final class StepSystems {
  final Map<String, List<SystemRegistration>> _byPhase =
      <String, List<SystemRegistration>>{};
  final Map<String, List<SystemRegistration>> _ordered =
      <String, List<SystemRegistration>>{};
  int _added = 0;

  /// Whether anything is registered. A genre checks this to skip announcing.
  bool get isEmpty => _byPhase.values.every((list) => list.isEmpty);

  /// Adds [system] to [phase], returning the handle that removes it again.
  ///
  /// [label] names it, for a constraint in another system and a diagnostic
  /// overlay; unique among [phase]'s systems when given. [after] and
  /// [before] name the systems of [phase] it runs after and before; where
  /// they leave a choice, the order of adding decides.
  ///
  /// Throws an [ArgumentError] for a [label] [phase] already has.
  SystemRegistration add(
    StepPhase phase,
    StepSystem system, {
    String? label,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final list = _byPhase.putIfAbsent(phase.name, () => <SystemRegistration>[]);
    if (label != null && list.any((r) => r.label == label)) {
      throw ArgumentError.value(
        label,
        'label',
        'a system labelled "$label" is already in ${phase.name}',
      );
    }
    final registration = SystemRegistration._(
      phase: phase,
      system: system,
      sequence: _added++,
      label: label,
      after: List<String>.unmodifiable(after),
      before: List<String>.unmodifiable(before),
    );
    list.add(registration);
    // Sorted when the phase next runs rather than here: a step runs sixty
    // times a second and registration happens when a level loads.
    _ordered.remove(phase.name);
    return registration;
  }

  /// Removes a system added earlier. Removing one that is already gone is not
  /// an error — a level torn down twice should not be.
  void remove(SystemRegistration registration) {
    final list = _byPhase[registration.phase.name];
    if (list == null || !list.remove(registration)) return;
    _ordered.remove(registration.phase.name);
  }

  void clear() {
    _byPhase.clear();
    _ordered.clear();
  }

  /// Runs everything registered for [phase]. Called by the genre's `step`.
  ///
  /// **Iterated over a copy**, so a system that adds or removes one — a rule
  /// that fires once and unregisters itself is the ordinary case — does not
  /// mutate the list being walked.
  void run(StepPhase phase, double dt) {
    final list = _byPhase[phase.name];
    if (list == null || list.isEmpty) return;
    final ordered = _orderOf(phase.name, list);
    _context
      ..dt = dt
      ..phase = phase;
    for (final registration in List<SystemRegistration>.of(ordered)) {
      registration.system(_context);
    }
  }

  /// The scratch handed to every system. See [StepContext].
  final StepContext _context = StepContext._();

  /// What is registered for [phase], in the order it will run. For tests and
  /// for a diagnostic overlay that answers "what is running in this step".
  List<SystemRegistration> forPhase(StepPhase phase) {
    final list = _byPhase[phase.name];
    if (list == null || list.isEmpty) return const <SystemRegistration>[];
    return List<SystemRegistration>.unmodifiable(_orderOf(phase.name, list));
  }

  List<SystemRegistration> _orderOf(
    String phase,
    List<SystemRegistration> list,
  ) => _ordered[phase] ??= orderByConstraints<SystemRegistration>(
    List<SystemRegistration>.of(list),
    nameOf: (r) => r.label ?? '#${r.sequence}',
    after: (r) => r.after,
    before: (r) => r.before,
    what: 'systems in step phase $phase',
  );
}

/// One registered system, and the handle that removes it.
final class SystemRegistration {
  const SystemRegistration._({
    required this.phase,
    required this.system,
    required this.sequence,
    required this.after,
    required this.before,
    this.label,
  });

  final StepPhase phase;
  final StepSystem system;

  /// When this was added, which decides where the constraints leave a
  /// choice.
  final int sequence;

  /// The systems of [phase] this runs after, by label.
  final List<String> after;

  /// The systems of [phase] this runs before, by label.
  final List<String> before;

  /// The name a constraint and a diagnostic overlay know it by.
  final String? label;

  @override
  String toString() =>
      'SystemRegistration(${label ?? 'unnamed'} in ${phase.name})';
}
