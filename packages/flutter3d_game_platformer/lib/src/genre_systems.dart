/// The systems a game hangs on a genre's own moments inside its step.
///
/// **This package's own, and not exported.** Every genre carries the same
/// small table (the shooter, the racer and the strategy game each have a
/// copy): its simulation is what a game registers on, through `addSystem`,
/// and this is what that call keeps. The engine's loop orders its systems by
/// the same rule (`LoopRegistry.addSystem`), with the same
/// `orderByConstraints`, so a system moves between a genre's moment and a
/// loop phase without changing what it is.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// Systems by the genre's phases, each run in the order it was added, moved
/// only by named `after` and `before` constraints within its phase.
final class GenreSystems {
  /// A table over [phases], the moments the genre announces; [publish] is
  /// where a system's event goes when the genre is stepped without a loop.
  GenreSystems(this.phases, {required this.publish});

  /// The phases a system may be added to, in the order the step reaches them.
  final List<LoopPhase> phases;

  /// Where [LoopContext.publish] goes when the step was not run by a loop.
  final void Function(BusEvent event) publish;

  late final _OwnContext _own = _OwnContext(publish);
  final _InLoopContext _inLoop = _InLoopContext();
  final List<_Entry> _entries = <_Entry>[];
  final Map<String, List<_Entry>> _ordered = <String, List<_Entry>>{};

  /// Whether no system is added.
  bool get isEmpty => _entries.isEmpty;

  /// Adds [system] to [phase] under [name]; see the genre's `addSystem`.
  Registration add(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    if (!phases.contains(phase)) {
      throw ArgumentError.value(
        phase.name,
        'phase',
        'the step has no phase "${phase.name}"; its phases are '
            '${phases.map((LoopPhase p) => p.name).join(', ')}',
      );
    }
    if (_entries.any((_Entry e) => e.name == name)) {
      throw ArgumentError.value(
        name,
        'name',
        'a system named "$name" is already added',
      );
    }
    final entry = _Entry(
      name,
      phase,
      system,
      List<String>.unmodifiable(after),
      List<String>.unmodifiable(before),
    );
    _entries.add(entry);
    // Sorted when the phase next runs: a step runs sixty times a second,
    // and systems are added when a level loads.
    _ordered.remove(phase.name);
    return Registration(() {
      if (_entries.remove(entry)) _ordered.remove(phase.name);
    });
  }

  /// The names of [phase]'s systems, in the order they run.
  List<String> namesIn(LoopPhase phase) => <String>[
    for (final e in _orderOf(phase)) e.name,
  ];

  /// Runs [phase]'s systems for a step of [dt] seconds, the [step]th of the
  /// run, inside [outer] when a loop is stepping the genre.
  ///
  /// **Over a copy**, so a system that removes itself — a rule that fires
  /// once — does not change the list being walked.
  void run(
    LoopPhase phase,
    double dt, {
    required int step,
    LoopContext? outer,
  }) {
    final ordered = _orderOf(phase);
    if (ordered.isEmpty) return;
    // One context of each kind, rewritten before each phase: a step runs
    // several phases sixty times a second, and a fresh object per call is
    // an allocation on that path. A system copies what it keeps.
    final LoopContext context;
    if (outer == null) {
      context = _own
        ..phase = phase
        ..dt = dt
        ..step = step;
    } else {
      context = _inLoop
        ..outer = outer
        ..phase = phase;
    }
    for (final entry in List<_Entry>.of(ordered)) {
      entry.system(context);
    }
  }

  List<_Entry> _orderOf(LoopPhase phase) =>
      _ordered[phase.name] ??= orderByConstraints<_Entry>(
        <_Entry>[
          for (final e in _entries)
            if (e.phase == phase) e,
        ],
        nameOf: (_Entry e) => e.name,
        after: (_Entry e) => e.after,
        before: (_Entry e) => e.before,
        what: 'systems in ${phase.name}',
      );
}

final class _Entry {
  _Entry(this.name, this.phase, this.system, this.after, this.before);

  final String name;
  final LoopPhase phase;
  final LoopSystem system;
  final List<String> after;
  final List<String> before;
}

/// The loop's own context, with the genre's moment as its phase.
final class _InLoopContext extends LoopContext {
  _InLoopContext();

  LoopContext? outer;

  @override
  LoopPhase phase = LoopPhase.physics;

  LoopContext get _outer => outer!;

  @override
  int get step => _outer.step;

  /// The loop's step, in seconds.
  @override
  double get dt => _outer.dt;

  /// The loop's wall-clock seconds: nought in a step phase.
  @override
  double get realDt => _outer.realDt;

  /// The loop's fraction between two steps: nought in a step phase.
  @override
  double get alpha => _outer.alpha;

  @override
  bool get isResimulated => _outer.isResimulated;

  @override
  void publish(BusEvent event) => _outer.publish(event);

  @override
  SimWorld get world => _outer.world;

  @override
  PublishedState get published => _outer.published;
}

/// A step run without a loop: a test's, a headless game's.
final class _OwnContext extends LoopContext {
  _OwnContext(this._publish);

  @override
  LoopPhase phase = LoopPhase.physics;

  /// The step, in seconds.
  @override
  double dt = 0.0;

  @override
  int step = 0;

  final void Function(BusEvent event) _publish;

  /// No wall clock inside a step: nought seconds.
  @override
  double get realDt => 0.0;

  /// No frame between steps: a fraction of nought.
  @override
  double get alpha => 0.0;

  @override
  bool get isResimulated => false;

  @override
  void publish(BusEvent event) => _publish(event);
}
