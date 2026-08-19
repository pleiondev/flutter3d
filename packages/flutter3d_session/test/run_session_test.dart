/// Starting, dying, moving on, quitting and coming back — for every game.
///
///     flutter test test/run_session_test.dart
///
/// Three games had three answers to this: a cubit in the dungeon, nine private
/// methods inside the platformer's widget, and nothing at all in racing. What
/// they had in common was the *sequencing*, and every rule in it has been got
/// wrong at least once.
///
/// Driven against a toy game rather than a real one, and that is the point: the
/// rules below are about order and guards, not about crypts. A test that had to
/// load a level to ask whether `advance` runs twice would be a test of a level.
library;

import 'dart:async';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A level, as small as one can be: a name, an outcome and what comes next.
final class _Level {
  _Level(this.name);

  final String name;
  RunOutcome outcome = RunOutcome.playing;
  String? next;
  Map<String, Object?> restored = const <String, Object?>{};
}

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// A game with two levels and a record of everything it was asked.
final class _Game extends RunSession<_Level> {
  _Game({required super.saves, super.firstLevel = 'one'});

  final List<String> opened = <String>[];
  final List<String> carried = <String>[];
  int freshened = 0;

  /// Set to hold the next `open` until it is let go, so two `advance` calls can
  /// overlap the way two frames do.
  Completer<void>? gate;

  /// Levels that refuse to load.
  final Set<String> broken = <String>{};

  @override
  Future<_Level> open(String asset) async {
    opened.add(asset);
    if (gate != null) await gate!.future;
    if (broken.contains(asset)) throw StateError('no such level: $asset');
    return _Level(asset)..next = asset == 'one' ? 'two' : null;
  }

  @override
  RunOutcome outcomeOf(_Level level) => level.outcome;

  @override
  String? nextOf(_Level level) => level.next;

  @override
  Snapshot snapshotOf(_Level level) =>
      Snapshot(<String, Object?>{'where': level.name});

  @override
  void restoreInto(_Level level, Snapshot snapshot) =>
      level.restored = snapshot.data;

  @override
  void carryFrom(_Level level, String next) => carried.add(next);

  @override
  void startFresh() => freshened++;
}

_Game _game() => _Game(saves: SaveFile(appName: 't', storage: _Storage()));

