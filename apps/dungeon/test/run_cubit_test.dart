/// Starting, dying, moving on, quitting and coming back.
///
///     flutter test test/run_cubit_test.dart
///
/// **None of this existed and none of it could be tested.** The crypt was the
/// only level, `next` was empty, dying printed "You died" and left the player
/// standing in a corridor at nought health with no way out but closing the
/// application, and `sim.save()` — written and covered by 349 lines in the
/// package — was called by nothing.
///
/// It is testable because it is a cubit rather than four more fields on a
/// widget. Loading a level needs a graphics device and does **not** need a
/// window, so this drives the real `LevelLoader` over the real documents with
/// `CpuDevice` underneath — which is the door round the wall
/// `apps/platformer/test/playing_the_game_test.dart` records, where the same
/// loader never completes under `testWidgets`.
library;

import 'package:dungeon/src/run_cubit.dart';
import 'package:dungeon/src/staging.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _crypt = 'assets/levels/crypt.json';

/// Sixteen by nine, because nothing here looks at the picture.
///
/// The device exists so that `LevelLoader` has somewhere to upload the level's
/// textures to. What is being tested is the chain, and the chain runs at any
/// size — the platformer learned this the expensive way, with a frame test that
/// had produced no output after ten minutes at 320 by 180.
GraphicsDevice _device() => CpuDevice(
      width: 16,
      height: 9,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );

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

/// A cubit over the shipped documents, with a real device and no window.
({RunCubit run, _Storage storage}) _game({String first = _crypt}) {
  final device = _device();
  final storage = _Storage();
  return (
    storage: storage,
    run: RunCubit(DungeonRun(
      firstLevel: first,
      registry: sampleRegistry(),
      input: InputState(),
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: storage),
      // **The device, and nothing else.** Forty lines of the game's own
      // assembly used to sit here — the loader and both sets of visuals,
      // copied — and the copy had lost `bindLights()`, so every torch in this
      // harness lit nothing while the game's lit the room. That is what
      // `one_assembly_test` is named after, and this file was outside the two
      // calls it watched.
      device: device,
    )),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new game starts at the first level and says it did not resume',
      () async {
    final it = _game();

    expect(await it.run.begin(), isFalse, reason: 'resumed nothing');

    final state = it.run.state;
    expect(state, isA<RunPlaying<LevelReady>>());
    expect((state as RunPlaying<LevelReady>).asset, _crypt);
    expect(state.outcome, RunOutcome.playing);
  });

  test('a level that is not there fails loudly rather than silently', () async {
    // **This used to be a black screen for ever.** The application caught the
    // throw and printed it, which is a line in a console nobody playing the
    // game can see.
    final it = _game(first: 'assets/levels/no_such_level.json');

    await it.run.begin();

    expect(it.run.state, isA<RunFailed<LevelReady>>());
    expect((it.run.state as RunFailed<LevelReady>).asset, contains('no_such_level'));
  });

  test('and a save naming a level that is gone gives a game, not an error',
      () async {
    // A player whose save is broken should get to play. Mutation: drop the
    // `state is RunFailed` fallback in `begin`, and a renamed level file bricks
    // every save that mentions it.
    final it = _game();
    it.storage.documents['save.json'] =
        '{"level":"assets/levels/deleted.json","run":{}}';

    expect(await it.run.begin(), isFalse);

    expect(it.run.state, isA<RunPlaying<LevelReady>>());
    expect((it.run.state as RunPlaying<LevelReady>).asset, _crypt);
    expect(it.storage.documents['save.json'], isNull,
        reason: 'the broken save was kept and will fail again next launch');
  });

  group('dying', () {
    test('can be restarted, which is the whole of what was missing', () async {
      // There was no restart at all: the only way out of a death was to close
      // the application.
      final it = _game();
      await it.run.begin();
      final first = it.run.state as RunPlaying<LevelReady>;

      // Spend some health so the restart has something to undo.
      it.run.inventory.damage(40.0);
      expect(it.run.inventory.health.current, lessThan(100.0));

      await it.run.restart();

      final second = it.run.state as RunPlaying<LevelReady>;
      expect(second.asset, first.asset, reason: 'restarted a different level');
      expect(identical(second.level.staged, first.level.staged), isFalse,
          reason: 'the same simulation was handed back');
      expect(it.run.inventory.health.isAlive, isTrue);
      expect(it.run.inventory.health.current, 100.0,
          reason: 'a restart that keeps the health you died at is not one');
    });

    test('and the save goes with it', () async {
      // A run left on disk after a restart is resumed on the next launch, and
      // the player is put back where they gave up rather than where they asked
      // to start.
      final it = _game();
      await it.run.begin();
      it.run.save();
      expect(it.storage.documents['save.json'], isNotNull);

      await it.run.restart();

      expect(it.storage.documents['save.json'], isNull);
    });
  });

  group('the save', () {
    test('is written and read back into the same level', () async {
      final it = _game();
      await it.run.begin();

      it.run.save();

      final resumed = _game();
      resumed.storage.documents.addAll(it.storage.documents);
      expect(await resumed.run.begin(), isTrue, reason: 'did not resume');
      expect((resumed.run.state as RunPlaying<LevelReady>).asset, _crypt);
    });

    test('is not written for a run that is already over', () async {
      // Mutation: drop the `isOver` guard. A finished game writes a save, the
      // next launch resumes it, and the player is put back at the exit of a
      // level they have already beaten.
      final it = _game();
      await it.run.begin();
      final sim = (it.run.state as RunPlaying<LevelReady>).level.staged.sim;

      // Kill the player, then let the simulation notice on its next step.
      it.run.inventory.damage(999.0);
      sim.step(1.0 / 60.0);
      it.run.observe();
      expect((it.run.state as RunPlaying<LevelReady>).outcome, RunOutcome.lost);

      it.run.save();

      expect(it.storage.documents['save.json'], isNull);
    });
  });

  group('the end of a level', () {
    test('is republished once, not on every frame', () async {
      // `GameState.complete` stays true for every frame after the exit. A state
      // emitted per step would rebuild the tree sixty times a second, which is
      // the boundary this application draws around `flutter_bloc`.
      final it = _game();
      await it.run.begin();
      final emitted = <RunStatus<LevelReady>>[];
      final subscription = it.run.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      final sim = (it.run.state as RunPlaying<LevelReady>).level.staged.sim;
      for (var i = 0; i < 30; i++) {
        sim.step(1.0 / 60.0);
        it.run.observe();
      }
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty,
          reason: 'nothing changed, and thirty states were emitted anyway');
    });

    test('does not move on twice while the next one is loading', () async {
      // Mutation: drop `_movingOn`. Every frame between the exit and the new
      // level starts another load, which on a slow disk is a dozen of them.
      final it = _game();
      await it.run.begin();

      // The crypt says nothing comes next, so `advance` should clear the save
      // and stop — and stop *once*.
      it.run.save();
      await it.run.advance();
      await it.run.advance();

      expect(it.run.state, isA<RunPlaying<LevelReady>>(),
          reason: 'a level with no next unloaded itself');
    });
  });
}
