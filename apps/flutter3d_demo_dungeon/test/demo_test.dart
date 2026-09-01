/// A run through the crypt, written down and played back to the same bytes.
///
///     flutter test test/demo_test.dart
///
/// `input_tape_test.dart` measures the claim on a toy. This measures it on the
/// game that ships: the level as authored, monsters and all, the dice the
/// snapshot carries, and the document a player would attach to a bug report —
/// serialised to a string and read back, because that is the form it travels
/// in. Not "close": the same snapshot, byte for byte.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_screens/flutter3d_screens.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

/// A [Storage] that keeps documents in a map, so the file path is exercised
/// without a disk.
final class _MemoryStorage implements Storage {
  final Map<String, String> _documents = <String, String>{};

  @override
  String? read(String name) => _documents[name];

  @override
  bool write(String name, String contents) {
    _documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => _documents.remove(name);
}

Level _crypt() => Level.fromJson(
  jsonDecode(File('assets/levels/crypt.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// The shipped assembly with nothing that draws, the way `playthrough_test.dart`
/// builds it — monsters included, since a replay that never rolled a die would
/// prove nothing about the dice.
({Staged staged, InputState input}) _stageCrypt() {
  final level = _crypt();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(
    level,
    world,
    input: input,
    registry: sampleRegistry(),
    inventory: startingInventory(),
  );
  world.update();
  return (staged: staged, input: input);
}

/// What a player might do for ten seconds: walk, look about, shoot, try the
/// use key. Not a route to anywhere — a run that touches every kind of input
/// the tape carries, so that dropping any one of them shows.
void _play(InputState input, int step) {
  input.setStickAxis(step % 90 < 60 ? 0.0 : 0.6, step % 120 < 90 ? 1.0 : 0.0);
  input.addLook((step % 7 - 3) * 0.004, step % 50 == 0 ? 0.01 : 0.0);
  if (step % 40 == 5) input.press(ShooterActions.fire);
  if (step % 40 == 8) input.release(ShooterActions.fire);
  if (step % 150 == 100) input.press(GameAction.use);
  if (step % 150 == 101) input.release(GameAction.use);
  if (step == 200) input.requestSlot(2);
}

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  test('a run through the crypt replays to the same snapshot', () {
    const steps = 600;

    // Live: play, recording as we go.
    final live = _stageCrypt();
    final start = live.staged.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    for (var i = 0; i < steps; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      live.staged.sim.step(_dt);
      live.input.endStep();
    }
    final ending = _bytes(live.staged.sim.save());
    expect(
      ending,
      isNot(_bytes(start)),
      reason: 'a run in which nothing happened would prove nothing',
    );

    // Through the document, as it would travel: a string.
    final sent = jsonEncode(
      Demo(
        level: 'assets/levels/crypt.json',
        start: start,
        tape: recorder.tape,
      ).toJson(),
    );
    final demo = Demo.fromJson(jsonDecode(sent) as Map<String, Object?>);
    expect(demo.steps, steps);

    // Replay: a fresh crypt, the demo's start restored into it, the tape
    // driving the input instead of the script above.
    final replay = _stageCrypt();
    replay.staged.sim.restore(demo.start);
    final playback = InputTapePlayback(demo.tape);
    while (!playback.isFinished) {
      playback.applyTo(replay.input);
      replay.staged.sim.step(_dt);
      replay.input.endStep();
    }

    expect(_bytes(replay.staged.sim.save()), ending);
  });

  test('and the demo the game writes on a death is readable', () {
    // The document path an actual run takes: `DemoFile` through an in-memory
    // storage, which is the same code the disk and the browser go through.
    final live = _stageCrypt();
    final start = live.staged.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    for (var i = 0; i < 30; i++) {
      _play(live.input, i);
      recorder.record(live.input);
      live.staged.sim.step(_dt);
      live.input.endStep();
    }
    final issues = <String>[];
    final file = DemoFile(
      appName: 'dungeon-test',
      storage: _MemoryStorage(),
      onIssue: issues.add,
    );

    expect(
      file.write(
        Demo(
          level: 'assets/levels/crypt.json',
          start: start,
          tape: recorder.tape,
        ),
      ),
      isTrue,
    );
    final read = file.read();

    expect(read, isNotNull);
    expect(read!.steps, 30);
    expect(read.level, 'assets/levels/crypt.json');
    expect(issues, isEmpty);
  });
}
