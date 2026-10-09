/// What the view holds of a simulation, and the questions it may ask it by
/// name.
///
/// **The simulation host's side, not the plugin contract's.** The contract
/// (`flutter3d_plugin_api`) is what a step publishes: [PublishedState],
/// [PublishedEvent], [SimulationVersion]. The handle that hands it to a
/// view, and the registry a plugin answers named questions from, are the
/// engine's, beside the loop that implements them (`LocalSimulation`,
/// `IsolateSimulation`, `SimQueries`). They were in the plugin API until
/// 1.0.0-rc.1.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// A simulation that cannot do what was asked of it through its handle: a
/// rewind past what it keeps, a query on a handle already disposed.
final class SimulationCapabilityException extends CapabilityException {
  const SimulationCapabilityException(this.message);

  @override
  final String message;

  @override
  String toString() => 'SimulationCapabilityException: $message';
}

/// How the simulation answers one named question: [SimulationHandle.ask]
/// with [arguments], run against [world] where the world is, between two
/// steps. The answer is plain values only, which is what crosses an isolate.
typedef SimulationAnswer = Object? Function(SimWorld world, Object? arguments);

/// The questions a simulation answers by name, for a view that asks them
/// through [SimulationHandle.ask].
///
/// **A name, not a closure**, because a name crosses an isolate boundary and
/// a closure does not: the simulation's side registers what each name means,
/// next to the world it reads, and the view sends only the name and plain
/// arguments. Filled by `flutter3d_sim`'s `SimQueries`, which `EngineLoop`
/// owns and hands to plugins: `host.registry<SimulationQueryRegistry>()`.
abstract base class SimulationQueryRegistry extends PluginRegistry {
  const SimulationQueryRegistry();

  /// Says how the question [name] is answered. Throws an [ArgumentError]
  /// when [name] is taken; a plugin's names are prefixed with its id.
  Registration add(String name, SimulationAnswer answer);

  /// The answer registered under [name]; null when there is none (absent).
  SimulationAnswer? answerFor(String name);

  /// Every registered name, in registration order.
  List<String> get names;

  @override
  SimulationQueryRegistry forPlugin(PluginScope scope);
}

/// What the view holds of a simulation: its published state, a way to hand
/// it input, questions answered asynchronously, and rewinding.
///
/// **One shape for this isolate and another.** Everything that crosses is a
/// plain value or a [PublishedState]: input is a value the simulation's
/// input system reads ([submit]), a question is a name the simulation
/// answers where the world is ([ask]), and the answers are futures even when
/// the world is next door — so a view written against `LocalSimulation`
/// keeps working when the world moves into an isolate. [query], which takes
/// a closure, is the same isolate group's shortcut and does not cross.
///
/// `base`, so a member added later arrives with a default. Made by the
/// engine (`LocalSimulation` and `IsolateSimulation` in `flutter3d_sim`) or
/// by a plugin that runs a simulation elsewhere; a handle across a boundary
/// sends [PublishedState.toWire] and reads it back with
/// [PublishedState.fromWire].
abstract base class SimulationHandle {
  const SimulationHandle();

  /// The latest state the simulation published; [PublishedState.empty]
  /// before the first step.
  PublishedState get published;

  /// The simulation this handle runs.
  SimulationVersion get simulation;

  /// Calls [listener] with every state published from now on.
  Registration onPublished(void Function(PublishedState state) listener);

  /// Hands [input] to the player in [seat] for the next step. Plain values
  /// only: what an isolate message carries.
  void submit(Object? input, {int seat = 0});

  /// Runs [question] against the world where it is, between two steps, and
  /// answers with its result. The function must not keep the world, and its
  /// answer must be a plain value or immutable.
  ///
  /// **Same isolate group only.** A closure can be sent to an isolate that
  /// shares this one's code and to nothing further — a worker on the web, a
  /// simulation on a server. A view meant to keep working wherever the
  /// simulation runs asks by name instead ([ask]).
  Future<R> query<R>(R Function(SimWorld world) question);

  /// Asks the simulation the question registered as [name]
  /// ([SimulationQueryRegistry]), with [arguments], and answers with what it
  /// returned: plain values, wherever the world is.
  ///
  /// Completes with a [SimulationCapabilityException] when no question of
  /// that name is registered. The default refuses every name: a handle whose
  /// simulation answers none says so.
  Future<Object?> ask(
    String name, {
    Object? arguments,
  }) => Future<Object?>.error(
    SimulationCapabilityException(
      '$runtimeType answers no named questions, so it cannot answer "$name"',
    ),
  );

  /// Puts the simulation back to how it was after [step] steps, through its
  /// snapshots. The default refuses: a handle that keeps no history says so.
  Future<void> rewindTo(int step) => Future<void>.error(
    SimulationCapabilityException(
      '$runtimeType keeps no history, so it cannot rewind to step $step',
    ),
  );

  /// Lets the simulation go. Nothing published after this is delivered.
  Future<void> dispose() async {}
}
