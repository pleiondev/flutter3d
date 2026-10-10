/// The view's handle on a simulation that runs in an isolate of its own.
library;

import 'dart:async';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'engine_loop.dart';
import 'isolate_link.dart';
import 'isolate_link_native.dart'
    if (dart.library.js_interop) 'isolate_link_web.dart';
import 'local_simulation.dart';
import 'simulation_handle.dart';

/// What a [SimulationFactory] builds where the simulation runs: the loop,
/// how a submitted input reaches it, and how much history it keeps.
///
/// The same three things [LocalSimulation] takes, so one factory serves both:
/// [local] builds the handle in this isolate, which is what a game on the web
/// does with the factory it hands [IsolateSimulation.open] elsewhere.
final class SimulationSetup {
  SimulationSetup({
    required this.loop,
    required this.applyInput,
    this.history = 0,
  });

  /// The loop, with the game's plugins installed and its level loaded.
  final EngineLoop loop;

  /// Hands an input submitted for a seat to the game: what
  /// [LocalSimulation.applyInput] is.
  final void Function(int seat, Object? input) applyInput;

  /// How many steps of captures are kept for `rewindTo`; nought keeps none.
  final int history;

  /// A [LocalSimulation] over [loop], in this isolate.
  LocalSimulation local() =>
      LocalSimulation(loop, applyInput: applyInput, history: history);
}

/// Builds a simulation where it runs, from [arguments] — plain values the
/// caller of [IsolateSimulation.open] passed.
///
/// **A top-level function or a static method.** It is called in the spawned
/// isolate, which has none of the opener's objects: the loop, the world and
/// the plugins are made there, from the arguments, and only plain values and
/// published states cross back.
typedef SimulationFactory = SimulationSetup Function(Object? arguments);

/// [SimulationHandle] over an [EngineLoop] running in an isolate spawned for
/// it — the step off the thread that draws (item 19).
///
/// ## What crosses
///
/// * **[published]** arrives as [PublishedState.toWire] after every step and
///   is read back with [PublishedState.fromWire]: the components and the
///   events are already their codecs' output, so the view decodes exactly
///   what a [LocalSimulation]'s view decodes.
/// * **[submit]** sends the input and its seat. On the other side it is
///   queued for the next live step and handed to the setup's `applyInput`,
///   as [LocalSimulation.submit] does, so it is on the tape.
/// * **[ask]** sends a name and plain arguments; the answer is the one
///   registered in the loop's `queries`, run there between two steps.
/// * **[rewindTo]** puts the loop back to a step it kept a capture of.
///
/// **[query] is refused.** A closure runs only in an isolate that shares its
/// code, and a view written against this handle should keep working when the
/// simulation moves further still; it completes with a
/// [SimulationCapabilityException] that says to ask by name.
///
/// ## The clock
///
/// By default the isolate runs its own clock: a timer at the loop's step
/// rate, measured against a stopwatch, handed to `EngineLoop.frame`. With
/// `ownsClock: false` it steps only when told, by [advance] — what a test,
/// or a view that paces the simulation by its own frames, does.
///
/// ## Where it runs
///
/// Anywhere `dart:isolate` does. **On the web [open] refuses**, with a
/// [SimulationCapabilityException]: a package cannot spawn a worker there.
/// [isSupported] says which, and a game that runs in both places keeps one
/// factory and asks:
///
/// ```dart
/// final SimulationHandle handle = IsolateSimulation.isSupported
///     ? await IsolateSimulation.open(buildCrypt, arguments: level)
///     : buildCrypt(level).local();
/// ```
final class IsolateSimulation extends SimulationHandle {
  IsolateSimulation._(
    this._link,
    this._simulation,
    PublishedState first, {
    required this.ownsClock,
  }) : _published = first;

  /// Whether this platform can spawn the isolate [open] needs: false in a
  /// browser.
  static bool get isSupported => isolatesRun;

