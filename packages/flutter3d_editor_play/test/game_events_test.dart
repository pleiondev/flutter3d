/// `P12`: what a running game posts about itself — a level up, the player
/// dead — kept beside its console, numbered, and read by cursor.
///
///     dart test test/game_events_test.dart
library;

import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' show Event;

/// Lets the fake's replies and events cross the stream to the run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

PostedEvent _event(int sequence, [String kind = 'pickup.taken']) => PostedEvent(
  sequence: sequence,
  kind: kind,
  time: DateTime.utc(2026),
  data: const <String, Object?>{},
);

void main() {
  group('an attached game', () {
    test(
      'keeps what the game posted, and nothing else on the stream',
      () async {
        final game = FakeGame();
        final run = fakeAttachedRun(game);
        await run.start();
        await _settle();

        game
          ..posts('flutter3d.level.loaded', <String, Object?>{
            'level': 'crypt',
          }, 1767225600000)
          ..posts('Flutter.Frame', <String, Object?>{'elapsed': 16})
          ..posts('flutter3d.player.died');
        await _settle();

        // Mutation: not listening to `Extension` (the subscription or the
        // `streamListen`) keeps nothing; dropping the prefix check keeps
        // Flutter's own frame events too.
        expect(
          run.events.value.map((it) => (it.sequence, it.kind)).toList(),
          <(int, String)>[(1, 'level.loaded'), (2, 'player.died')],
        );
        expect(run.events.value.first.data, <String, Object?>{
          'level': 'crypt',
        });
        expect(
          run.events.value.first.time,
          DateTime.fromMillisecondsSinceEpoch(1767225600000),
        );
        expect(
          game.calls
              .where((it) => it['method'] == 'streamListen')
              .map((it) => (it['params']! as Map<String, Object?>)['streamId']),
          contains('Extension'),
        );
      },
    );
  });

  group('a game flutter run started', () {
    test('is listened to at the VM service the tool reports', () async {
      final game = FakeGame();
      final it = fakeFlutterRun(game: game);
      await it.run.start();
      game.posts('flutter3d.level.loaded');
      it.tool.event('app.debugPort', <String, Object?>{
        'appId': 'a1',
        'wsUri': 'ws://127.0.0.1:8181/ws',
      });
      await pumpEventQueue();

      game.posts('flutter3d.pickup.taken', <String, Object?>{'gift': 'key'});
      await pumpEventQueue();

      // Mutation: not opening the connection at `app.debugPort` keeps
      // nothing. The event posted before the tool said where the game was
      // is not seen: nothing was listening yet.
      expect(it.run.events.value.single.kind, 'pickup.taken');
      expect(it.run.events.value.single.data, <String, Object?>{'gift': 'key'});
    });

    test('lets go of the VM service when the game exits', () async {
      final game = FakeGame();
      final it = fakeFlutterRun(game: game);
      await it.run.start();
      it.tool.event('app.debugPort', <String, Object?>{
        'appId': 'a1',
        'wsUri': 'ws://x',
      });
      await pumpEventQueue();

      it.tool.exit(0);
      await pumpEventQueue();
      game.posts('flutter3d.player.died');
      await pumpEventQueue();

      // Mutation: not stopping the listening on exit keeps hearing a game
      // that, as far as the panel is concerned, is gone.
      expect(it.run.events.value, isEmpty);
    });

    test('a VM service it cannot reach is said, not thrown', () async {
      final tool = FakeFlutterTool();
      final run = FlutterRun(
        projectRoot: '/game',
        start: (_, _) async => tool,
        connect: (String _) async => throw StateError('connection refused'),
      );
      await run.start();
      tool.running();
      await pumpEventQueue();

      expect(run.state.value, isA<PlayRunning>());
      expect(run.console.value.single, contains('events will not arrive'));
    });
  });

  group('read by cursor', () {
    final events = <PostedEvent>[
      _event(1, 'level.loaded'),
      _event(2),
      _event(3, 'player.died'),
      _event(4),
    ];

    test('from 0 is everything, and the next cursor is the last', () {
      final read = eventsSince(events, 0);
      expect(read.events.map((it) => it.sequence), <int>[1, 2, 3, 4]);
      expect(read.next, 4);
      expect(read.missed, 0);
    });

    test('from a cursor is only what came after it', () {
      // Mutation: `>=` instead of `>` gives the event at the cursor twice.
      expect(eventsSince(events, 2).events.map((it) => it.sequence), <int>[
        3,
        4,
      ]);
      expect(eventsSince(events, 4).events, isEmpty);
      expect(eventsSince(events, 4).next, 4);
    });

    test('a filter does not bring back what it left out', () {
      final read = eventsSince(events, 0, kinds: <String>{'player.died'});
      expect(read.events.single.sequence, 3);
      // Mutation: the cursor as the last event returned (3) gives event 4
      // to the next unfiltered call as new, after it was already passed.
      expect(read.next, 4);
    });

    test('says how many the cap dropped before they were read', () {
      final kept = <PostedEvent>[_event(7), _event(8)];
      expect(eventsSince(kept, 2).missed, 4);
      expect(eventsSince(kept, 6).missed, 0);
    });

    test('a cursor past the last event starts again from the first', () {
      // A cursor from a run that a new one replaced, which numbers from 1.
      final read = eventsSince(events, 40);
      expect(read.restarted, isTrue);
      expect(read.events, hasLength(4));
      expect(read.next, 4);
    });

    test('the log is capped like the console, the oldest dropped', () {
      final log = GameEventLog();
      for (var i = 0; i < GameEventLog.limit + 3; i++) {
        log.take(
          Event(kind: 'Extension', timestamp: 0)
            ..extensionKind = 'flutter3d.tick',
        );
      }
      expect(log.events.value, hasLength(GameEventLog.limit));
      expect(log.events.value.first.sequence, 4);
    });
  });
}
