/// Ten seconds of the crypt, rewound to any moment and lived again.
///
///     flutter test test/rewind_test.dart
///
/// `rewind_test.dart` in the game layer measures the arithmetic on a toy. This
/// measures it on the shipped game, monsters and dice included: the buffer is
/// driven the way `main.dart` drives it, and a rewind to an arbitrary moment
/// has to land on the snapshot the game itself wrote at that moment, byte for
/// byte. The size of a snapshot is measured here too, since the buffer's own
/// doc quotes it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

Level _crypt() => Level.fromJson(
  jsonDecode(File('assets/levels/crypt.json').readAsStringSync())
      as Map<String, dynamic>,
);

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

void _play(InputState input, int step) {
  input.setStickAxis(step % 90 < 60 ? 0.0 : 0.6, step % 120 < 90 ? 1.0 : 0.0);
  input.addLook((step % 7 - 3) * 0.004, 0.0);
  if (step % 40 == 5) input.press(ShooterActions.fire);
  if (step % 40 == 8) input.release(ShooterActions.fire);
  if (step == 200) input.requestSlot(2);
}

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  test('a rewind lands on the snapshot the game wrote at that moment', () {
    final live = _stageCrypt();
    final buffer = RewindBuffer(stepsPerSecond: 60, history: 10.0);
    final before = <int, String>{};
    final loop = GameLoop(
      input: live.input,
      onStep: (dt) {
        if (buffer.keyframeDue) buffer.keyframe(live.staged.sim.save());
        // The state every step saw, for the moments below to be checked
        // against. Every seventh, to keep the test quick.
        final step = buffer.step - 1;
        if (step % 7 == 0) before[step] = _bytes(live.staged.sim.save());
        live.staged.sim.step(dt);
      },
    )..recorders.add(buffer.recorder);
    for (var i = 0; i < 900; i++) {
      _play(live.input, i);
      loop.advance(1 / 60);
    }

    expect(buffer.available, greaterThanOrEqualTo(10.0));

    for (final seconds in <double>[0.5, 3.0, 7.35, 9.9]) {
      final point = buffer.rewindBy(seconds)!;
      // Nearest checked step at or before the point, then play to the point.
      final replay = _stageCrypt();
      replay.staged.sim.restore(point.snapshot);
      final playback = InputTapePlayback(point.tapeToPoint);
      while (!playback.isFinished) {
        playback.applyTo(replay.input);
        replay.staged.sim.step(1 / 60);
        replay.input.endStep();
      }
      final expected = before[point.step];
      if (expected == null) continue;
      expect(
        _bytes(replay.staged.sim.save()),
        expected,
        reason: '$seconds seconds back, step ${point.step}',
      );
    }
    expect(
      before.keys.where((s) => s >= 900 - 600).where((s) => s % 7 == 0),
      isNotEmpty,
      reason: 'at least one of the moments above was actually compared',
    );
  });

  test('and a snapshot of the crypt is the size the buffer quotes', () {
    // The buffer's doc says 1.6 kilobytes as JSON, measured here at 1582
    // bytes. A number in a doc is a claim, and this is where it is held: a
    // snapshot that doubled would move the memory the doc promises, and one
    // that halved would mean a system stopped writing itself down.
    final live = _stageCrypt();
    for (var i = 0; i < 300; i++) {
      live.input.setStickAxis(0.0, 1.0);
      live.staged.sim.step(1 / 60);
      live.input.endStep();
    }
    final size = utf8.encode(_bytes(live.staged.sim.save())).length;

    expect(size, inInclusiveRange(1200, 2400), reason: '$size bytes');
  });
}
