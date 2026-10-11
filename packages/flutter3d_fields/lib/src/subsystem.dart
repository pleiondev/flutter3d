/// A solver as a subsystem of the simulation: what it reads and writes,
/// where in the step it runs, and which simulation it belongs to.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'field.dart';
import 'host_field.dart';

/// What a solver says about itself before it runs: its id and version,
/// the quantities and fields it reads and writes, and its place in the
/// step.
///
/// **Declarations first, so a checker can come later.** Nothing here is a
/// promise the engine cannot hold: the fields a subsystem names are held
/// to it now (it is handed only those, read-only where it only reads), and
/// a later simulation-graph checker reads the same declarations instead of
/// asking for new ones.
///
/// **Switched on by a profile.** A solver a minor adds is declared with
/// [switchedOnBy] naming the profiles it runs under. Under any other, the
/// default `SimulationProfile.deterministic` among them, it is registered
/// and does not run, and the simulation's version does not name it, so the
/// default simulation, its tapes and its matches are as they were. Under one
/// of its profiles it runs, and `SimulationVersion.subsystems` names it at
/// [version].
final class SubsystemDeclaration {
  const SubsystemDeclaration({
    required this.id,
    required this.version,
    this.phase = LoopPhase.fields,
    this.after = const <String>[],
    this.before = const <String>[],
    this.readsQuantities = const <String>[],
    this.writesQuantities = const <String>[],
    this.readsFields = const <String>[],
    this.writesFields = const <String>[],
    this.switchedOnBy,
  });

  /// `<namespace>.<name>`, a plugin's under its own id: the subsystem's
  /// system in the loop and its key in `SimulationVersion.subsystems`.
  final String id;

  /// Its own simulation number, by the promise `SimulationVersion` keeps:
  /// a patch never changes what it computes, a minor that does bumps this.
  /// From 1.
  final int version;

  /// The step phase it runs in: the world's fields, after the bodies have
  /// moved and before the rules read them, unless it says otherwise.
  final LoopPhase phase;

  /// The systems of [phase] it runs after, by name.
  final List<String> after;

  /// The systems of [phase] it runs before, by name.
  final List<String> before;

  /// The quantities it reads, by their namespaced ids (`f3d.temperature`).
  final List<String> readsQuantities;

  /// The quantities it writes.
  final List<String> writesQuantities;

  /// The fields it reads, by id: each a host field it is handed read-only.
  final List<String> readsFields;

  /// The fields it writes, by id: each a host field whose writer it is.
  final List<String> writesFields;

  /// The profiles it runs under, or null for every profile.
  ///
  /// A solver of the default simulation, or a plugin's that is always on
  /// while the plugin is, leaves it null. A solver added in a minor names
  /// the profile that switches it on, so the default profile's simulation
  /// stays the one its tapes were recorded on.
  final List<SimulationProfile>? switchedOnBy;

  /// Whether it runs under [profile].
  bool runsUnder(SimulationProfile profile) =>
      switchedOnBy?.contains(profile) ?? true;

  /// What is wrong with this declaration, or null when nothing is.
  String? get problem {
    if (!FieldDeclaration.namespacedId.hasMatch(id)) {
      return 'a subsystem\'s id is "<namespace>.<name>", as "f3d.heat" is, '
          'not "$id"';
    }
    if (version < 1) {
      return 'subsystem "$id" is at version $version; a subsystem\'s number '
          'starts at 1';
    }
    if (phase.kind != PhaseKind.step) {
      return 'subsystem "$id" runs in the ${phase.name} phase, which is a '
          'frame\'s; a subsystem is part of the fixed step';
    }
    for (final quantity in <String>[...readsQuantities, ...writesQuantities]) {
      if (!FieldDeclaration.namespacedId.hasMatch(quantity)) {
        return 'subsystem "$id" names the quantity "$quantity", which is not '
            '"<namespace>.<name>"';
      }
    }
    for (final field in readsFields) {
      if (writesFields.contains(field)) {
        return 'subsystem "$id" names field "$field" among what it reads and '
            'what it writes; a writer reads its own field as it writes it';
      }
    }
    return null;
  }

