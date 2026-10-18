import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'ecs.dart';
import 'events.dart';
import 'readings.dart';
import 'registration.dart';
import 'simulation.dart';
import 'simulation_profile.dart';

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

  /// The kind's name, `step` or `frame`, as a manifest and a tool list write
  /// it.
  final String name;

  @override
  String toString() => name;
}

/// A named stretch of the loop that systems are added to.
///
/// **A name rather than an enum**, for the reason `GameAction` is a name: a
/// genre has moments the engine cannot list, and
/// a plugin adds them with `LoopRegistry.addPhase` between the engine's.
/// A name is unique across both kinds — a step phase and a frame phase may
/// not share one, since a constraint names a phase without its kind.
final class LoopPhase {
  /// A phase named [name] that runs inside every fixed step.
  const LoopPhase.step(this.name) : kind = PhaseKind.step;

  /// A phase named [name] that runs once a displayed frame.
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

  /// The phase's name, unique across both kinds: what a system, a constraint
  /// and a data plugin name it by.
  final String name;

  /// Whether the phase runs inside the fixed step or once a frame.
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
/// **One object rather than parameters, so it can grow**: a new field here
/// breaks nobody, a new parameter breaks every system. Reused between calls
/// by the engine; copy what you keep. Made by the engine: `base`, so a member
/// added later arrives with a default.
///
/// **The one context every system is handed**, the engine's, a plugin's and
/// a genre's alike: a rule a game adds to a genre's step is a system in the
/// genre's phase, ordered against `<genre>.step` by name
/// (`LoopRegistry.addSystem`), and reads this.
abstract base class LoopContext {
  /// For the engine's loop, which extends this; a system is handed one, and
  /// never makes its own.
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
  /// For the engine's loop, which extends this; a plugin is handed one
  /// through its host.
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
  /// [reads] and [writes] name the state the system touches: a component's
  /// or a resource's registered name, a field's id (`f3d.heat`), a genre's
  /// simulation (`shooter.simulation`), any name the systems that share the
  /// state agree on, namespaced like every other name a plugin brings. Both
  /// default to empty, which declares nothing and is never checked.
  ///
  /// **Declared so an unordered pair can be named.** A replay is bit for bit
  /// only while two systems that touch one state run in one order on every
  /// machine; where the constraints leave a choice, registration order
  /// decides, and an install order that differs between the run and its
  /// replay is a different picture. The engine's loop names every pair of
  /// systems in one step phase where one writes what the other reads or
  /// writes and neither is ordered against the other, through
  /// [after]/[before] or a chain of them.
  ///
  /// Throws an [ArgumentError] for a name already used or a phase that does
  /// not exist.
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
    List<String> reads = const <String>[],
    List<String> writes = const <String>[],
  });

  /// Adds [assimilation] to the step under [name], unique in the loop: it
  /// runs in the [LoopPhase.input] phase of every step, after the step's
  /// input is in place, and is handed the [ExternalStateInput]s fed in for
  /// that step. Ordered against the phase's systems by [after]/[before].
  ///
  /// The engine's loop takes it; a registry that has no external input says
  /// so with an [UnsupportedError], the default.
  Registration addAssimilation(
    String name,
    Assimilation assimilation, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => throw UnsupportedError(
    '$runtimeType takes no assimilation: "$name" has no external input to '
    'read here',
  );

  @override
  LoopRegistry forPlugin(PluginScope scope);
}

/// What an [Assimilation] is told about the step it runs in.
///
/// **One object rather than parameters, so it can grow**, as [LoopContext]
/// does. Made by the engine: `base`, so a member added later arrives with
/// a default.
abstract base class AssimilationContext {
  /// For the engine's loop, which extends this.
  const AssimilationContext();

  /// The step being run, counted from the start of the run.
  int get step;

  /// One fixed step of simulated time, in seconds.
  double get dt;

  /// What arrived from outside for this step, in the order it was fed: on
  /// the tape with the step, so a replay hands the same.
  List<ExternalStateInput> get inputs;

  /// The ones of [inputs] from [source], in order.
  Iterable<ExternalStateInput> from(String source) =>
      inputs.where((input) => input.source == source);

  /// The simulation's world, where the assimilation writes what it decides.
  SimWorld get world;

  /// What the simulation promises about its numbers: an assimilation that
  /// blends in double precision asks [SimulationProfile.usesDoublePrecision]
  /// rather than which profile it is.
  SimulationProfile get profile => SimulationProfile.deterministic;

  /// Whether the step is being run again after a rollback: [inputs] are the
  /// ones the step was first fed.
  bool get isResimulated;

  /// Publishes [event] on the step channel.
  void publish(BusEvent event);
}

/// The place inside the step where outside state meets the model: a
/// twin's Kalman filter, a valve set to what the plant reports, a headset's
/// pose put on the camera rig.
///
/// **The hook a twin writes.** Telemetry enters as input
/// ([ExternalStateInput], on the tape with its step) and the simulation's
/// boundary does not change: an assimilation reads the step's inputs and
/// writes the world, so a run fed by a plant replays as one fed by a
/// keyboard. Registered with [LoopRegistry.addAssimilation].
///
/// `base`, so a member added later arrives with a default; [assimilate]
/// takes one growing context, never a list of parameters.
abstract base class Assimilation {
  /// For an assimilation class, which supplies [assimilate].
  const Assimilation();

  /// An assimilation that calls [assimilate].
  const factory Assimilation.of(
    void Function(AssimilationContext context) assimilate,
  ) = _FunctionAssimilation;

  /// Decides between what arrived and what the model says, for one step.
  void assimilate(AssimilationContext context);
}

final class _FunctionAssimilation extends Assimilation {
  const _FunctionAssimilation(this._assimilate);

  final void Function(AssimilationContext context) _assimilate;

  @override
  void assimilate(AssimilationContext context) => _assimilate(context);
}
