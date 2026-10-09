import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'ecs.dart';
import 'events.dart';
import 'registration.dart';
import 'simulation.dart';

/// Whether a phase runs inside the fixed step or once a frame.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1): a
/// later minor may add a kind — a phase run once per network tick, say —
/// and a `switch` written against two values would break on it.
final class PhaseKind {
  const PhaseKind._(this.name);

  /// Inside every fixed step, at the world's step rate. Deterministic: it
  /// reads no clock and no loose dice, and two runs of one tape call the
  /// same systems in the same order.
  static const PhaseKind step = PhaseKind._('step');

  /// Once a displayed frame, after the frame's steps: animation, sound,
  /// camera, drawing, interface.
  static const PhaseKind frame = PhaseKind._('frame');

  final String name;

  @override
  String toString() => name;
}

/// A named stretch of the loop that systems are added to.
///
/// **A name rather than an enum**, for the reason `StepPhase` and
/// `GameAction` are names: a genre has moments the engine cannot list, and
/// a plugin adds them with `LoopRegistry.addPhase` between the engine's.
/// A name is unique across both kinds — a step phase and a frame phase may
/// not share one, since a constraint names a phase without its kind.
final class LoopPhase {
  const LoopPhase.step(this.name) : kind = PhaseKind.step;
  const LoopPhase.frame(this.name) : kind = PhaseKind.frame;

  // The engine's step phases, in the order they run.

  /// Input for this step is in place: a tape has been applied or the
  /// devices read, and the latches are set.
  static const LoopPhase input = LoopPhase.step('input');

  /// Doors, lifts and what else the level drives, before anything sweeps
  /// against them.
  static const LoopPhase movers = LoopPhase.step('movers');

  /// The bodies, the broadphase and the overlaps.
  static const LoopPhase physics = LoopPhase.step('physics');

  /// The world's fields: heat, water, wind, fire — whatever spreads through
  /// the world after the bodies have moved and before the rules read it.
  ///
  /// **Named for what runs in it, not for a package.** It was `elements`
  /// until 1.0.0-rc.1, the name of the one package that filled it; a phase
  /// every simulation of a field shares is the engine's, and its name says
  /// so. A loop still finds it by the old name ([formerNames]).
  static const LoopPhase fields = LoopPhase.step('fields');

  /// [fields], by the name it had.
  @Deprecated('Use LoopPhase.fields. Deprecated in 1.0.0, removed in 2.0.0.')
  static const LoopPhase elements = fields;

  /// The game's rules: damage, scoring, win and lose.
  static const LoopPhase rules = LoopPhase.step('rules');

  /// The step's outcome is read and published; nothing after this changes
  /// the world.
  static const LoopPhase publish = LoopPhase.step('publish');

  // The engine's frame phases, in the order they run.

  /// Skinned poses, particles and anything else that moves between steps.
  static const LoopPhase animate = LoopPhase.frame('animate');

  /// Sounds started by what the steps did, and the listener moved.
  static const LoopPhase audio = LoopPhase.frame('audio');

  /// The camera placed for this frame.
  static const LoopPhase camera = LoopPhase.frame('camera');

  /// The frame drawn.
  static const LoopPhase render = LoopPhase.frame('render');

  /// The interface over it.
  static const LoopPhase ui = LoopPhase.frame('ui');

  /// The engine's step phases, in order.
  static const List<LoopPhase> stepPhases = <LoopPhase>[
    input,
    movers,
    physics,
    fields,
    rules,
    publish,
  ];

  /// The engine's frame phases, in order.
  static const List<LoopPhase> framePhases = <LoopPhase>[
    animate,
    audio,
    camera,
    render,
    ui,
  ];

  /// The names the engine's phases had before, to the names they have now.
  ///
  /// **A phase's name is written in files** — a data plugin's systems and
  /// phases name the phase they go in, and a constraint names the one it
  /// goes after — so a rename keeps the old word reading until the next
  /// major. The engine's loop looks a name up here before it looks for the
  /// phase ([current]).
  static const Map<String, String> formerNames = <String, String>{
    'elements': 'fields',
  };

  /// The name [name] has now: itself, unless it is one of [formerNames].
  static String currentName(String name) => formerNames[name] ?? name;

  /// This phase under the name it has now: itself, unless it was made with
  /// one of [formerNames].
  LoopPhase get current => switch (formerNames[name]) {
    null => this,
    final now =>
      kind == PhaseKind.frame ? LoopPhase.frame(now) : LoopPhase.step(now),
  };

