/// `HR3`: a run with an editor's edit in it, written down and played back.
///
///     flutter test test/demo_level_swap_test.dart
///
/// The live half goes the way `main.dart` goes: a rewind buffer and the demo's
/// own recorder beside it, the edit through `LiveLevel` and the timeline, the
/// step it took effect at written into the demo by `LiveLevel.swapped`. The
/// replay is `PlatformerRun.replay` in a game of its own, from the file's
/// JSON. The claim is that the two arrive at the same bytes — and that
/// without the swap in the file they would not.
library;

import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const String _first = 'assets/levels/first_steps.json';

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

PlatformerRun _game(InputState input) {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return PlatformerRun(
    firstLevel: _first,
    saves: SaveFile(appName: 'platformer', storage: _Storage()),
    input: input,
    openDevice: () async => device,
    onLevelBuilt: (String asset, LevelReady level, GraphicsDevice device) {},
    pauseBetweenLevels: Duration.zero,
  );
}

/// Forward most of the time, a jump a second: a run the floor matters to.
void _play(InputState input, int step) {
  if (step % 30 < 22) {
    input.press(GameAction.moveForward);
  } else {
    input.release(GameAction.moveForward);
  }
  if (step % 60 == 0) input.press(GameAction.jump);
  if (step % 60 == 3) input.release(GameAction.jump);
}

/// Steps [from] to [to] through [loop], as `main.dart` does: the rewind and
/// the demo recording through it, the checkpoint after each step.
void _live(
  PlatformerRun run,
  InputState input,
  EngineLoop loop,
  DemoRecording demo, {
  required int from,
  required int to,
}) {
  for (var step = from; step < to; step++) {
    _play(input, step);
    loop.runSteps(1);
    demo.observe(run.level!.sim.save);
  }
}

/// [level] with every brush half a metre lower: the runner, mid-run, is
/// suddenly over a floor that is not where it was.
Level _lowered(Level level) {
  final document = level.toJson();
  return Level.fromJson(<String, Object?>{
    ...document,
    'brushes': <Object?>[
      for (final brush in document['brushes']! as List<Object?>)
        switch (brush) {
          {'at': final List<Object?> at} => <String, Object?>{
            ...brush as Map<String, Object?>,
            'at': <double>[
              (at[0]! as num).toDouble(),
              (at[1]! as num).toDouble() - 0.5,
              (at[2]! as num).toDouble(),
            ],
          },
          _ => brush,
        },
    ],
  });
}

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a run with an edit at step K, saved and replayed, arrives where the '
      'live run did', () async {
    const edited = 150;
    const end = 300;
    final input = InputState();
    final run = _game(input);
    await run.begin();
    final start = run.level!.sim.save();
    final demo = DemoRecording(
      level: _first,
      levelHash: run.level!.loaded.level.digestHex,
      start: start,
      seed: start.data.integer('random'),
    );
    final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
    final (:loop, genre: _) = run.ownLoop();
    rewind.attach(loop);
    demo.attach(loop);
    final timeline = RunTimeline(rewind: rewind, loop: loop);

    _live(run, input, loop, demo, from: 0, to: edited);
    final applied = await LiveLevel(
      level: run.level!.loaded.level,
      timeline: timeline,
      prepare: run.prepareEdit,
      rebuild: (Level next) => run.installEdit(),
      present: (Level next, LevelDiff diff) => run.announceEdit(),
      swapped: (Level next, int step) =>
          demo.levelSwapped(next, stepsAgo: rewind.step - step),
    ).applyWhenReady(_lowered(run.level!.loaded.level));
    _live(run, input, loop, demo, from: edited, to: end);
    final arrived = _bytes(run.level!.sim.save());

    final sent = jsonEncode(demo.demo(buildStamp: 'test-build').toJson());
    final file = Demo.fromJson(jsonDecode(sent) as Map<String, Object?>);
    expect(file.steps, end);
    expect(
      file.levelSwaps.single.step,
      applied.swappedAt,
      reason: 'the demo started with the timeline, so the steps agree',
    );
    expect(file.levelSwaps.single.step, lessThan(edited));
    expect(file.levelSwaps.single.levelHash, run.level!.loaded.level.digestHex);

    final replayInput = InputState();
    final replayRun = _game(replayInput);
    await replayRun.begin();
    final replayed = await replayRun.replay(file);

    expect(replayed.steps, end);
    expect(
      replayed.divergence,
      isNull,
      reason: 'the replay keeps to the checkpoints written live',
    );
    expect(_bytes(replayRun.level!.sim.save()), arrived);
    expect(
      replayRun.level!.loaded.level.digestHex,
      file.levelSwaps.single.levelHash,
      reason: 'the replay ends in the edited level, as the run did',
    );

    // Mutation: drop the swap from the file — the replay plays through the
    // shipped floor to the end — and it has to arrive somewhere else, or the
    // edit never reached the runner and the test above compared nothing.
    final unswapped = Demo(
      level: file.level,
      levelHash: file.levelHash,
      start: file.start,
      tape: file.tape,
      buildStamp: file.buildStamp,
      checkpoints: file.checkpoints,
    );
    final controlInput = InputState();
    final control = _game(controlInput);
    await control.begin();
    final parted = await control.replay(unswapped);
    expect(_bytes(control.level!.sim.save()), isNot(arrived));
    expect(parted.divergence, isNotNull);
    expect(parted.divergence!.step, greaterThan(file.levelSwaps.single.step));
  });

  test('a demo recorded in another level is refused before a step', () async {
    final run = _game(InputState());
    await run.begin();
    final start = run.level!.sim.save();

    // Mutation: drop the path check in `replay` — the tape plays into the
    // level that happens to be up and answers with a divergence, which reads
    // as a determinism bug rather than as the wrong file.
    await expectLater(
      run.replay(
        Demo(
          level: 'assets/levels/ascent.json',
          levelHash: run.level!.loaded.level.digestHex,
          start: start,
          tape: InputTape(seed: 1, frames: const <InputFrame>[]),
          buildStamp: 'test-build',
          checkpoints: DigestTrace(),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
