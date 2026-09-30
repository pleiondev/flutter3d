/// The four ways two machines share a game, each over a `LoopbackTransport`
/// that is late and, where the way allows it, loses messages.
///
///     dart test
library;

import 'dart:convert';

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:test/test.dart';

/// A game small enough to read and still worth rolling back: two players
/// walking along a line, each by what their hands say, and a shared counter
/// every step adds both positions to — so a wrong guess about either hand
/// shows in the sum from then on.
final class _Walk {
  final List<int> at = <int>[0, 0];
  int sum = 0;
  int steps = 0;

  void step(List<Map<String, Object?>> hands) {
    for (var slot = 0; slot < 2; slot++) {
      at[slot] += (hands[slot]['move'] as int?) ?? 0;
    }
    sum += at[0] * 3 + at[1];
    steps++;
  }

  Map<String, Object?> save() => <String, Object?>{
    'at': List<int>.of(at),
    'sum': sum,
    'steps': steps,
  };

  void restore(Map<String, Object?> from) {
    final to = from['at']! as List<Object?>;
    at[0] = to[0]! as int;
    at[1] = to[1]! as int;
    sum = from['sum']! as int;
    steps = from['steps']! as int;
  }
}

/// Player [slot]'s hands on step [i]: different for each, changing often.
Map<String, Object?> _hands(int slot, int i) => <String, Object?>{
  'move': ((i ~/ (7 + slot * 4)) + slot).isEven ? 1 : -1,
};