  final String name;
  final PhaseKind kind;

  @override
  bool operator ==(Object other) =>
      other is LoopPhase && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);

  @override
  String toString() => '${kind.name} phase $name';
}

/// What a system is told about the moment it runs in.
///
/// **One object rather than parameters, so it can grow**, as `StepContext`
/// grew: a new field here breaks nobody, a new parameter breaks every system.
/// Reused between calls by the engine; copy what you keep. Made by the
/// engine: `base`, so a member added later arrives with a default.
abstract base class LoopContext {
  const LoopContext();

  /// The step being run, counted from the start of the run — or, in a frame
  /// phase, how many steps have run.
  int get step;

  /// Seconds of simulated time: one fixed step in a step phase; in a frame
  /// phase the simulated time this frame accepted, which is nought while
  /// paused and scaled by the time scale.
  double get dt;

  /// The wall-clock seconds of this frame, clamped to the loop's longest
  /// frame. For what goes on while the game is paused — a photo camera, a
  /// menu's animation. Nought in a step phase, where a wall clock is
  /// exactly what may not be read.
  double get realDt;

  /// How far the frame sits between the last two steps, in `[0, 1)`. Nought
  /// in a step phase.
  double get alpha;

  /// The phase running now.
  LoopPhase get phase;

  /// Whether this step is being run again — a rollback re-stepping after a
  /// correction, a scrub replaying to a point. Simulation systems run as
  /// usual; anything with an effect outside the world (a sound, a vibration)
  /// should not repeat itself. False in a frame phase.
  bool get isResimulated;

  /// Publishes [event]: onto the step channel from a step phase, onto the
  /// frame channel from a frame phase.
  void publish(BusEvent event);

  /// The simulation's world: entities, components, resources and the
  /// commands deferred to the end of the phase (item 27).
  ///
  /// **Only in a step phase**, where it is the whole of what a system may
  /// change. A frame phase is the view's, and the view reads [published]:
  /// the engine's loop throws a [StateError] for this in a frame phase,
  /// because a frame system that reads the world directly is one that stops
  /// working the day the simulation runs in another isolate.
  ///
  /// A context made by something other than the engine's loop — a test's —
  /// may have no world; the default says so with a [StateError].
  SimWorld get world =>
      throw StateError('this $runtimeType was made without a world');

  /// What the last step published for the view: the published components,
  /// the positions in double precision and the steps' events, encoded
  /// (item 19).
  ///
  /// **What a frame phase reads of the simulation.** The engine's loop builds
  /// it after every step once anything has asked — a frame system reading
  /// this, or a `SimulationHandle` listening — and [PublishedState.empty]
  /// before the first step. A context made by something other than the
  /// engine's loop may have none; the default says so with a [StateError].
  PublishedState get published =>
      throw StateError('this $runtimeType was made without published state');
}

/// Work added to a phase.
typedef LoopSystem = void Function(LoopContext context);

/// The loop's phases and the systems in them.
///
/// ## Order
///
/// Phases and systems are ordered by named `after` and `before` constraints,
/// sorted when the loop next reaches a step boundary. A cycle is an error
/// naming every member of it. Where constraints leave a choice, registration
/// order decides — the application's own registrations first, then each
/// plugin's in install order — and never a hash map.
///
/// A sort takes the earliest place the constraints allow for whatever was
/// registered first, so a phase given only `after: ['physics']` lands after
/// every engine phase that follows physics too: the engine's chain was
/// registered before it. To put a phase between two, name both.
///
/// A constraint naming a system that is not registered is ignored: "before
/// fire" from a plugin that works with or without the fire plugin.
abstract base class LoopRegistry extends PluginRegistry {
  const LoopRegistry();

  /// Adds a phase of its own kind, ordered against the others by
  /// [after]/[before], which name phases of the same kind.
  ///
  /// Throws an [ArgumentError] for a name already used, or a constraint
  /// naming a phase that does not exist.
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  });

  /// Adds [system] to [phase] under [name], unique in the loop, ordered
  /// against the phase's other systems by [after]/[before].
  ///
  /// Throws an [ArgumentError] for a name already used or a phase that does
  /// not exist.
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  });

  @override
  LoopRegistry forPlugin(PluginScope scope);
}
