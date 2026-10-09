/// A run recorded in the game, verified by a tool that plays the crypt blind:
/// the same start, the same checkpoints, the fire and the water included.
///
///     flutter test test/headless_verify_test.dart
///
/// The crypt's elements were the game's alone, so a `.f3drun` recorded with
/// them diverged in `resimulate` before its first step — the headless run had
/// no crates, no torches burning and no water in it. They are stood by the
/// shooter package now, the same way on both sides; this holds the two to the
/// bit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_content/shooter_staging.dart'
    show ShooterHeadlessGame;
import 'package:flutter3d_demo_dungeon/src/monster_graphs.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;
const String _asset = 'assets/levels/crypt.json';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  setUpAll(() => startPhysics(asked: 'native'));
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a run the game recorded with its elements retraces headless, bit for '
      'bit', () async {
    // The crypt opened the way the game opens it: the level loaded with its
    // scene, the elements stood into the run's one world, put back to blank.
    final it = cpuTestDevice(width: 16, height: 16);
    final input = InputState();
    final run = RunCubit(
      DungeonRun(
        firstLevel: _asset,
        registry: sampleRegistry(
          extra: const <EntityKind>[WidgetSurfaceKind()],
        ),
        input: input,
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon', storage: _Storage()),
        device: it.device,
      ),
    );
    await run.begin();
    final level = (run.state as RunPlaying<LevelReady>).level;
    final sim = level.staged.sim;
    final crypt = level.crypt!;

    // Recorded as the game records a demo: from the state the level opened
    // in, a checkpoint every so many steps, and the input of each step.
    final start = sim.save();
    expect(
      jsonEncode(start.toJson()),
      contains('"crypt"'),
      reason: 'a start with no elements in it would verify nothing of them',
    );
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    final checkpoints = DigestTrace();
    for (var step = 1; step <= 300; step++) {
      // Walking and turning, and a shot now and then: the walker the
      // elements follow moves, and the rounds go through the world.
      input
        ..setStickAxis(step % 90 < 60 ? 0.0 : 0.5, step % 120 < 90 ? 1.0 : 0.0)
        ..addLook((step % 7 - 3) * 0.004, 0.0);
      if (step % 40 == 5) input.press(ShooterActions.fire);
      if (step % 40 == 8) input.release(ShooterActions.fire);
      recorder.record(input);
      input.beginStep();
      sim.step(_dt);
      if (step % checkpoints.every == 0) {
        checkpoints.observe(step, sim.save().toJson());
      }
      input.endStep();
    }
    expect(
      crypt.world.fires(),
      isNotEmpty,
      reason: 'the torches burn in the world the checkpoints cover',
    );
    final ended = StateDigest.of(sim.save().toJson());

    final demo = Demo(
      level: _asset,
      levelHash: level.loaded.level.digestHex,
      start: start,
      tape: recorder.tape,
      buildStamp: 'test',
      checkpoints: checkpoints,
      physics: usePhysics().name,
    );
    // The form it travels in.
    final sent = Demo.fromJson(
      jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
    );

    final document = Level.fromJson(
      jsonDecode(File(_asset).readAsStringSync()) as Map<String, Object?>,
    );
    // The monsters walked by their clips headless as in the game: their
    // strides are run state too, and a tool composing the dungeon hangs
    // them the same way.
    final clips = await MonsterClips.load();
    final game = ShooterHeadlessGame(
      extra: const <EntityKind>[WidgetSurfaceKind()],
      dress: clips.hangOn,
    );
    final found = resimulate(game: game, level: document, demo: sent);
    // Mutation: `ShooterHeadlessGame.start` standing no crypt — the fresh
    // run starts with no elements and is `ResimulationStartDiffers`.
    // Mutation: `dress` left out — the headless monsters have no strides
    // in their state, where the game's have, and the starts differ.
    expect(found, isA<ResimulationRetraced>());
    final retraced = found as ResimulationRetraced;
    expect(retraced.checkpoints, checkpoints.steps.length);
    expect(retraced.finalDigest, ended);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
