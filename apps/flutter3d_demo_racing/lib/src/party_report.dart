import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One machine's line of a party's rollback report: what its
/// [RollbackSession] counted, the round trip it measured to the others, and
/// the digests of the steps it settled, in the shape
/// `packages/flutter3d_net/tool/rollback_report.dart` reads.
///
/// **The round trip is measured, not assumed.** Once every [pingEvery]
/// steps the machine sends a ping of its own over the party's wire, beside
/// the rollback's frames; every other machine answers it at once, and the
/// time from the ping to each answer is one sample. A ping not answered in
/// [forgetAfter] is let go, so a lost one costs nothing.
///
/// **The digests are of settled steps.** A step is digested once every
/// machine's frame for it has come or its guess was settled on, which is
/// the state every machine of the party has to agree on; one every
/// [digestEvery] steps, the report comparing them at the last step all of
/// the machines reached.
final class PartyRunReport {
  /// The report of the machine in [slot] of a party of [players].
  ///
  /// [clock] reads microseconds; a stopwatch started now by default.
  PartyRunReport({
    required this.slot,
    required this.players,
    this.digestEvery = 100,
    this.pingEvery = 60,
    this.forgetAfter = const Duration(seconds: 5),
    int Function()? clock,
  }) : _clock = clock ?? _stopwatch(),
       _trace = DigestTrace(every: digestEvery);

  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  /// What a ping and its answer carry under [PeerWire.engineKey], so the
  /// rollback hands them on rather than reading them as frames.
  static const String pingKind = 'race.ping';
  static const String pongKind = 'race.pong';

  /// The car this machine drives.
  final int slot;

  /// How many machines the party has.
  final int players;

  /// Steps between two digests.
  final int digestEvery;

  /// Steps between two pings.
  final int pingEvery;

  /// How long a ping waits for its answers before it is let go.
  final Duration forgetAfter;

  final int Function() _clock;
  final DigestTrace _trace;
  final List<double> _rttMs = <double>[];
  final Map<int, int> _sentAt = <int, int>{};
  int _pings = 0;

  /// The round trips measured so far, in milliseconds, in the order they
  /// came.
  List<double> get roundTrips => List<double>.unmodifiable(_rttMs);

  /// Digests the state a settled step ended in.
  void settled(SettledStep<Snapshot> step) =>
      _trace.observe(step.step + 1, step.after.toJson());

  /// Sends a ping on [wire] when [step] is one to send it on.
  void pingIfDue(PeerWire wire, int step) {
    if (step % pingEvery != 0) return;
    final now = _clock();
    _sentAt.removeWhere((_, sent) => now - sent > forgetAfter.inMicroseconds);
    final id = _pings++;
    _sentAt[id] = now;
    wire.send(
      PeerSend(
        message: <String, Object?>{PeerWire.engineKey: pingKind, 'id': id},
        reliable: false,
      ),
    );
  }

  /// Answers a ping from another machine, or takes the round trip of an
  /// answer to one of this machine's. Says whether [message] was either.
  bool hear(PeerWire wire, PeerMessage message) {
    final body = message.message;
    switch (body[PeerWire.engineKey]) {
      case pingKind:
        wire.send(
          PeerSend(
            message: <String, Object?>{
              PeerWire.engineKey: pongKind,
              'id': body['id'],
              'to': message.from,
            },
            reliable: false,
          ),
        );
        return true;
      case pongKind:
        if (body['id'] case final int id when body['to'] == slot) {
          if (_sentAt[id] case final int sent) {
            _rttMs.add((_clock() - sent) / 1000.0);
          }
        }
        return true;
    }
    return false;
  }

  /// The line of the report for [session], ended by [endedBy]: `time` for
  /// a session that ran its length, anything else for one that did not.
  ///
  /// [lastStep] is the last step every machine is held to; the digests
  /// after it are left out, as the report compares at the last step all of
  /// them reached.
  Map<String, Object?> toJson({
    required RollbackSession<Snapshot> session,
    required String machine,
    required String device,
    String endedBy = 'time',
  }) {
    final steps = _trace.steps;
    final hex = _trace.hexDigests;
    return <String, Object?>{
      'kind': 'rollback-run',
      'version': 1,
      'machine': machine,
      'device': device,
      'slot': slot,
      'players': players,
      'stepHz': 60,
      'inputDelay': session.inputDelay,
      'maxRollbackFrames': session.maxRollbackFrames,
      'rttMs': <String, Object?>{
        'p50': _percentile(50),
        'p99': _percentile(99),
        'samples': _rttMs.length,
      },
      'lastStep': session.step,
      'digestEvery': digestEvery,
      'digests': <String, Object?>{
        for (var i = 0; i < steps.length; i++) '${steps[i]}': hex[i],
      },
      'stats': session.stats.toJson(),
      'endedBy': endedBy,
    };
  }

  /// The least round trip that [p] in a hundred took no more than; null
  /// before the first answer.
  double? _percentile(int p) {
    if (_rttMs.isEmpty) return null;
    final sorted = List<double>.of(_rttMs)..sort();
    final at = ((p / 100) * sorted.length).ceil() - 1;
    return sorted[at.clamp(0, sorted.length - 1)];
  }
}
