/// `net-04`: two runs of the crypt whose input diverged partway through,
/// diffed down to the step and the field — on the game that ships, not on
/// a toy.
///
///     flutter test test/desync_diff_test.dart
///
/// **Why this lives in the app and not in `flutter3d_net`.** `diffRuns`
/// itself is genre-agnostic and is proven that way in
/// `flutter3d_net/test/snapshot_divergence_test.dart` — this file is the
/// other half `flutter3d_net` cannot provide: something that actually knows
/// how to stage the crypt and step `GameSimulation`, the same reason
/// `apps/flutter3d_demo_dungeon/test/replay_video_test.dart` carries
/// `rp-05`'s `checkReplay`/`renderReplayVideo` rather than
/// `flutter3d_testing` doing it generically. A `dart run
/// flutter3d_net:diff a.f3drun b.f3drun` reading two files off disk and
/// dispatching to whichever genre they name is the same terminal command
/// `rp-05` deferred to `flutter3d_build`/`ap-10` — not built here for the
/// same reason.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

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

/// The ordinary crawl `rewind_test.dart` plays, unless [step] is
/// [divergeAt] or later — from there on this run walks the other way,
/// standing in for a network frame one side received differently than the
/// other actually sent.
void _play(InputState input, int step, {int? divergeAt}) {
  final flipped = divergeAt != null && step >= divergeAt;
  input.setStickAxis(
    step % 90 < 60 ? 0.0 : (flipped ? -0.6 : 0.6),
    step % 120 < 90 ? 1.0 : 0.0,
  );
  input.addLook((step % 7 - 3) * 0.004, 0.0);
  if (step % 40 == 5) input.press(ShooterActions.fire);
  if (step % 40 == 8) input.release(ShooterActions.fire);
}

/// Plays the crypt for [steps] fixed steps with [divergeAt], recording a
/// digest every 25 and returning both the trace and a way to replay back to
/// any checkpoint's full saved state on demand.
({DigestTrace digests, Map<String, Object?> Function(int step) snapshotAt})
_run({required int steps, int? divergeAt}) {
  final digests = DigestTrace();
  final live = _stageCrypt();
  for (var step = 0; step < steps; step++) {
    _play(live.input, step, divergeAt: divergeAt);
    live.staged.sim.step(_dt);
    live.input.endStep();
    digests.observe(step + 1, live.staged.sim.save().toJson());
  }

  Map<String, Object?> snapshotAt(int step) {
    final replay = _stageCrypt();
    for (var s = 0; s < step; s++) {
      _play(replay.input, s, divergeAt: divergeAt);
      replay.staged.sim.step(_dt);
      replay.input.endStep();
    }
    return replay.staged.sim.save().toJson();
  }

  return (digests: digests, snapshotAt: snapshotAt);
}

void main() {
  test('two honest runs of the crypt never diverge', () {
    final a = _run(steps: 400);
    final b = _run(steps: 400);
    expect(
      diffRuns(
        a: a.digests,
        b: b.digests,
        snapshotAtA: a.snapshotAt,
        snapshotAtB: b.snapshotAt,
      ),
      isNull,
    );
  });

  test('input that diverged partway through names the checkpoint step and the '
      'field that actually differed', () {
    const divergeAt = 150;
    final truthful = _run(steps: 400);
    final corrupted = _run(steps: 400, divergeAt: divergeAt);

    final divergence = diffRuns(
      a: truthful.digests,
      b: corrupted.digests,
      snapshotAtA: truthful.snapshotAt,
      snapshotAtB: corrupted.snapshotAt,
    );

    expect(
      divergence,
      isNotNull,
      reason:
          'a run that turned the other way from step $divergeAt on '
          'must eventually land somewhere different',
    );
    expect(
      divergence!.step,
      greaterThanOrEqualTo(divergeAt),
      reason:
          'every checkpoint before the input actually diverged '
          'should still have matched',
    );
    expect(
      divergence.path,
      contains('.'),
      reason:
          'the path should have walked into the saved JSON rather than '
          'stopping at the first key — this run found the corruption '
          'first moved a monster\'s own focus (`actors.lastFocus[0]`) '
          'before it ever moved the player\'s own recorded position, '
          'which is itself the honest finding: turning changes who the '
          'nearest monster is looking at sooner than it changes where '
          'the walk has carried the player',
    );
    expect(divergence.expected, isNot(divergence.found));
  });
}
