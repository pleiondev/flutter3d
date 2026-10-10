/// `HR3`: a level saved in the editor reaches the running game through
/// `ext.flutter3d.level.apply`, and the game takes it as little disturbed as
/// the change allows.
///
///     flutter test test/live_level_test.dart
///
/// What the extension does is `answerLevelApply`, tested here over the same
/// string parameters the VM service hands it.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _document({double wallAt = 5.0, double fog = 0.0}) =>
    <String, Object?>{
      'version': 1,
      'name': 'corridor',
      'fogDensity': fog,
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[wallAt, 0, 0],
          'size': <double>[1, 4, 4],
          'material': 'stone',
        },
      ],
    };

Level _level({double wallAt = 5.0, double fog = 0.0}) =>
    Level.fromJson(_document(wallAt: wallAt, fog: fog));

/// What a game did with each call, in order.
({LiveLevel live, List<String> calls}) _game({
  RunTimeline? timeline,
  bool prepares = false,
  String? prepareFails,
}) {
  final calls = <String>[];
  return (
    live: LiveLevel(
      level: _level(),
      present: (next, diff) => calls.add('present fog=${diff.fog}'),
      rebuild: (next) => calls.add('rebuild ${next.brushes.single.center.x}'),
      timeline: timeline,
      swapped: (next, step) => calls.add('swapped $step'),
      prepare: prepares || prepareFails != null
          ? (next) async {
              await Future<void>.delayed(Duration.zero);
              if (prepareFails != null) throw StateError(prepareFails);
              calls.add('prepare');
            }
          : null,
    ),
    calls: calls,
  );
}

Map<String, String> _send(Level level) => <String, String>{
  'document': jsonEncode(level.toJson()),
  'hash': level.digestHex,
};

