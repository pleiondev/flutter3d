@TestOn('vm')
library;

/// `net-02`'s fallback transport, proved against a real second process
/// rather than a mock — the same reasoning
/// `flutter3d_session/test/run_timeline_extensions_test.dart` gives for
/// `rp-02`: a relay that only ever talked to an in-memory fake would be
/// proving a protocol nobody outside this test speaks.
///
///     dart test test/relay_test.dart
///
/// Starts `bin/relay.dart` as a real subprocess, reads back which port the
/// system actually gave it, connects two real [WebSocketTransport]s to the
/// same room over `ws://127.0.0.1`, and drives the exact `NetSession`
/// convergence `net_session_test.dart` already proved over
/// [LoopbackTransport] — this time end to end through a socket and a
/// process this test does not control the timing of.
///
/// `@TestOn('vm')`: spawns a real process and opens real sockets, neither
/// of which exists on the web.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);
  final GameRandom dice;
  double x = 0.0;
  double y = 0.0;
  int rolls = 0;

  void step(Map<String, Object?> a, Map<String, Object?> b) {
    x += (a['move'] as num?)?.toDouble() ?? 0.0;
    y += (b['move'] as num?)?.toDouble() ?? 0.0;
    if ((a['fire'] as bool?) ?? false) rolls += dice.nextInt(1000);
    if ((b['fire'] as bool?) ?? false) rolls += dice.nextInt(1000);
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    'y': y,
    'rolls': rolls,
    'random': dice.state,
  });

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    y = data.number('y');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
  }
}

Map<String, Object?> _sideA(int step) => <String, Object?>{
  'move': step % 4 < 2 ? 1.0 : -1.0,
  'fire': step % 7 == 0,
};

Map<String, Object?> _sideB(int step) => <String, Object?>{
  'move': step % 5 < 3 ? 0.5 : -0.5,
  'fire': step % 9 == 0,
};

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start(
    'dart',
    <String>['run', 'bin/relay.dart', '0'],
    workingDirectory: Directory.current.path,
  );
  final portFound = Completer<int>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final match = RegExp(
          r'flutter3d_net relay listening on (\d+)',
        ).firstMatch(line);
        if (match != null && !portFound.isCompleted) {
          portFound.complete(int.parse(match.group(1)!));
        }
      });
  final port = await portFound.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      process.kill();
      throw StateError('the relay never printed the port it bound to');
    },
  );
  await subscription.cancel();
  return (process: process, port: port);
}

void main() {
  test(
    'two NetSessions over a real relay and real sockets converge on the '
    'same digests',
    () async {
      final relay = await _startRelay();
      addTearDown(() => relay.process.kill());

      final room = 'test-room-${DateTime.now().microsecondsSinceEpoch}';
      final roomUri = Uri.parse(
        'ws://127.0.0.1:${relay.port}/room/$room',
      );
      final transportA = await WebSocketTransport.connect(roomUri);
      final transportB = await WebSocketTransport.connect(roomUri);
      addTearDown(transportA.close);
      addTearDown(transportB.close);

      final toyA = _Toy(1);
      final toyB = _Toy(1);
      final digestsA = DigestTrace();
      final digestsB = DigestTrace();
      late final NetSession sessionA;
      late final NetSession sessionB;
      sessionA = NetSession(
        transport: transportA,
        captureLocalFrame: () => _sideA(sessionA.step),
        applyAndStep: (local, remote) => toyA.step(local, remote),
        save: toyA.save,
        restore: toyA.restore,
        inputDelay: 2,
        maxRollbackFrames: 16,
        onSettled: (step, after) => digestsA.observe(step + 1, after.toJson()),
      );
      sessionB = NetSession(
        transport: transportB,
        captureLocalFrame: () => _sideB(sessionB.step),
        applyAndStep: (local, remote) => toyB.step(remote, local),
        save: toyB.save,
        restore: toyB.restore,
        inputDelay: 2,
        maxRollbackFrames: 16,
        onSettled: (step, after) => digestsB.observe(step + 1, after.toJson()),
      );

      // A real socket introduces real, if small, scheduling delay — steps
      // are paced on a timer rather than driven back-to-back in a tight
      // loop, so messages have an actual chance to round-trip through the
      // relay between one side's step and the other's.
      const steps = 200;
      for (var i = 0; i < steps + 40; i++) {
        sessionA.advance();
        sessionB.advance();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final divergence = digestsA.divergenceFromHex(digestsB.hexDigests);
      expect(
        divergence,
        isNull,
        reason:
            'the two sides should agree on every settled checkpoint through '
            'the real relay: $divergence',
      );
      expect(digestsA.steps, isNotEmpty);
      expect(sessionA.droppedCorrections, 0);
      expect(sessionB.droppedCorrections, 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a third socket asking for a room that already has two is refused',
    () async {
      final relay = await _startRelay();
      addTearDown(() => relay.process.kill());
      final room = 'crowded-${DateTime.now().microsecondsSinceEpoch}';
      final roomUri = Uri.parse('ws://127.0.0.1:${relay.port}/room/$room');

      final a = await WebSocketTransport.connect(roomUri);
      final b = await WebSocketTransport.connect(roomUri);
      addTearDown(a.close);
      addTearDown(b.close);

      final third = WebSocketChannel.connect(roomUri);
      await third.ready;
      // The relay closes a rejected socket rather than leaving it open and
      // silent — the stream ends once that close reaches this side,
      // whether or not this side ever sent anything of its own.
      final closed = Completer<void>();
      third.stream.listen((_) {}, onDone: closed.complete);
      await closed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail(
          'a third socket in an already-full room should have been closed '
          'by the relay rather than left open',
        ),
      );
    },
  );
}
