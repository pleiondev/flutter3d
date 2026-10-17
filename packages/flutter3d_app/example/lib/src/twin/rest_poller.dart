/// A REST endpoint asked at a fixed interval, its answers queued as
/// readings for the loop to take at the start of a step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ExternalStateInput;
import 'package:http/http.dart' as http;

/// What a source's answer says, as a reading, or null when it says none.
typedef ReadAnswer =
    ExternalStateInput? Function(Object? json, {required double receivedTime});

/// Asks [uri] every [every], reads the answer with [read], and queues the
/// reading until the loop [take]s it.
///
/// **The network is not the simulation's.** A poll finishes whenever the
/// server answers, which is between steps and at no step in particular, so
/// nothing here touches the loop: a reading waits in the queue, and the
/// twin feeds the whole queue into the input of the next step it runs
/// (`EngineLoop.onStepInput`). That puts it on the tape with that step, and
/// a replay or a scrub hands it back at the same step without asking the
/// network again.
///
/// **A reading the source took once is fed once.** A service that updates
/// every fifteen minutes answers the same reading to every poll between,
/// and the twin should not hear it as news; a reading whose source time is
/// the last one's is dropped.
final class RestPoller {
  RestPoller({
    required this.uri,
    required this.read,
    this.every = const Duration(minutes: 1),
    http.Client? client,
    double Function()? clock,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? _wallClock;

  /// The endpoint.
  final Uri uri;

  /// How its answer becomes a reading.
  final ReadAnswer read;

  /// How long between two polls.
  final Duration every;

  final http.Client _client;
  final bool _ownsClient;
  final double Function() _clock;
  final List<ExternalStateInput> _queue = <ExternalStateInput>[];
  Timer? _timer;
  double? _lastTaken;

  /// Why the last poll read nothing, or null when it read an answer.
  String? get lastError => _lastError;
  String? _lastError;

  /// The last reading a poll queued, or null before the first.
  ExternalStateInput? get latest => _latest;
  ExternalStateInput? _latest;

  static double _wallClock() => DateTime.now().millisecondsSinceEpoch / 1000;

  /// Polls now and every [every] from now on, until [stop].
  void start() {
    _timer ??= Timer.periodic(every, (_) => unawaited(pollOnce()));
    unawaited(pollOnce());
  }

  /// Stops polling; what is queued stays queued.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Asks the endpoint once and queues what it answered.
  Future<void> pollOnce() async {
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        _lastError = 'the source answered ${response.statusCode}';
        return;
      }
      final reading = read(
        jsonDecode(utf8.decode(response.bodyBytes)),
        receivedTime: _clock(),
      );
      if (reading == null) {
        _lastError = 'the answer held no reading';
        return;
      }
      _lastError = null;
      final taken = reading.sourceTime;
      if (taken != null && taken == _lastTaken) return;
      _lastTaken = taken;
      _latest = reading;
      _queue.add(reading);
    } on Object catch (error) {
      _lastError = '$error';
    }
  }

  /// Everything queued since the last call, oldest first; the queue is
  /// empty afterwards.
  List<ExternalStateInput> take() {
    final taken = List<ExternalStateInput>.of(_queue);
    _queue.clear();
    return taken;
  }

  /// Stops polling and closes the client when it was this poller's own.
  void dispose() {
    stop();
    if (_ownsClient) _client.close();
  }
}