void main() {
  test('a look-only edit is presented and the run is left alone', () {
    final game = _game();
    final applied = game.live.apply(_level(fog: 0.04));

    expect(game.calls, <String>['present fog=true']);
    expect(applied.swappedAt, isNull);
    expect(applied.rebuiltInPlace, isFalse);
    expect(game.live.level.fogDensity, 0.04);
  });

  test('a moved wall goes through the timeline, then the picture', () {
    final input = InputState();
    final rewind = RewindBuffer(stepsPerSecond: 60);
    // A run with nothing in it, as one part of the loop's snapshots that
    // notes every restore.
    final restored = <Object?>[];
    final loop = EngineLoop(input: input)
      ..snapshots.add(
        SnapshotPart.of(
          id: 'run',
          capture: () => const <String, Object?>{},
          restore: (Object? data, int _) => restored.add(data),
        ),
      );
    rewind.attach(loop);
    final timeline = RunTimeline(rewind: rewind, loop: loop);
    loop.runSteps(30);
    final game = _game(timeline: timeline);

    final applied = game.live.apply(_level(wallAt: 8.0));

    // Mutation: drop the `swapped` call — the run goes on under the new
    // level and the demo being recorded never hears of it.
    expect(game.calls, <String>[
      'rebuild 8.0',
      'swapped 0',
      'present fog=false',
    ]);
    expect(applied.swappedAt, 0);
    expect(restored, hasLength(1), reason: 'the keyframe the replay starts at');
    expect(
      timeline.history.single,
      TimelineLevelSwapped(0, _level(wallAt: 8.0).digestHex),
    );
  });

  test('with no timeline the wall is rebuilt in place, and says so', () {
    final game = _game();
    final applied = game.live.apply(_level(wallAt: 8.0));

    expect(game.calls.first, 'rebuild 8.0');
    expect(applied.rebuiltInPlace, isTrue);
  });

  test('the same level again touches nothing', () {
    final game = _game();
    expect(game.live.apply(_level()).diff.isEmpty, isTrue);
    expect(game.calls, isEmpty);
  });

  group('ext.flutter3d.level.apply', () {
    test('applies a document whose hash matches, and reports how', () async {
      final game = _game();
      final (:result, :error) = await answerLevelApply(
        game.live,
        _send(_level(fog: 0.04)),
      );

      expect(error, isNull);
      expect((result!['diff']! as Map<String, Object?>)['fog'], isTrue);
      expect(result['rebuiltInPlace'], isFalse);
    });

    test('refuses a document that changed on the way', () async {
      final game = _game();
      final parameters = _send(_level(fog: 0.04))
        ..['hash'] = _level().digestHex;

      final (:result, :error) = await answerLevelApply(game.live, parameters);

      expect(result, isNull);
      expect(error, contains('changed on the way'));
      expect(game.calls, isEmpty);
    });

    test('builds the level ahead, then swaps it in', () async {
      final game = _game(prepares: true);
      final (:result, :error) = await answerLevelApply(
        game.live,
        _send(_level(wallAt: 8.0)),
      );

      expect(error, isNull);
      expect(game.calls, <String>[
        'prepare',
        'rebuild 8.0',
        'present fog=false',
      ]);
      expect(game.live.level.brushes.single.center.x, 8.0);
    });

    test('keeps the level it had when the new one does not build', () async {
      final game = _game(prepareFails: 'no texture stone.png');
      final (:result, :error) = await answerLevelApply(
        game.live,
        _send(_level(wallAt: 8.0)),
      );

      expect(result, isNull);
      expect(error, contains('did not build'));
      expect(error, contains('no texture stone.png'));
      expect(game.calls, isEmpty);
      expect(game.live.level.brushes.single.center.x, 5.0);
    });

    test('the same level again prepares nothing', () async {
      final game = _game(prepares: true);
      await answerLevelApply(game.live, _send(_level()));
      expect(game.calls, isEmpty);
    });

    // Mutation: answer a stale patch as an ordinary refusal and the editor
    // never sends the whole level; mark a level that will not build as
    // stale and it sends it whole only to be refused again.
    test('a patch against the level the game has is applied', () async {
      final game = _game();
      final patch = LevelPatch.between(_level(), _level(wallAt: 8.0));

      final (:result, :error, :stale) = await answerLevelPatch(
        game.live,
        <String, String>{'patch': jsonEncode(patch.toJson())},
      );

      expect(error, isNull);
      expect(stale, isFalse);
      expect((result!['diff']! as Map<String, Object?>)['simulation'], <String>[
        'brushes',
      ]);
      expect(game.calls, <String>['rebuild 8.0', 'present fog=false']);
      expect(game.live.level.digestHex, _level(wallAt: 8.0).digestHex);
    });

    test(
      'a patch against another version is stale, and changes nothing',
      () async {
        final game = _game();
        final patch = LevelPatch.between(
          _level(fog: 0.04),
          _level(wallAt: 8.0),
        );

        final (:result, :error, :stale) = await answerLevelPatch(
          game.live,
          <String, String>{'patch': jsonEncode(patch.toJson())},
        );

        expect(result, isNull);
        expect(stale, isTrue);
        expect(error, contains(_level().digestHex));
        expect(game.calls, isEmpty);
      },
    );

    test('a patched level that does not build is refused, not stale', () async {
      final game = _game(prepareFails: 'no texture stone.png');
      final patch = LevelPatch.between(_level(), _level(wallAt: 8.0));

      final (:result, :error, :stale) = await answerLevelPatch(
        game.live,
        <String, String>{'patch': jsonEncode(patch.toJson())},
      );

      expect(stale, isFalse);
      expect(error, contains('did not build'));
      expect(game.live.level.brushes.single.center.x, 5.0);
    });

    test('refuses what is not a level, and what is missing', () async {
      final game = _game();
      expect(
        (await answerLevelApply(game.live, <String, String>{
          'document': '[1, 2]',
          'hash': 'x',
        })).error,
        contains('not a level'),
      );
      expect(
        (await answerLevelApply(game.live, <String, String>{})).error,
        contains('takes a document'),
      );
    });
  });
}
