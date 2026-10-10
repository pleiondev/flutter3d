/// A level saved in the editor while the crypt runs (`HR3`): built ahead,
/// put in under the run through the timeline, and the run — its fires and
/// its water too — carried on where it stood.
///
///     flutter test test/level_edit_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_content/crypt.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

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

DungeonRun _run(InputState input) => DungeonRun(
  firstLevel: 'assets/levels/crypt.json',
  registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
  input: input,
  inventory: startingInventory(),
  saves: SaveFile(appName: 'dungeon', storage: _Storage()),
  device: cpuTestDevice(width: 16, height: 16).device,
);

/// The door the game opens for the editor, as `main.dart` builds it.
LiveLevel _live(DungeonRun run, RunTimeline timeline) => LiveLevel(
  level: run.level!.loaded.level,
  timeline: timeline,
  prepare: run.prepareEdit,
  rebuild: (Level next) => run.installEdit(),
  present: (Level next, LevelDiff diff) => run.installEdit(),
);

/// Plays [steps] steps of the level that is up through a loop, the way
/// `main.dart` does — the shooter stepping whichever level is up, the rewind
/// attached — and hands back the timeline over them.
RunTimeline _played(DungeonRun run, InputState input, {required int steps}) {
  final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
  final shooter = ShooterPlugin(kinds: const <EntityKind>[])
    ..simulation = run.level?.staged.sim;
  final loop = EngineLoop(input: input, plugins: <Flutter3dPlugin>[shooter])
    ..addSystem('test.level', LoopPhase.input, (LoopContext _) {
      shooter.simulation = run.level?.staged.sim;
    });
  rewind.attach(loop);
  loop.runSteps(steps);
  return RunTimeline(rewind: rewind, loop: loop);
}

/// [level] with its last brush forty metres up, out of everybody's way.
Level _raised(Level level) {
  final document = level.toJson();
  final brushes = <Object?>[...document['brushes']! as List<Object?>];
  final last = Map<String, Object?>.of(
    brushes.removeLast()! as Map<String, Object?>,
  );
  final at = (last['at']! as List<Object?>).cast<num>();
  last['at'] = <double>[
    at[0].toDouble(),
    at[1].toDouble() + 40.0,
    at[2].toDouble(),
  ];
  return Level.fromJson(<String, Object?>{
    ...document,
    'brushes': <Object?>[...brushes, last],
  });
}

void main() {
  setUpAll(() => startPhysics(asked: 'native'));
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an edit goes in under the run, which carries on where it stood, its '
      'fire still burning', () async {
    final input = InputState();
    final run = _run(input);
    await run.begin();
    final before = run.level!;
    // A crate set alight, so there is something of the crypt's own to
    // carry over.
    final crypt = before.crypt!;
    final crate = crypt.wood.firstWhere((w) => w.kind == WoodKind.crate);
    crypt.world.setTemperature(crate.body, 900.0);
    final timeline = _played(run, input, steps: 90);
    final burning = crypt.world.fires().length;
    expect(burning, greaterThan(crypt.torches.length));
    final standing = before.staged.player.body.position.clone();
    final health = before.staged.player.inventory.health.current;
    String wood(CryptWorld crypt) => jsonEncode(<Object?>[
      for (final w in <CryptWood>[...crypt.wood, ...crypt.pieces]) w.serial,
    ]);
    final woodBefore = wood(crypt);
    final lastBrush = before.loaded.level.brushes.last.center.y;

    final applied = await _live(
      run,
      timeline,
    ).applyWhenReady(_raised(before.loaded.level));

    final after = run.level!;
    expect(applied.swappedAt, isNotNull, reason: 'a brush is the run’s');
    expect(after, isNot(same(before)));
    expect(after.loaded.level.brushes.last.center.y, lastBrush + 40.0);
    expect(
      after.staged.player.body.position.distanceTo(standing),
      lessThan(1e-6),
      reason: 'the run was lived again up to now',
    );
    expect(after.staged.player.inventory.health.current, health);
    // Mutation: the run written down after the crypt is stood into the
    // edit rather than before — the world has been cleared for the edit by
    // then, and the burning crate comes back as the level placed it, cold.
    final carried = after.crypt!;
    expect(wood(carried), woodBefore);
    expect(carried.world.fires().length, burning);
    // Mutation: `takeEdited` never set — the widget takes the edit for a new
    // level, counts it as one more entered and starts its run over.
    expect(run.takeEdited(), isTrue);
    expect(run.takeEdited(), isFalse, reason: 'told once');
  });

  test('another level is refused, and the one up is kept', () async {
    final input = InputState();
    final run = _run(input);
    await run.begin();
    final before = run.level!;
    final document = _raised(before.loaded.level).toJson()
      ..['name'] = 'elsewhere';
    // Mutation: drop the name check in `prepareEdit` — the vaults' document
    // goes in under a run in the crypt.
    await expectLater(
      _live(
        run,
        _played(run, input, steps: 1),
      ).applyWhenReady(Level.fromJson(document)),
      throwsA(isA<StateError>()),
    );
    expect(run.level, same(before));
  });
}
