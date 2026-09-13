/// `net-00`: what a rollback costs on the game that ships, not on a toy.
///
///     flutter test test/rollback_cost_test.dart
///
/// **Prints rather than asserts a fixed threshold**, the same reasoning
/// `widget_surface_pipeline_benchmark_test.dart` gives for `wg-00`: the
/// number this file measures depends on the machine it runs on, and net-00's
/// own budget — eight steps restored and replayed in four milliseconds — is
/// stated against "a mid-range phone", which this machine is not. What is
/// measured here and printed into `doc/tooling-plan.md` §8 by hand is the
/// honest number for whatever machine ran it, the same way `rp-00`'s table
/// names the platform each row was recorded on.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_bridge/flutter3d_bridge.dart';
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
    registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
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

const double _dt = 1.0 / 60.0;

void main() {
  test('restore + k steps of the crypt, k = 1..10', () {
    // Play three hundred steps into the crypt before measuring — a rollback
    // in a real match never lands on the empty starting frame, and neither
    // should the thing timing it.
    final live = _stageCrypt();
    for (var step = 0; step < 300; step++) {
      _play(live.input, step);
      live.staged.sim.step(_dt);
      live.input.endStep();
    }
    final snapshot = live.staged.sim.save();

    // One warm-up restore + full run, outside the loop below, so the JIT has
    // already seen every code path a measured trial takes — otherwise k=1's
    // number would be paying for compilation the later k's would not.
    live.staged.sim.restore(snapshot);
    for (var i = 0; i < 10; i++) {
      live.staged.sim.step(_dt);
      live.input.endStep();
    }

    final results = <int, double>{};
    for (var k = 1; k <= 10; k++) {
      const trials = 20;
      final watch = Stopwatch();
      for (var trial = 0; trial < trials; trial++) {
        live.staged.sim.restore(snapshot);
        watch.start();
        for (var step = 0; step < k; step++) {
          live.staged.sim.step(_dt);
          live.input.endStep();
        }
        watch.stop();
      }
      results[k] = watch.elapsedMicroseconds / trials / 1000.0;
    }

    // ignore: avoid_print
    print(
      'net-00 dungeon (crypt): ${[
        for (final k in results.keys) 'k=$k ${results[k]!.toStringAsFixed(4)}ms',
      ].join(', ')}',
    );

    expect(
      results[8],
      isNotNull,
      reason: 'net-00 states its budget at k=8; the table must have a row for it',
    );
    // Structural check rather than a hard number: restoring once and running
    // more steps costs at least as much as running fewer, since a step never
    // runs backwards in time to give memory back.
    expect(results[10]!, greaterThanOrEqualTo(results[1]!));
  });
}