  /// Spawns an isolate, builds the simulation there with [factory] from
  /// [arguments], and answers once it has published its first state.
  ///
  /// [ownsClock] true (the default) steps the loop on a timer of its own;
  /// false steps it only through [advance]. [debugName] names the isolate
  /// in a debugger.
  ///
  /// Completes with a [SimulationCapabilityException] on a platform with no
  /// isolates ([isSupported]), and with the factory's error when it threw.
  static Future<IsolateSimulation> open(
    SimulationFactory factory, {
    Object? arguments,
    bool ownsClock = true,
    String? debugName,
  }) async {
    final link = await openIsolateLink(
      factory,
      arguments,
      ownsClock: ownsClock,
      debugName: debugName,
    );
    final (simulation, first) = link.first;
    final handle = IsolateSimulation._(
      link,
      simulation,
      first,
      ownsClock: ownsClock,
    );
    link.listen(handle._hear);
    return handle;
  }

  final IsolateLink _link;
  final SimulationVersion _simulation;
  PublishedState _published;

  /// Whether the isolate steps on its own timer, or only through [advance].
  final bool ownsClock;

  final List<void Function(PublishedState state)> _listeners =
      <void Function(PublishedState state)>[];
  final Map<int, (Completer<Object?>, String)> _waiting =
      <int, (Completer<Object?>, String)>{};
  int _asked = 0;
  bool _disposed = false;

  @override
  PublishedState get published => _published;

  @override
  SimulationVersion get simulation => _simulation;

  @override
  Registration onPublished(void Function(PublishedState state) listener) {
    _listeners.add(listener);
    return Registration(() => _listeners.remove(listener));
  }

  @override
  void submit(Object? input, {int seat = 0}) {
    if (_disposed) return;
    _link.send(<Object?>[LinkWords.submit, seat, input]);
  }

  /// Runs one frame of [seconds] real seconds in the isolate: what a view
  /// pacing a handle opened with `ownsClock: false` calls once a frame. The
  /// steps it runs publish as they do on the isolate's own clock.
  ///
  /// Throws a [StateError] on a handle whose isolate keeps its own clock:
  /// two clocks would step the world twice as fast.
  void advance(double seconds) {
    if (ownsClock) {
      throw StateError(
        'this simulation keeps its own clock; open it with ownsClock: false '
        'to step it by advance',
      );
    }
    if (_disposed) return;
    _link.send(<Object?>[LinkWords.advance, seconds]);
  }

  @override
  Future<Object?> ask(String name, {Object? arguments}) =>
      _call(LinkWords.ask, name, <Object?>[name, arguments]);

  @override
  Future<R> query<R>(R Function(SimWorld world) question) => Future<R>.error(
    const SimulationCapabilityException(
      'the world is in another isolate, and a closure does not cross to '
      'it; register the question in the loop\'s queries and ask it by name',
    ),
  );

  @override
  Future<void> rewindTo(int step) =>
      _call(LinkWords.rewind, 'a rewind to step $step', <Object?>[step]);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    for (final (waiting, what) in _waiting.values) {
      waiting.completeError(
        SimulationCapabilityException(
          'the simulation was disposed before it answered $what',
        ),
      );
    }
    _waiting.clear();
    await _link.close();
  }

  Future<Object?> _call(String verb, String what, List<Object?> body) {
    if (_disposed) {
      return Future<Object?>.error(
        const SimulationCapabilityException(
          'the simulation was disposed, so there is no world to ask',
        ),
      );
    }
    final id = _asked++;
    final waiting = Completer<Object?>();
    _waiting[id] = (waiting, what);
    _link.send(<Object?>[verb, id, ...body]);
    return waiting.future;
  }

  void _hear(List<Object?> message) {
    if (_disposed) return;
    switch (message) {
      case [LinkWords.published, final Object? wire]:
        final state = _published = PublishedState.fromWire(wire);
        for (final listener in List.of(_listeners)) {
          listener(state);
        }
      case [LinkWords.answer, final int id, final Object? answer]:
        _waiting.remove(id)?.$1.complete(answer);
      case [LinkWords.refused, final int id, final String why]:
        _waiting
            .remove(id)
            ?.$1
            .completeError(SimulationCapabilityException(why));
      case [LinkWords.failed, final int id, final String why]:
        if (_waiting.remove(id) case (final waiting, final what)) {
          waiting.completeError(
            StateError('the simulation failed answering $what: $why'),
          );
        }
      case [LinkWords.exited, final String why]:
        _disposed = true;
        for (final (waiting, what) in _waiting.values) {
          waiting.completeError(
            SimulationCapabilityException(
              'the simulation stopped before it answered $what: $why',
            ),
          );
        }
        _waiting.clear();
    }
  }
}
