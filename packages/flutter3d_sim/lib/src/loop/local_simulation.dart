/// The view's handle on a simulation that runs in this isolate.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'engine_loop.dart';
import 'simulation_handle.dart';

/// [SimulationHandle] over an [EngineLoop] in this isolate.
///
/// **The shape an isolate's handle has too** (item 19): the view reads
/// [published], hands input to [submit], asks [query] and waits for the
/// answer, and nothing it holds is the world itself. [IsolateSimulation],
/// the handle for a world in another isolate, carries the same calls as
/// messages; a view written against this one does not change, as long as it
/// asks by name ([ask]) rather than with a closure ([query]).
///
/// ## Input
///
/// What [submit] is handed is queued for the next live step: at its start,
/// before the loop's recorders write the step's input
/// (`EngineLoop.onStepInput`), each submission is handed to [applyInput] in
/// the order it was submitted — the game's own reading of it into the loop's
/// `InputState`. So a submitted press is on the tape like a key press, a
/// replay of the tape repeats it, and a press and a release submitted
/// between two steps are both seen, in that order, rather than the release
/// alone.
///
/// ## Questions
///
/// [ask] answers the questions registered by name in the loop's
/// [EngineLoop.queries]; [query] runs a closure, which only this isolate
/// group can.
///
/// ## Rewinding
///
/// [rewindTo] goes through the loop's snapshots: the loop keeps a capture of
/// the last [history] steps (`EngineLoop.keep`), and a rewind restores the
/// one at the step asked for.
final class LocalSimulation extends SimulationHandle {
  /// A handle on [loop]. [history] steps of captures are kept for
  /// [rewindTo]; nought keeps none.
  LocalSimulation(this.loop, {required this.applyInput, int history = 0}) {
    if (history > 0) loop.keep(window: history);
    _publishing = loop.onPublished(_published);
    _input = loop.onStepInput((_) => _applyPending());
  }

  /// The loop this handle drives.
  final EngineLoop loop;

  /// Hands [input], submitted for [seat], to the game, to be put into the
  /// loop's `InputState`: called at the start of the next live step for
  /// every submission since the last, in the order they were made.
  final void Function(int seat, Object? input) applyInput;

  late final Registration _publishing;
  late final Registration _input;
  final List<(int, Object?)> _pending = <(int, Object?)>[];
  final List<void Function(PublishedState state)> _listeners =
      <void Function(PublishedState state)>[];
  bool _disposed = false;

  @override
  PublishedState get published => loop.published;

  @override
  SimulationVersion get simulation => loop.simulationVersion;

  @override
  Registration onPublished(void Function(PublishedState state) listener) {
    _listeners.add(listener);
    return Registration(() => _listeners.remove(listener));
  }

  @override
  void submit(Object? input, {int seat = 0}) {
    if (_disposed) return;
    _pending.add((seat, input));
  }

  @override
  Future<Object?> ask(String name, {Object? arguments}) {
    if (_disposed) {
      return Future<Object?>.error(
        const SimulationCapabilityException(
          'the simulation was disposed, so there is no world to ask',
        ),
      );
    }
    final answer = loop.queries.answerFor(name);
    if (answer == null) {
      final known = loop.queries.names;
      return Future<Object?>.error(
        SimulationCapabilityException(
          'no question named "$name" is answered here '
          '(${known.isEmpty ? 'none are' : 'these are: ${known.join(', ')}'})',
        ),
      );
    }
    return Future<Object?>.sync(() => answer(loop.world, arguments));
  }

  @override
  Future<R> query<R>(R Function(SimWorld world) question) {
    if (_disposed) {
      return Future<R>.error(
        const SimulationCapabilityException(
          'the simulation was disposed, so there is no world to ask',
        ),
      );
    }
    // Answered now, between two steps, but as a future: the world in another
    // isolate answers later, and a caller written against this one waits.
    return Future<R>.sync(() => question(loop.world));
  }

  @override
  Future<void> rewindTo(int step) {
    final kept = loop.keptSteps;
    if (!kept.contains(step)) {
      return Future<void>.error(
        SimulationCapabilityException(
          'no capture of step $step is kept '
          '(${kept.isEmpty ? 'none are' : 'kept: ${kept.join(', ')}'}); '
          'make the handle with a longer history',
        ),
      );
    }
    loop.rewindTo(step);
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _publishing.cancel();
    _input.cancel();
    _listeners.clear();
    _pending.clear();
  }

  void _applyPending() {
    if (_pending.isEmpty) return;
    final submitted = List<(int, Object?)>.of(_pending);
    _pending.clear();
    for (final (seat, input) in submitted) {
      applyInput(seat, input);
    }
  }

  void _published(PublishedState state) {
    for (final listener in List.of(_listeners)) {
      listener(state);
    }
  }
}
