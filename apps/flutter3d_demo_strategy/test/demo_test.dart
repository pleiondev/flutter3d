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
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/map_world.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const String _mapAsset = 'assets/levels/map_a.json';

StrategyMap _map() => StrategyMap.parse(File(_mapAsset).readAsStringSync());

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

/// Where everybody stands, and nothing else.
String _crowd(StrategySimulation simulation) => jsonEncode(<List<double>>[
  for (final Unit unit in simulation.units)
    <double>[unit.position.x, unit.position.z],
]);

void main() {
  test('a stretch of the shipped map replays to the same snapshot and digests, '
      'and its world to the same bits', () {
    // Twenty seconds: long enough for a squad sent from the near camp to
    // reach the ford and wade it.
    const steps = 1200;
    final levelHash = contentDigestHex(
      jsonDecode(File(_mapAsset).readAsStringSync()) as Map<String, Object?>,
    );

    final live = openMatch(_map());
    final liveWorld = mapWorldOf(live.simulation);
    final command = CommandPost(simulation: live.simulation, side: viewerSide);
    final start = live.simulation.save();
    expect(
      jsonEncode(start.toJson()),
      contains('"map world"'),
      reason: 'a start with no world in it would verify nothing of it',
    );
    final recorder = OrderTapeRecorder(seed: live.simulation.random.state);
    live.simulation.orders.recorder = recorder;
    final liveCheckpoints = DigestTrace();

    // A dozen of the near camp's diggers sent over the ford, the way a
    // player's clicks send them, orders on the tape like any other: first to
    // the near bank, then, once there, across. Sent straight over, their
    // way rounded the spring at the river's head and never got wet.
    final Vector3 ford = liveWorld.fords.first;
    final List<Building> halls = live.simulation.buildings;
    final Vector3 way = halls[1].center - halls[0].center
      ..y = 0.0
      ..normalize();
    final corner = Vector3(23.5, 0.0, 43.5),
        opposite = Vector3(28.0, 0.0, 47.0);
    final List<Unit> squad = UnitSelection(
      live.simulation.units,
    ).unitsWithin(corner, opposite);
    expect(command.selectWithin(corner, opposite), greaterThan(6));
    expect(command.orderTo(ford - way * 6.0), isTrue);
    var wettest = 0.0;

    for (var i = 0; i < steps; i++) {
      if (i == 700) expect(command.orderTo(ford + way * 8.0), isTrue);
      // The near side's own policy, the same one the screen asks on the
      // player's behalf every frame; the far side's bot, called directly
      // rather than through `Match.step`, so the loop below can be repeated
      // for the replay with only the bot's half missing. The world steps
      // inside the simulation's step, as it does on the screen.
      command.restock();
      for (final bot in live.match.bots) {
        bot.step(live.simulation);
      }
      live.simulation.step(_dt);
      if (recorder.tape.steps % liveCheckpoints.every == 0) {
        liveCheckpoints.observe(
          recorder.tape.steps,
          live.simulation.save().toJson(),
        );
      }
      for (final Unit unit in squad) {
        final NativeShallowSample? water = liveWorld.world.sampleShallow(
          liveWorld.river,
          unit.position.x,
          unit.position.z,
        );
        if (water != null && water.depth > wettest) wettest = water.depth;
      }
    }
    live.simulation.orders.recorder = null;
    final ending = _bytes(live.simulation.save());
    final Uint8List liveBits = liveWorld.world.snapshot();
    liveWorld.dispose();
    expect(
      wettest,
      greaterThan(0.05),
      reason: 'a stretch in which nobody waded would prove nothing of it',
    );
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
    final demo = MatchDemo.fromJson(jsonDecode(sent) as Map<String, Object?>);
    expect(demo.steps, steps);
    expect(demo.levelHash, levelHash);

    // The world is built again from the map, as the screen builds it for a
    // match, before the start is put back.
    final replay = openMatch(_map());
    final replayWorld = mapWorldOf(replay.simulation);
    replay.simulation.restore(demo.start);
    final playback = OrderTapePlayback(demo.tape);
    final replayCheckpoints = DigestTrace();
    var replayedSteps = 0;
    while (!playback.isFinished) {
      playback.applyTo(replay.simulation.orders);
      replay.simulation.step(_dt);
      replayedSteps++;
      if (replayedSteps % replayCheckpoints.every == 0) {
        replayCheckpoints.observe(
          replayedSteps,
          replay.simulation.save().toJson(),
        );
      }
    }
    final Uint8List replayBits = replayWorld.world.snapshot();
    final String replayed = _bytes(replay.simulation.save());
    final String replayedCrowd = _crowd(replay.simulation);
    replayWorld.dispose();

    // Mutation: the world not hung on the simulation's entities — the save
    // has no world in it, and the checkpoints below say nothing of the
    // water and the fires.
    expect(replayed, ending);
    expect(
      replayCheckpoints.divergenceFromHex(demo.checkpoints.hexDigests),
      isNull,
      reason:
          'the replay should check out against the document\'s own trace, '
          'not only end at the same byte',
    );
    // The water, the fires and every body thrown, to the bit. Mutation: the
    // world's wind read off the wall clock rather than the match's own
    // (`_windAt(_clock)`), and the bits part.
    expect(listEquals(replayBits, liveBits), isTrue);

    // And the world is part of what is replayed: the same tape played with
    // no world under it — nobody held back by the ford — leaves the crowd
    // somewhere else. Mutation: the world's pace not hung on the simulation
    // (`simulation.pace` left null) makes the two crowds agree.
    final bare = openMatch(_map());
    bare.simulation.restore(demo.start);
    final again = OrderTapePlayback(demo.tape);
    while (!again.isFinished) {
      again.applyTo(bare.simulation.orders);
      bare.simulation.step(_dt);
    }
    expect(_crowd(bare.simulation), isNot(replayedCrowd));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