void main() {
  group('starting', () {
    test('a new game opens the first level and says it did not resume',
        () async {
      final game = _game();

      expect(await game.begin(), isFalse);

      expect(game.opened, <String>['one']);
      expect(game.freshened, 1, reason: 'a new game kept the last one’s state');
      expect(game.status, isA<RunPlaying<_Level>>());
    });

    test('and a level that will not read says so rather than going black',
        () async {
      // In two of the three games this used to be a black screen for ever: the
      // load caught its own throw and printed it to a console nobody playing
      // can see.
      final game = _game()..broken.add('one');

      await game.begin();

      expect(game.status, isA<RunFailed<_Level>>());
      expect((game.status as RunFailed<_Level>).asset, 'one');
    });

    test('and a save naming a level that is gone gives a game, not an error',
        () async {
      // Renaming a level file should not brick every save that mentions it.
      final game = _game()..broken.add('gone');
      game.saves.write('gone', const Snapshot(<String, Object?>{}));

      expect(await game.begin(), isFalse);

      expect(game.status, isA<RunPlaying<_Level>>());
      expect(game.saves.read(), isNull, reason: 'the broken save was kept');
    });

    test('and a good save is resumed into its own level', () async {
      final game = _game();
      game.saves.write('two', const Snapshot(<String, Object?>{'where': 'two'}));

      expect(await game.begin(), isTrue);

      final playing = game.status as RunPlaying<_Level>;
      expect(playing.asset, 'two');
      expect(playing.level.restored, <String, Object?>{'where': 'two'});
      expect(game.freshened, 0, reason: 'a resumed run was started fresh');
    });
  });

  group('moving on', () {
    test('waits until the run is won', () async {
      final game = _game();
      await game.begin();

      await game.advance();

      expect(game.opened, <String>['one'], reason: 'it moved on mid-level');
    });

    test('and does not do it twice while the next level is loading', () async {
      // **The guard nothing was testing.** A finished level stays finished for
      // every frame until the next one is up, so without it each of those
      // frames starts another load — a dozen of them on a slow disk. The two
      // calls here overlap the way two frames do: the first is still inside
      // `open` when the second arrives.
      final game = _game();
      await game.begin();
      (game.status as RunPlaying<_Level>).level.outcome = RunOutcome.won;
      game.observe();

      game.gate = Completer<void>();
      final first = game.advance();
      final second = game.advance();
      game.gate!.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(game.opened, <String>['one', 'two'],
          reason: 'the same level was loaded ${game.opened.length - 1} times');
    });

    test('and asks what carries before reading the next one', () async {
      // The only moment both levels are knowable: the one being left is still
      // up, and the one being entered is named.
      final game = _game();
      await game.begin();
      (game.status as RunPlaying<_Level>).level.outcome = RunOutcome.won;
      game.observe();

      await game.advance();

      expect(game.carried, <String>['two']);
    });

    test('and the end of the game clears the save rather than loading', () async {
      final game = _game();
      await game.begin();
      final level = (game.status as RunPlaying<_Level>).level
        ..outcome = RunOutcome.won
        ..next = null;
      game.observe();
      game.saves.write('one', snapshotOfNothing);

      await game.advance();

      expect(game.opened, <String>['one']);
      expect(game.saves.read(), isNull,
          reason: 'the next launch resumes a run that is already over');
      expect(level.next, isNull);
    });
  });

  group('the save', () {
    test('is not written for a run that has ended', () async {
      // A save written at the exit is a save the next launch resumes, putting
      // the player back at the end of a level they already beat.
      final game = _game();
      await game.begin();
      (game.status as RunPlaying<_Level>).level.outcome = RunOutcome.lost;
      game.observe();

      game.save();

      expect(game.saves.read(), isNull);
    });

    test('and is written for one that has not', () async {
      final game = _game();
      await game.begin();

      game.save();

      expect(game.saves.read()?.level, 'one');
    });
  });

  group('restarting', () {
    test('reloads the level that is up and starts the state fresh', () async {
      // A run that begins with the health you died at is not a restart.
      final game = _game();
      await game.begin();
      final before = game.freshened;

      await game.restart();

      expect(game.opened, <String>['one', 'one']);
      expect(game.freshened, before + 1);
    });

    test('and drops the save with it', () async {
      // A run left on disk after a restart is resumed on the next launch, and
      // the player is put back where they gave up rather than where they asked
      // to start.
      final game = _game();
      await game.begin();
      game.save();
      expect(game.saves.read(), isNotNull);

      await game.restart();

      expect(game.saves.read(), isNull);
    });

    test('and works from a level that would not load', () async {
      // The one place a player is most likely to press it.
      final game = _game()..broken.add('one');
      await game.begin();
      expect(game.status, isA<RunFailed<_Level>>());

      game.broken.clear();
      await game.restart();

      expect(game.status, isA<RunPlaying<_Level>>());
    });
  });

  group('watching', () {
    test('reports a change once, not on every step', () async {
      // A finished run stays finished for every frame afterwards, so a status
      // emitted per step would rebuild the tree sixty times a second.
      final game = _game();
      await game.begin();
      final seen = <RunStatus<_Level>>[];
      game.onChanged = seen.add;

      for (var i = 0; i < 30; i++) {
        game.observe();
      }
      expect(seen, isEmpty, reason: 'nothing changed and it said so 30 times');

      (game.status as RunPlaying<_Level>).level.outcome = RunOutcome.won;
      for (var i = 0; i < 30; i++) {
        game.observe();
      }

      expect(seen, hasLength(1));
    });

    test('and isOver answers for the screen', () async {
      final game = _game();
      await game.begin();
      expect(game.isOver, isFalse);

      (game.status as RunPlaying<_Level>).level.outcome = RunOutcome.lost;
      game.observe();

      expect(game.isOver, isTrue);
    });
  });
}

const Snapshot snapshotOfNothing = Snapshot(<String, Object?>{});
