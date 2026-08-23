/// Starting, dying, moving on, quitting and coming back — through this game.
///
///     flutter test test/run_test.dart
///
/// **The route `playing_the_game_test.dart` could not take.** That file mounts
/// the application, so the level load starts inside `initState` — inside the
/// fake-async zone `testWidgets` runs in — and never completes. This one never
/// mounts anything: it drives `PlatformerRun` from a plain `test()` with a
/// `CpuDevice` underneath, where the shipped `LevelLoader` reads the shipped
/// documents perfectly well.
///
/// The dungeon proved this route first. What it covers is everything about a
/// run that is not a widget: the chain between the two levels, what carries
/// across it, and the four rules a run has to keep.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart'; // RunPlaying/RunFailed, SaveFile
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String _first = 'assets/levels/first_steps.json';

/// A storage that keeps everything in a map.
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

/// Sixteen by nine, because nothing here looks at the picture: the device
/// exists so the loader has somewhere to upload the level's textures.
({PlatformerRun run, _Storage storage}) _game() {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final storage = _Storage();
  return (
    storage: storage,
    run: PlatformerRun(
      firstLevel: _first,
      saves: SaveFile(appName: 'platformer', storage: storage),
      input: InputState(),
      openDevice: () async => device,
      // The widget's half, which this test does not have: a camera, a box for
      // the runner, the interpolators.
      onLevelBuilt: (LevelReady level, GraphicsDevice device) {},
      // No beat between levels: that is a pause on a results screen nobody is
      // watching here, and 1.4 seconds per test adds up.
      pauseBetweenLevels: Duration.zero,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new game opens the first level with a full set of lives', () async {
    final it = _game();

    expect(await it.run.begin(), isFalse, reason: 'resumed nothing');

    final playing = it.run.status as RunPlaying<LevelReady>;
    expect(playing.asset, _first);
    expect(playing.level.sim.lives, 3);
    expect(playing.level.sim.elapsed, 0.0);
  });

  test('and a level that is not there says so rather than going black',
      () async {
    final it = _game();

    await it.run.load('assets/levels/no_such_level.json');

    expect(it.run.status, isA<RunFailed<LevelReady>>());
  });

  group('moving on', () {
    test('carries the run into the next level rather than restarting it',
        () async {
      // **Three lives used to mean three lives per level**, and the clock on
      // the summit read as the time for the last climb. A run spans levels and
      // a simulation does not.
      final it = _game();
      await it.run.begin();
      final first = (it.run.status as RunPlaying<LevelReady>).level;

      // Spend something on the first level, so there is a tally to carry.
      first.sim.step(1.0 / 60.0);
      final spent = first.sim.elapsed;
      expect(spent, greaterThan(0.0));

      // Reach the exit the way the game does — by saying so, because walking
      // there is `playthrough_test.dart`'s job and not this file's.
      first.staged.runner.body.teleport(first.sim.respawnPoint);
      await _finish(it.run);

      final playing = it.run.status as RunPlaying<LevelReady>;
      expect(playing.asset, isNot(_first),
          reason: 'it never left the first level, so this proves nothing');
      final second = playing.level;
      expect(second.sim.elapsed, greaterThanOrEqualTo(spent),
          reason: 'the clock started again on the second level');
      expect(second.sim.lives, first.sim.lives,
          reason: 'the lives were handed back at the door');
    });

    test('and the shipped chain arrives at a second document', () async {
      // The first level names the second, and the second is on disk. Read from
      // the documents rather than written here, so a renamed level is a red
      // test rather than a game that ends at level one.
      final it = _game();
      await it.run.begin();
      final first = (it.run.status as RunPlaying<LevelReady>).level;

      // **From the document, not from the simulation.** `sim.nextLevel` is
      // null until the exit is actually reached — the first draft asked it
      // before finishing and got null every time.
      final next = first.loaded.level.next;
      expect(next, isNotNull, reason: 'the first level leads nowhere');

      await _finish(it.run);

      expect((it.run.status as RunPlaying<LevelReady>).asset, next);
    });
  });

  group('losing', () {
    test('throws the save away, because a platformer has lives', () async {
      // **The place this game and the crypt disagree, and both are right.** A
      // save from before the last life would undo the loss; a crypt has no
      // lives, so its save is where you come back to.
      final it = _game();
      await it.run.begin();
      it.run.save();
      expect(it.storage.documents['save.json'], isNotNull);

      final level = (it.run.status as RunPlaying<LevelReady>).level;
      // Straight to nought lives, which is what falling three times does.
      while (level.sim.state != RunState.lost) {
        level.staged.runner.body.teleport(Vector3(0.0, -80.0, 0.0));
        level.sim.step(1.0 / 60.0);
      }
      it.run.observe();
      await it.run.advance();

      expect(it.storage.documents['save.json'], isNull);
    });

    test('and a restart throws away what the run had carried', () async {
      // **On the second level, and it has to be.** The first draft restarted on
      // the first one, where there is nothing carried yet — so removing the
      // reset changed nothing and the mutation walked through. A restart only
      // means anything once there is a tally to lose.
      final it = _game();
      await it.run.begin();
      final first = (it.run.status as RunPlaying<LevelReady>).level;
      for (var i = 0; i < 120; i++) {
        first.sim.step(1.0 / 60.0);
      }
      await _finish(it.run);

      final second = (it.run.status as RunPlaying<LevelReady>).level;
      expect(second.sim.elapsed, greaterThan(1.0),
          reason: 'nothing was carried, so this proves nothing');

      await it.run.restart();

      final after = (it.run.status as RunPlaying<LevelReady>).level;
      expect(after.sim.lives, 3);
      expect(after.sim.elapsed, 0.0,
          reason: 'the clock of the run before carried into a restart');
    });
  });

  test('the save is a level and a snapshot, and comes back as both', () async {
    final it = _game();
    await it.run.begin();
    it.run.save();

    final again = _game();
    again.storage.documents.addAll(it.storage.documents);

    expect(await again.run.begin(), isTrue, reason: 'did not resume');
    expect((again.run.status as RunPlaying<LevelReady>).asset, _first);
  });
}

/// Finishes the level that is up, and moves on.
///
/// **The runner is put on the exit rather than walked to it**, and it has to be
/// put there rather than told: an `Exit` is reached by a collision, so
/// `activate` does not reach it and `nextLevel` stays null. The first draft of
/// this helper did that, and the test above passed while comparing a level to
/// itself.
///
/// Where the runner has to walk is `playthrough_test.dart`'s subject; this file
/// is about what happens after they arrive.
Future<void> _finish(PlatformerRun run) async {
  final level = (run.status as RunPlaying<LevelReady>).level;
  final exit = level.staged.mechanisms.all.whereType<Exit>().first;
  level.staged.runner.body.teleport(exit.collider.position);
  for (var i = 0; i < 4 && level.sim.nextLevel == null; i++) {
    level.sim.step(1.0 / 60.0);
  }
  run.observe();
  await run.advance();
}
