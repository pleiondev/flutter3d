import 'dart:async';
import 'dart:isolate';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'isolate_link.dart';
import 'isolate_simulation.dart';
import 'simulation_handle.dart';

/// Where there are isolates: everywhere but a browser.
const bool isolatesRun = true;

/// Spawns the isolate, builds the simulation there with [factory] and
/// answers the view's end once it has said it is ready.
///
/// Completes with a [StateError] naming what [factory] threw, or that the
/// isolate ended before it was ready.
Future<IsolateLink> openIsolateLink(
  SimulationFactory factory,
  Object? arguments, {
  required bool ownsClock,
  String? debugName,
}) async {
  final inbox = ReceivePort();
  final errors = ReceivePort();
  final exits = ReceivePort();
  final ready = Completer<(SendPort, SimulationVersion, PublishedState)>();
  final link = _NativeLink(<ReceivePort>[inbox, errors, exits]);

  inbox.listen((Object? message) {
    if (message is! List<Object?>) return;
    if (!ready.isCompleted) {
      switch (message) {
        case [
          LinkWords.ready,
          final SendPort port,
          final Map<Object?, Object?> version,
          final Object? state,
        ]:
          try {
            ready.complete((
              port,
              SimulationVersion.fromJson(version.cast<String, Object?>()),
              PublishedState.fromWire(state),
            ));
          } on Object catch (error, stack) {
            ready.completeError(error, stack);
          }
      }
      return;
    }
    link._hear(message);
  });
  errors.listen((Object? error) {
    final why = switch (error) {
      [final Object? message, ...] => '$message',
      _ => '$error',
    };
    if (!ready.isCompleted) {
      ready.completeError(StateError('the simulation was not built: $why'));
    } else {
      link._hear(<Object?>[LinkWords.exited, why]);
    }
  });
  exits.listen((_) {
    if (!ready.isCompleted) {
      ready.completeError(
        StateError('the simulation\'s isolate ended before it was ready'),
      );
    } else {
      link._hear(<Object?>[LinkWords.exited, 'its isolate ended']);
    }
    link._ended();
  });

  final Isolate isolate;
  try {
    isolate = await Isolate.spawn<_Start>(
      _work,
      (inbox.sendPort, factory, arguments, ownsClock),
      debugName: debugName,
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
  } on Object {
    link._closePorts();
    rethrow;
  }
  try {
    final (port, version, state) = await ready.future;
    return link
      .._isolate = isolate
      .._port = port
      ..first = (version, state);
  } on Object {
    isolate.kill(priority: Isolate.immediate);
    link._closePorts();
    rethrow;
  }
}

final class _NativeLink extends IsolateLink {
  _NativeLink(this._ports);

  final List<ReceivePort> _ports;
  late final Isolate _isolate;
  late final SendPort _port;
  final Completer<void> _exited = Completer<void>();
  final List<List<Object?>> _early = <List<Object?>>[];
  void Function(List<Object?> message)? _onMessage;

  @override
  late final (SimulationVersion, PublishedState) first;

  @override
  void listen(void Function(List<Object?> message) onMessage) {
    _onMessage = onMessage;
    final early = List<List<Object?>>.of(_early);
    _early.clear();
    early.forEach(onMessage);
  }

  void _hear(List<Object?> message) {
    final onMessage = _onMessage;
    if (onMessage == null) {
      _early.add(message);
    } else {
      onMessage(message);
    }
  }

  @override
  void send(List<Object?> message) {
    if (_exited.isCompleted) return;
    _port.send(message);
  }

  @override
  Future<void> close() async {
    if (!_exited.isCompleted) {
      _port.send(const <Object?>[LinkWords.close]);
      // A loop stuck in a long step is not waited on for ever: the isolate
      // is killed when it has not ended within the wait.
      await _exited.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _isolate.kill(priority: Isolate.immediate),
      );
    }
    _closePorts();
  }

  void _ended() {
    if (!_exited.isCompleted) _exited.complete();
    _closePorts();
  }

  void _closePorts() {
    for (final port in _ports) {
      port.close();
    }
  }
}

/// What the spawned isolate is handed: where to answer, how to build the
/// simulation and from what, and whether it keeps its own clock.
typedef _Start = (SendPort, SimulationFactory, Object?, bool);

/// The simulation's side: builds it, then answers the view's messages until
/// it is told to close.
void _work(_Start start) {
  final (reply, factory, arguments, ownsClock) = start;
  final setup = factory(arguments);
  final loop = setup.loop;
  final handle = setup.local();
  final inbox = ReceivePort();

  final publishing = handle.onPublished(
    (PublishedState state) =>
        reply.send(<Object?>[LinkWords.published, state.toWire()]),
  );

  // The step rate's own period, measured against a stopwatch rather than
  // trusted: a timer that fires late hands the loop the time it really took,
  // and the loop runs as many steps as that owes.
  final Timer? clock;
  if (ownsClock) {
    final watch = Stopwatch()..start();
    var last = 0;
    clock = Timer.periodic(
      Duration(microseconds: (loop.stepSeconds * 1e6).round()),
      (_) {
        final now = watch.elapsedMicroseconds;
        loop.frame((now - last) / 1e6);
        last = now;
      },
    );
  } else {
    clock = null;
  }

  void answer(int id, Future<Object?> asked) {
    asked.then(
      (Object? value) {
        try {
          reply.send(<Object?>[LinkWords.answer, id, value]);
        } on Object catch (error) {
          final why =
              'its answer does not cross an isolate ($error); answer plain '
              'values';
          reply.send(<Object?>[LinkWords.failed, id, why]);
        }
      },
      onError: (Object error) => reply.send(switch (error) {
        SimulationCapabilityException(:final message) => <Object?>[
          LinkWords.refused,
          id,
          message,
        ],
        _ => <Object?>[LinkWords.failed, id, '$error'],
      }),
    );
  }

  inbox.listen((Object? message) {
    switch (message) {
      case [LinkWords.submit, final int seat, final Object? input]:
        handle.submit(input, seat: seat);
      case [LinkWords.advance, final num seconds]:
        loop.frame(seconds.toDouble());
      case [
        LinkWords.ask,
        final int id,
        final String name,
        final Object? arguments,
      ]:
        answer(id, handle.ask(name, arguments: arguments));
      case [LinkWords.rewind, final int id, final int step]:
        answer(id, handle.rewindTo(step).then((_) => null));
      case [LinkWords.close]:
        clock?.cancel();
        publishing.cancel();
        unawaited(handle.dispose());
        inbox.close();
        Isolate.exit();
    }
  });

  reply.send(<Object?>[
    LinkWords.ready,
    inbox.sendPort,
    loop.simulationVersion.toJson(),
    handle.published.toWire(),
  ]);
}
