/// A stretch of the shipped map, written down and played back to the same
/// bytes and the same digests.
///
///     flutter test test/demo_test.dart
///
/// The `rp-01` round trip, on the game that ships rather than on the bare
/// simulation `tape_test.dart` (`flutter3d_game_strategy`) already drives.
/// This genre had `MatchDemo`'s own shape, and every one of its four
/// refusals, tested there — what none of that touches is the shipped map,
/// its real crowd, and the far side's actual bot, rather than orders written
/// by hand into a `StrategySimulation` built in code. See
/// `apps/flutter3d_demo_racing/test/demo_test.dart` for the sibling this
/// mirrors and the reason it lives in the app rather than the package.
///
/// **The tape is the queue's, not the match's.** `Match.step` always asks
/// every bot to decide before it steps the simulation underneath it, with no
/// way to tell it not to — so a replay that called `Match.step` again would
/// ask the far side's bot to decide a second time, on the state its first
/// decision already produced, and add a second helping of orders to a step
/// that already has one. `OrderTapePlayback.applyTo` takes an `OrderQueue`,
/// not a `Match`, and that is the shape the whole mechanism was built to —
/// the tape already holds everything either side asked for that step, bot
/// included, so a replay hands it to `StrategySimulation.step` directly
/// instead of asking `Match.step` to go through the bots a second time. What
/// is staged, stepped and compared here is the simulation the tape actually
/// replays, not the match around it — a bot's own head (`Bot.save`) is no
/// part of a demo for the reason it is part of a save and not this: only
/// `RunSession` resumes a launch, and only a save needs to remember what a
/// bot was thinking between two of them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;
const String _mapAsset = 'assets/levels/map_a.json';

StrategyMap _map() =>
    StrategyMap.parse(File(_mapAsset).readAsStringSync());

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

void main() {
  test(
    'a stretch of the shipped map replays to the same snapshot and digests',
    () {
      const steps = 600;
      final levelHash = contentDigestHex(
        jsonDecode(File(_mapAsset).readAsStringSync()) as Map<String, Object?>,
      );

      final live = openMatch(_map());
      final command = CommandPost(
        simulation: live.simulation,
        side: viewerSide,
      );
      final start = live.simulation.save();
      final recorder = OrderTapeRecorder(seed: live.simulation.random.state);
      live.simulation.orders.recorder = recorder;
      final liveCheckpoints = DigestTrace();
      for (var i = 0; i < steps; i++) {
        // The near side's own policy, the same one the screen asks on the
        // player's behalf every frame; the far side's bot, called directly
        // rather than through `Match.step`, so the loop below can be repeated
        // for the replay with only the bot's half missing.
        command.restock();
        for (final bot in live.match.bots) {
          bot.step(live.simulation);
        }
        live.simulation.step(_dt);
        liveCheckpoints.observe(
          recorder.tape.steps,
          live.simulation.save().toJson(),
        );
      }
      live.simulation.orders.recorder = null;
      final ending = _bytes(live.simulation.save());
      expect(
        ending,
        isNot(_bytes(start)),
        reason: 'a stretch in which nothing happened would prove nothing',
      );

      final sent = jsonEncode(
        MatchDemo(
          level: _mapAsset,
          levelHash: levelHash,
          start: start,
          tape: recorder.tape,
          buildStamp: 'test-build',
          checkpoints: liveCheckpoints,
        ).toJson(),
      );
      final demo = MatchDemo.fromJson(
        jsonDecode(sent) as Map<String, Object?>,
      );
      expect(demo.steps, steps);
      expect(demo.levelHash, levelHash);

      final replay = openMatch(_map());
      replay.simulation.restore(demo.start);
      final playback = OrderTapePlayback(demo.tape);
      final replayCheckpoints = DigestTrace();
      var replayedSteps = 0;
      while (!playback.isFinished) {
        playback.applyTo(replay.simulation.orders);
        replay.simulation.step(_dt);
        replayedSteps++;
        replayCheckpoints.observe(
          replayedSteps,
          replay.simulation.save().toJson(),
        );
      }

      expect(_bytes(replay.simulation.save()), ending);
      expect(
        replayCheckpoints.divergenceFromHex(demo.checkpoints.hexDigests),
        isNull,
        reason:
            'the replay should check out against the document\'s own trace, '
            'not only end at the same byte',
      );
    },
  );
}
