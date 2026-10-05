/// The sanctum's cutscene: the first sight of the altar, played by the game
/// as it ships.
///
///     flutter test test/cutscene_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/cutscene_overlay.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Level _sanctum() => Level.fromJson(
  jsonDecode(File('assets/levels/sanctum.json').readAsStringSync())
      as Map<String, Object?>,
);

/// The sanctum staged as the game stages it, stepped through a [GameLoop]
/// the way the application steps it, with a tape recording every step.
final class _Run {
  _Run() {
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: input,
      registry: sampleRegistry(),
      inventory: startingInventory(),
    );
    world.update();
    loop = GameLoop(input: input, onStep: staged.sim.step)
      ..recorders.add(recorder);
  }

  final Level level = _sanctum();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  final InputTapeRecorder recorder = InputTapeRecorder(seed: 1);
  late final Staged staged;
  late final GameLoop loop;

  GameSimulation get sim => staged.sim;

  /// Puts the player in the corridor to the altar hall, where its trigger
  /// is.
  void walkIn() {
    staged.player.body.position.setValues(0.0, 0.9, -40.0);
    loop.runSteps(30);
  }

  Actor named(String name) =>
      staged.actors.actors.firstWhere((a) => a.name == name);
}

void main() {
  test('the corridor to the altar starts the cutscene', () {
    final it = _Run()..walkIn();
    final cutscene = it.sim.cutscene;
    expect(cutscene, isNotNull, reason: 'the trigger did not start it');
    expect(cutscene!.name, 'the_altar');
    expect(cutscene.player.sequence.hasCamera, isTrue);
  });

  test('the three on the dais come down to meet the player', () {
    final it = _Run()..walkIn();
    final before = it.named('altar_north').position!.z;
    it.loop.runSteps(it.sim.cutscene!.player.remaining);
    expect(it.sim.cutscene, isNull);
    // From the dais at z = -62 towards its mark at -55.
    expect(it.named('altar_north').position!.z, greaterThan(before + 3.0));
  });

  test('a skip ends where watching ends, and the tape has every step', () {
    // Watching: the loop at the clock's speed, a frame at a time.
    final watched = _Run()..walkIn();
    while (watched.sim.cutscene != null) {
      watched.loop.advance(1 / 60);
    }
    // Skipping: the rest of it in one go, through the loop.
    final skipped = _Run()..walkIn();
    skipped.loop.runSteps(skipped.sim.cutscene!.player.remaining);
    expect(skipped.recorder.tape.steps, watched.recorder.tape.steps);
    expect(
      StateDigest.of(skipped.sim.save().toJson()),
      StateDigest.of(watched.sim.save().toJson()),
    );
  });

  test('the altar, from the cutscene\'s camera at its second key', () async {
    // Drawn the way the replay golden is: the sanctum loaded and dressed by
    // the run as it ships, on the software device. A picture, because what a
    // camera path is for is what it shows — the hall, the dais and the three
    // on it, and no wall in the way.
    const width = 160;
    const height = 100;
    final it = cpuTestDevice(width: width, height: height);
    final run = RunCubit(
      DungeonRun(
        firstLevel: 'assets/levels/sanctum.json',
        registry: sampleRegistry(),
        input: InputState(),
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon', storage: _Storage()),
        device: it.device,
      ),
    );
    await run.begin();
    final level = (run.state as RunPlaying<LevelReady>).level;
    level.staged.player.body.position.setValues(0.0, 0.9, -40.0);
    for (var i = 0; i < 30 + 150; i++) {
      level.staged.sim.step(1 / 60);
    }
    final cutscene = level.staged.sim.cutscene!;
    final at = Vector3.zero();
    final look = Vector3.zero();
    final fov = cutscene.player.cameraAt(at, look)!;
    final camera = CameraNode(
      projection: PerspectiveProjection(
        fovYRadians: fov * 3.141592653589793 / 180,
        near: 0.05,
        far: 200.0,
      ),
    )..setPositionFrom(at);
    camera.lookAt(look);
    final scene = level.loaded.scene..add(camera);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final result = renderer.render(
      width: width,
      height: height,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      settings: const RenderSettings(),
    );
    final pixels = await it.device.readPixels(result.frame);
    await expectMatchesGolden((
      pixels: pixels!.buffer.asUint8List(),
      width: width,
      height: height,
      drawCalls: result.drawCalls,
    ), 'test/goldens/cutscene-altar.png');
  });

  test('the three on the dais start up before they come down', () async {
    // Through the run as it ships, which is where the monsters have their
    // graphs. Just after the cue the jump is playing.
    final it = cpuTestDevice(width: 16, height: 16);
    final run = RunCubit(
      DungeonRun(
        firstLevel: 'assets/levels/sanctum.json',
        registry: sampleRegistry(),
        input: InputState(),
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon', storage: _Storage()),
        device: it.device,
      ),
    );
    await run.begin();
    final level = (run.state as RunPlaying<LevelReady>).level;
    level.staged.player.body.position.setValues(0.0, 0.9, -40.0);
    final animations = level.staged.actors.strides! as ActorAnimations;
    final tanks = <Actor>[
      for (final name in <String>['altar_west', 'altar_east', 'altar_north'])
        level.staged.actors.actors.firstWhere((a) => a.name == name),
    ];
    // The player stands in the trigger from the start, so the cutscene's
    // steps are the run's; 3.6 seconds in, and a few steps more.
    for (var i = 0; i < 216 + 8; i++) {
      level.staged.sim.step(1 / 60);
    }
    // Started by the first step, so one behind the run.
    expect(level.staged.sim.cutscene!.player.step, 216 + 7);
    // Mutation: a gesture asked of nothing, or a machine without the cue
    // states, leaves them standing in their idle.
    expect(<String>[
      for (final t in tanks) animations.graphOf(t)!.state,
    ], everyElement('cue:Jump'));
  });

  testWidgets('the overlay says the subtitle and offers the skip', (
    WidgetTester tester,
  ) async {
    var skipped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CutsceneOverlay(
          fade: 0.5,
          subtitle: 'It knows you are here.',
          skipHint: 'Space to skip',
          onSkip: () => skipped++,
        ),
      ),
    );
    expect(find.text('It knows you are here.'), findsOne);
    await tester.tap(find.byKey(const ValueKey<String>('cutscene:skip')));
    expect(skipped, 1);
  });
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
