/// The cubit `main.dart` now wraps `PlatformerRun` in.
///
///     flutter test test/run_cubit_test.dart
///
/// **What this covers and what it does not.** `run_test.dart` already drives
/// `PlatformerRun` itself — starting, dying, moving on, saving, resuming — in
/// full, straight through `RunSession`. A `Cubit` is a thin wrapper around
/// that: it forwards every call and re-exposes `RunSession.onChanged` as
/// `emit`. What is worth a test of its own is the wrapping — that `state`
/// tracks the run, that a failed load is readable off it the way `main.dart`
/// now reads it, and that BLoC's own promise holds here too: a status is
/// published once, not on every frame, which is what keeps a rebuild off the
/// sixty-hertz step.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart'; // RunPlaying/RunFailed, SaveFile
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/run_cubit.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// A cubit over the shipped documents, with a real device and no window.
({RunCubit run, _Storage storage}) _game({String first = _first}) {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final storage = _Storage();
  return (
    storage: storage,
    run: RunCubit(
      PlatformerRun(
        firstLevel: first,
        saves: SaveFile(appName: 'platformer', storage: storage),
        input: InputState(),
        openDevice: () async => device,
        onLevelBuilt: (LevelReady level, GraphicsDevice device) {},
        pauseBetweenLevels: Duration.zero,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('begins the way the run underneath it does', () async {
    final it = _game();

    expect(await it.run.begin(), isFalse, reason: 'resumed nothing');

    final state = it.run.state;
    expect(state, isA<RunPlaying<LevelReady>>());
    expect((state as RunPlaying<LevelReady>).asset, _first);
    expect(it.run.level, state.level);
    expect(it.run.isOver, isFalse);
  });

  test('a level that is not there is readable straight off state', () async {
    // **This is what `main.dart` reads now.** The widget used to copy the
    // error and its asset into two fields of its own from `onChanged`; the
    // cubit's `state` carries both already, and copying them a second time is
    // a second place for the two to disagree.
    final it = _game(first: 'assets/levels/no_such_level.json');

    await it.run.begin();

    final state = it.run.state;
    expect(state, isA<RunFailed<LevelReady>>());
    expect((state as RunFailed<LevelReady>).asset, contains('no_such_level'));
  });

  test('a status is published once, not on every frame', () async {
    // `GameSimulation`'s outcome stays finished for every step after the
    // exit. A status emitted per step would rebuild the tree sixty times a
    // second, which is the whole reason this game is a cubit rather than a
    // callback into `setState` on every tick.
    final it = _game();
    await it.run.begin();
    final emitted = <RunStatus<LevelReady>>[];
    final subscription = it.run.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    final sim = (it.run.state as RunPlaying<LevelReady>).level.sim;
    for (var i = 0; i < 30; i++) {
      sim.step(1.0 / 60.0);
      it.run.observe();
    }
    await Future<void>.delayed(Duration.zero);

    expect(
      emitted,
      isEmpty,
      reason: 'nothing changed, and thirty states were emitted anyway',
    );
  });

  test('restarting rebuilds the level rather than resuming it', () async {
    final it = _game();
    await it.run.begin();
    final first = it.run.state as RunPlaying<LevelReady>;
    first.level.sim.step(1.0 / 60.0);
    expect(first.level.sim.elapsed, greaterThan(0.0));

    await it.run.restart();

    final second = it.run.state as RunPlaying<LevelReady>;
    expect(second.asset, first.asset);
    expect(
      second.level.sim.elapsed,
      0.0,
      reason: 'a restart that keeps the clock you died at is not one',
    );
  });

  test(
    'load puts a named level up directly, the way a start-over does',
    () async {
      // `main.dart`'s `_startOver` calls this after a level that would not read
      // — straight back to the first one, skipping whatever was saved.
      final it = _game();
      await it.run.begin();

      await it.run.load(_first);

      expect((it.run.state as RunPlaying<LevelReady>).asset, _first);
    },
  );

  test('the save is written and read back through the cubit', () async {
    final it = _game();
    await it.run.begin();

    it.run.save();
    expect(it.storage.documents['save.json'], isNotNull);

    final resumed = _game();
    resumed.storage.documents.addAll(it.storage.documents);
    expect(await resumed.run.begin(), isTrue, reason: 'did not resume');
  });
}
