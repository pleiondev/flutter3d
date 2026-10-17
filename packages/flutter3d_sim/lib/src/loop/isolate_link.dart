/// The port between an `IsolateSimulation` and the isolate its loop runs in:
/// the words both ends speak, and the end the view holds.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'simulation_handle.dart';

/// The words of the link: every message is a list whose first entry is one
/// of these, and whose rest is plain values. Not exported.
abstract final class LinkWords {
  /// The simulation's first words: `[ready, port, version, state]`.
  static const String ready = 'ready';

  /// To the simulation: `[submit, seat, input]`.
  static const String submit = 'submit';

  /// To the simulation: `[advance, seconds]`, one frame of its loop.
  static const String advance = 'advance';

  /// To the simulation: `[ask, id, name, arguments]`.
  static const String ask = 'ask';

  /// To the simulation: `[rewind, id, step]`.
  static const String rewind = 'rewind';

  /// To the simulation: `[close]`; it lets everything go and exits.
  static const String close = 'close';

  /// From the simulation: `[published, PublishedState.toWire()]`.
  static const String published = 'published';

  /// From the simulation: `[answer, id, value]`.
  static const String answer = 'answer';

  /// From the simulation: `[refused, id, sentence]`, a
  /// [SimulationCapabilityException] there.
  static const String refused = 'refused';

  /// From the simulation: `[failed, id, sentence]`, any other error there.
  static const String failed = 'failed';

  /// From the link itself: `[exited, sentence]`, the isolate is gone.
  static const String exited = 'exited';
}

/// The view's end of the link to a simulation's isolate. Not exported: made
/// by `openIsolateLink`, held by `IsolateSimulation`.
abstract base class IsolateLink {
  IsolateLink();

  /// The simulation's version and the state it published first, as its
  /// [LinkWords.ready] message said.
  (SimulationVersion, PublishedState) get first;

  /// Starts handing every message after [LinkWords.ready] to [onMessage],
  /// those that arrived before this first.
  void listen(void Function(List<Object?> message) onMessage);

  /// Sends [message] to the simulation.
  void send(List<Object?> message);

  /// Tells the simulation to let go and waits for its isolate to end.
  Future<void> close();
}