void main() {
  group('PeerRoom', () {
    test('meets a machine that joined late, and hears what it plays', () {
      final (wireA, wireB) = LoopbackWire.pair(
        delaySteps: 3,
        lossRate: 0.5,
        seed: 2,
      );
      final host = PeerRoom(wireA, slot: 0, about: {'plays': 'elf'});
      // The host has been saying hello for a second into a room nobody
      // else is in yet.
      for (var i = 0; i < 60; i++) {
        host.step(1 / 60);
        wireA.tick();
        wireB.tick();
      }
      expect(host.met, isFalse);

      final guest = PeerRoom(wireB, slot: 1, about: {'plays': 'wizard'});
      for (var i = 0; i < 600 && !(host.met && guest.met); i++) {
        host.step(1 / 60);
        guest.step(1 / 60);
        wireA.tick();
        wireB.tick();
      }
      expect(host.peer, {'plays': 'wizard'});
      expect(guest.peer, {'plays': 'elf'});
      expect(host.otherSlot, 1);
      expect(guest.isHost, isFalse);
    });

    test('a channel hears only what was said on it', () {
      final (wireA, wireB) = LoopbackWire.pair();
      final a = PeerRoom(wireA, slot: 0);
      final b = PeerRoom(wireB, slot: 1);
      final heardOne = <Object?>[];
      final heardTwo = <Object?>[];
      b.channel('level:one').listen((m) => heardOne.add(m['n']));
      b.channel('level:two').listen((m) => heardTwo.add(m['n']));

      a.channel('level:one').send({'n': 1});
      a.channel('level:two').send({'n': 2});
      a.channel('nobody').send({'n': 3});
      wireB.tick();

      expect(heardOne, <Object?>[1]);
      expect(heardTwo, <Object?>[2]);
    });
  });

  group('RollbackPlay', () {
    test('both machines settle every step on the run that was played, and '
        'on the same ending', () {
      final (wireA, wireB) = LoopbackWire.pair(
        delaySteps: 6,
        lossRate: 0.1,
        seed: 5,
      );
      final games = <_Walk>[_Walk(), _Walk()];
      final settled = <Map<int, String>>[<int, String>{}, <int, String>{}];
      final captured = <int>[0, 0];
      final plays = <RollbackPlay<Map<String, Object?>>>[
        for (final slot in <int>[0, 1])
          RollbackPlay<Map<String, Object?>>(
            wire: slot == 0 ? wireA : wireB,
            localSlot: slot,
            capture: () => _hands(slot, captured[slot]++),
            applyAndStep: games[slot].step,
            save: games[slot].save,
            restore: games[slot].restore,
            endsAt: (after) => (after['steps']! as int) >= 300,
            onSettled: (step, after) => settled[slot][step] = jsonEncode(after),
          ),
      ];

      for (var i = 0; i < 400; i++) {
        plays[0].advance();
        plays[1].advance();
        wireA.tick();
        wireB.tick();
      }

      // What a machine that never guessed would have run: each player's
      // hands on the step they apply, `inputDelay` after they were
      // captured.
      final truth = _Walk();
      final truthSettled = <int, String>{};
      for (var s = 0; s < 400; s++) {
        truth.step(<Map<String, Object?>>[
          for (final slot in <int>[0, 1])
            s >= 3 ? _hands(slot, s - 3) : const <String, Object?>{},
        ]);
        truthSettled[s] = jsonEncode(truth.save());
      }

      final common = settled[0].keys.where(settled[1].containsKey).toList();
      expect(common.length, greaterThan(300));
      for (final step in common) {
        expect(settled[0][step], settled[1][step], reason: 'step $step');
        expect(settled[0][step], truthSettled[step], reason: 'step $step');
      }
      expect(plays.every((p) => p.connected), isTrue);
      final ends = <({int step, Map<String, Object?> after})>[
        plays[0].agreedEnd!,
        plays[1].agreedEnd!,
      ];
      expect(ends[0].step, ends[1].step);
      expect(jsonEncode(ends[0].after), jsonEncode(ends[1].after));
    });

    test('hands the frames over by slot, the same on both machines', () {
      final (wireA, _) = LoopbackWire.pair();
      final seen = <List<Map<String, Object?>>>[];
      final game = _Walk();
      RollbackPlay<Map<String, Object?>>(
        wire: wireA,
        localSlot: 1,
        capture: () => {'move': 1},
        applyAndStep: seen.add,
        save: game.save,
        restore: game.restore,
        inputDelay: 0,
      ).advance();
      // This machine is slot one: its own hands are second.
      expect(seen.single, <Map<String, Object?>>[
        <String, Object?>{},
        {'move': 1},
      ]);
    });
  });

  group('BatonStream', () {
    test('the watcher replays a turn in order and at its pace, and the '
        'turn goes across with its state', () {
      final (wireA, wireB) = LoopbackWire.pair(delaySteps: 6);
      final watched = <String>[];
      Map<String, Object?>? handedB;
      Map<String, Object?>? handedA;
      final a = BatonStream(
        wireA,
        holding: true,
        onFrame: (f) => fail('the one playing is shown no frames'),
        onEvent: (e) => watched.add('A heard ${e['what']}'),
        onBaton: (s) => handedA = s,
      );
      final perStep = <int>[];
      final b = BatonStream(
        wireB,
        holding: false,
        onFrame: (f) => watched.add('frame ${f['n']}'),
        onEvent: (e) => watched.add('event ${e['what']}'),
        onBaton: (s) => handedB = s,
      );

      for (var n = 0; n < 30; n++) {
        a.tellFrame({'n': n});
        if (n == 10) a.tellEvent({'what': 'tanker down'});
        a.step();
        final before = watched.length;
        b.step();
        perStep.add(watched.length - before);
        wireA.tick();
        wireB.tick();
      }
      a.pass({'player': 1, 'score': 90});
      for (var i = 0; i < 12; i++) {
        a.step();
        b.step();
        wireA.tick();
        wireB.tick();
      }

      final frames = watched.where((w) => w.startsWith('frame'));
      expect(frames.length, 30);
      // Every frame in the order it was flown, the event among them where
      // it happened.
      expect(
        watched.indexOf('event tanker down'),
        watched.indexOf('frame 10') + 1,
      );
      expect(frames, <String>[for (var n = 0; n < 30; n++) 'frame $n']);
      // Paced: never more than one frame in a step while it keeps up.
      expect(perStep.every((n) => n <= 2), isTrue);
      expect(handedB, {'player': 1, 'score': 90});
      expect(b.holding, isTrue);
      expect(a.holding, isFalse);
      expect(handedA, isNull);

      // The new holder's word reaches the old one.
      b.tellEvent({'what': 'again'});
      for (var i = 0; i < 6; i++) {
        wireA.tick();
      }
      a.step();
      expect(watched.last, 'A heard again');
    });

    test('a watcher far behind catches up rather than staying late', () {
      final (wireA, wireB) = LoopbackWire.pair();
      final shown = <Object?>[];
      final a = BatonStream(
        wireA,
        holding: true,
        onFrame: (_) {},
        onEvent: (_) {},
        onBaton: (_) {},
      );
      final b = BatonStream(
        wireB,
        holding: false,
        onFrame: (f) => shown.add(f['n']),
        onEvent: (_) {},
        onBaton: (_) {},
        catchUpAfter: 4,
      );
      // A stall: twenty frames arrive at once.
      for (var n = 0; n < 20; n++) {
        a.tellFrame({'n': n});
      }
      wireB.tick();
      b.step();
      expect(shown.length, 17, reason: 'down to the last few in one step');
      b.step();
      expect(shown.length, 18);
      expect(shown, <int>[for (var n = 0; n < 18; n++) n]);
    });
  });

  group('PeerFeed', () {
    test('keeps the latest word, and sends every so many steps', () {
      final (wireA, wireB) = LoopbackWire.pair(
        delaySteps: 3,
        lossRate: 0.3,
        seed: 9,
      );
      final a = PeerFeed(wireA, every: 2);
      final b = PeerFeed(wireB);
      expect(b.latest, isNull);
      var built = 0;
      for (var i = 0; i < 100; i++) {
        a.tell(() {
          built++;
          return {'x': i};
        });
        wireA.tick();
        wireB.tick();
      }
      for (var i = 0; i < 10; i++) {
        wireB.tick();
      }
      expect(built, 50, reason: 'a state not sent is not built');
      final x = b.latest!['x']! as int;
      expect(x.isEven, isTrue);
      expect(x, greaterThan(80));
    });
  });

  test('a turn arriving out of order is replayed in the order it was '
      'played', () {
    final wire = _Swapping();
    final shown = <Object?>[];
    final host = BatonStream(
      wire.a,
      holding: true,
      onFrame: (_) {},
      onEvent: (_) {},
      onBaton: (_) {},
    );
    final guest = BatonStream(
      wire.b,
      holding: false,
      onFrame: (f) => shown.add(f['n']),
      onEvent: (e) => shown.add(e['what']),
      onBaton: (_) {},
      catchUpAfter: 100,
    );
    for (var n = 0; n < 10; n++) {
      host.tellFrame({'n': n});
      if (n == 4) host.tellEvent({'what': 'hit'});
    }
    wire.flush();
    for (var i = 0; i < 20; i++) {
      guest.step();
    }
    expect(shown, <Object?>[0, 1, 2, 3, 4, 'hit', 5, 6, 7, 8, 9]);
  });

  test('the loopback loses unreliable messages only', () {
    final (a, b) = LoopbackWire.pair(lossRate: 0.5, seed: 4);
    final heard = <Object?>[];
    b.listen((m) => heard.add(m['n']));
    for (var n = 0; n < 200; n++) {
      a.send({'n': n}, reliable: n.isEven);
    }
    b.tick();
    expect(heard.whereType<int>().where((n) => n.isEven), hasLength(100));
    expect(a.lost, inInclusiveRange(30, 70));
    expect(heard, hasLength(200 - a.lost));
  });
}

/// A wire that keeps every message and delivers each pair of them the wrong
/// way round, as a jittery transport can.
final class _Swapping {
  late final _End a = _End(this, toB: true);
  late final _End b = _End(this, toB: false);
  final List<Map<String, Object?>> _toB = <Map<String, Object?>>[];

  void flush() {
    for (var i = 0; i + 1 < _toB.length; i += 2) {
      final first = _toB[i];
      _toB[i] = _toB[i + 1];
      _toB[i + 1] = first;
    }
    for (final message in _toB) {
      b._listener?.call(message);
    }
    _toB.clear();
  }
}

final class _End implements PeerWire {
  _End(this._wire, {required this.toB});

  final _Swapping _wire;
  final bool toB;
  void Function(Map<String, Object?> message)? _listener;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    if (toB) _wire._toB.add(message);
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _listener = onMessage;
}
