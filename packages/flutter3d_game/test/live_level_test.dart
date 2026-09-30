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
({LiveLevel live, List<String> calls}) _game({RunTimeline? timeline}) {
  final calls = <String>[];
  return (
    live: LiveLevel(
      level: _level(),
      present: (next, diff) => calls.add('present fog=${diff.fog}'),
      rebuild: (next) => calls.add('rebuild ${next.brushes.single.centre.x}'),
      timeline: timeline,
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
    final restored = <Snapshot>[];
    final timeline = RunTimeline(
      rewind: rewind,
      input: input,
      stepSim: (dt) {},
      restore: restored.add,
    );
    for (var step = 0; step < 30; step++) {
      rewind.recorder.record(input);
      if (rewind.keyframeDue) rewind.keyframe(Snapshot(<String, Object?>{}));
    }
    final game = _game(timeline: timeline);

    final applied = game.live.apply(_level(wallAt: 8.0));

    expect(game.calls, <String>['rebuild 8.0', 'present fog=false']);
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
    test('applies a document whose hash matches, and reports how', () {
      final game = _game();
      final (:result, :error) = answerLevelApply(
        game.live,
        _send(_level(fog: 0.04)),
      );

      expect(error, isNull);
      expect((result!['diff']! as Map<String, Object?>)['fog'], isTrue);
      expect(result['rebuiltInPlace'], isFalse);
    });

    test('refuses a document that changed on the way', () {
      final game = _game();
      final parameters = _send(_level(fog: 0.04))
        ..['hash'] = _level().digestHex;

      final (:result, :error) = answerLevelApply(game.live, parameters);

      expect(result, isNull);
      expect(error, contains('changed on the way'));
      expect(game.calls, isEmpty);
    });

    test('refuses what is not a level, and what is missing', () {
      final game = _game();
      expect(
        answerLevelApply(game.live, <String, String>{
          'document': '[1, 2]',
          'hash': 'x',
        }).error,
        contains('not a level'),
      );
      expect(
        answerLevelApply(game.live, <String, String>{}).error,
        contains('takes a document'),
      );
    });
  });
}