  /// Everything it declares, as a report or a checker reads it.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version,
    'phase': phase.name,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
    if (readsQuantities.isNotEmpty) 'readsQuantities': readsQuantities,
    if (writesQuantities.isNotEmpty) 'writesQuantities': writesQuantities,
    if (readsFields.isNotEmpty) 'readsFields': readsFields,
    if (writesFields.isNotEmpty) 'writesFields': writesFields,
    if (switchedOnBy case final profiles?)
      'switchedOnBy': <String>[for (final p in profiles) p.name],
  };

  @override
  String toString() => 'SubsystemDeclaration($id $version)';
}

/// What a [Subsystem] is told about the step it runs in, and its way to
/// the fields it declared.
///
/// **One object rather than parameters, so it can grow**, as `LoopContext`
/// does. Made by the engine: `base`, so a member added later arrives with a
/// default.
abstract base class SubsystemContext {
  const SubsystemContext();

  /// The subsystem's own declaration.
  SubsystemDeclaration get declaration;

  /// The step being run, counted from the start of the run.
  int get step;

  /// One fixed step of simulated time, in seconds.
  double get dt;

  /// Whether the step is being run again after a rollback or for a scrub:
  /// solve as usual, and repeat no effect outside the world.
  bool get isResimulated;

  /// What the simulation promises about its numbers: a solver that keeps
  /// double precision asks [SimulationProfile.usesDoublePrecision].
  SimulationProfile get profile => SimulationProfile.deterministic;

  /// The simulation's world.
  SimWorld get world;

  /// Publishes [event] on the step channel.
  void publish(BusEvent event);

  /// The host field called [id]: writable when the subsystem declared it
  /// among what it writes, a read-only view when among what it reads.
  /// Throws a [StateError] for a field it declared neither way, which is a
  /// read or a write a checker would never see.
  HostField field(String id);
}

/// A solver of the simulation, registered with what it reads and writes.
///
/// **Implementable outside this package, and stays so through 1.x**: one
/// method taking one context, and a member added later arrives with a
/// default body.
abstract base class Subsystem {
  const Subsystem();

  /// A subsystem declared by [declaration] that runs [step].
  const factory Subsystem.of(
    SubsystemDeclaration declaration,
    void Function(SubsystemContext context) step,
  ) = _FunctionSubsystem;

  /// What it reads and writes, and where it runs.
  SubsystemDeclaration get declaration;

  /// Solves one fixed step.
  void step(SubsystemContext context);
}

final class _FunctionSubsystem extends Subsystem {
  const _FunctionSubsystem(this.declaration, this._step);

  @override
  final SubsystemDeclaration declaration;

  final void Function(SubsystemContext context) _step;

  @override
  void step(SubsystemContext context) => _step(context);
}

/// The subsystems of one engine: `host.registry<SubsystemRegistry>()`.
///
/// **Registered, then run where the profile says.** [register] checks a
/// subsystem's declaration against the fields declared so far (each field
/// it writes names it as the writer, each it reads is held in host memory)
/// and, when it [SubsystemDeclaration.runsUnder] the loop's profile, adds
/// its step to its phase under its id. One that does not run under it is
/// kept in [declared] and nowhere else.
///
/// **The simulation's version is composed from [versions]**: every running
/// subsystem by id at its number, as `SimulationVersion.subsystems`. A run
/// recorded with a subsystem on is refused where it is off, and the other
/// way round, as a run with a simulation plugin is.
///
/// **Extended by the engine, called by plugins.** A plugin's subsystems are
/// under its own id and taken back when it is switched off.
abstract base class SubsystemRegistry extends PluginRegistry {
  const SubsystemRegistry();

  /// Registers [subsystem]. Throws an [ArgumentError] for a declaration
  /// with a [SubsystemDeclaration.problem], an id already registered, or a
  /// field it names that nobody declared, that is not held in host memory,
  /// or whose writer is another; a [PluginException] for a plugin's id
  /// outside its namespace (`PluginManifest.nameProblem`).
  Registration register(Subsystem subsystem);

  /// Every subsystem registered, running or not, in the order it was.
  List<SubsystemDeclaration> get declared;

  /// The ones that run under the loop's profile, in registration order.
  List<SubsystemDeclaration> get running;

  /// [running] by id at its version: `SimulationVersion.subsystems`.
  Map<String, int> get versions => <String, int>{
    for (final declaration in running) declaration.id: declaration.version,
  };

  @override
  SubsystemRegistry forPlugin(PluginScope scope);
}
