/// The shipped map stepped by the engine's loop, as the screen steps it: the
/// same match as the hand-written loop it replaced, and written down with a
/// pose record beside its tape, and the loop's journal and event digests
/// beside that.
///
///     flutter test test/loop_test.dart
///
/// **Why the first test is the one that matters.** Every match this game
/// has recorded was stepped by a loop written out in the widget — restock,
/// the match, the checkpoint, the prune — and the screen now runs the same
/// four as systems in the `input`, `physics` and `publish` phases of an
/// `EngineLoop`. A tape replays only if nothing ran between them that did
/// not before, and two runs of the map coming out the same to the byte is
/// what says so.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/map_world.dart';
import 'package:flutter3d_demo_strategy/src/match_recording.dart';
import 'package:flutter3d_demo_strategy/src/run.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart' show viewerSide;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const String _mapAsset = 'assets/levels/map_a.json';

StrategyMap _map() => StrategyMap.parse(File(_mapAsset).readAsStringSync());

String _bytes(Snapshot snapshot) => jsonEncode(snapshot.toJson());

/// The screen's loop around [start]: the plugin's step, and the screen's
/// own systems in the phases `main.dart` gives them.
EngineLoop _loopFor(
  StrategyStart start,
  CommandPost command,
  MatchRecording? recording,
) {
  final plugin = StrategyPlugin(kinds: strategyKinds)..simulation = start.match;
  return EngineLoop(
      input: InputState(),
      timing: strategyWorld,
      plugins: <Flutter3dPlugin>[plugin],
      registries: <PluginRegistry>[EntityKinds()],
    )
    ..addSystem('restock', LoopPhase.input, (_) => command.restock())
    ..addSystem(
      'record',
      LoopPhase.publish,
      (_) => recording?.observe(start.simulation),
    )
    ..addSystem(
      'prune',
      LoopPhase.publish,
      (_) => command.prune(),
      after: const <String>['record'],
    );
}

void main() {
  test('the loop steps the shipped map to the bytes the hand-written loop '
      'did', () {
    const steps = 900;
    final byHand = openMatch(_map());
    final handWorld = mapWorldOf(byHand.simulation);
    final handCommand = CommandPost(
      simulation: byHand.simulation,
      side: viewerSide,
    );
    for (var i = 0; i < steps; i++) {
      handCommand.restock();
      byHand.match.step(strategyStep);
      handCommand.prune();
    }

    final looped = openMatch(_map());
    final loopWorld = mapWorldOf(looped.simulation);
    final loop = _loopFor(
      looped,
      CommandPost(simulation: looped.simulation, side: viewerSide),
      null,
    );
    loop.runSteps(steps);

    // Mutation: register the restock in `publish` rather than `input`. The
    // near camp's order then reaches the step after the one it reached, and
    // the crowd parts within the first production cycle.
    expect(loop.stepSeconds, strategyStep, reason: 'another step size');
    expect(_bytes(looped.simulation.save()), _bytes(byHand.simulation.save()));
    handWorld.dispose();
    loopWorld.dispose();
  });

  test('a match recorded through the loop carries where its crowd stood', () {
    final start = openMatch(_map());
    final world = mapWorldOf(start.simulation);
    final recording = MatchRecording(
      level: _mapAsset,
      levelHash: 'test',
      simulation: start.simulation,
    );
    final loop = _loopFor(
      start,
      CommandPost(simulation: start.simulation, side: viewerSide),
      recording,
    );
    recording.attach(loop);

    loop.runSteps(4 * matchPoseEvery);
    recording.stop(start.simulation);
    final match = RecordedMatch.fromJson(
      jsonDecode(jsonEncode(recording.recorded(buildStamp: 'test').toJson()))
          as Map<String, Object?>,
    );
    final demo = match.demo;
    world.dispose();

    // Mutation: drop `attach`'s first entry. A replay then starts from the
    // engine's defaults with nothing saying which plugins the match had.
    expect(match.loopChanges.first, isA<LoopPluginChange>());
    expect(match.loopChanges.first.step, 0);
    // Mutation: write the digest at `steps` rather than `steps - 1`. The
    // last step's events then land past the tape.
    final EventTrace? events = match.events;
    expect(events, isNotNull);
    expect(events!.steps.every((int s) => s < 4 * matchPoseEvery), isTrue);

    // Mutation: leave `poses:` out of `MatchRecording.demo`. The file then
    // carries no record, and a build on other rules that refuses the tape
    // has nothing to show instead.
    final PoseRecord? poses = demo.poses;
    expect(poses, isNotNull);
    expect(
      <int>[for (final f in poses!.frames) f.step],
      <int>[
        matchPoseEvery,
        2 * matchPoseEvery,
        3 * matchPoseEvery,
        4 * matchPoseEvery,
      ],
    );
    // Every unit standing is in the record, under its entity's name, and
    // its last place is where it stands now.
    final StrategyUnit unit = start.simulation.units.first;
    final String name = 'unit.${unit.entity.packed}';
    expect(poses.bodies, contains(name));
    expect(
      poses.bodies.length,
      greaterThanOrEqualTo(start.simulation.units.length),
    );
    final Pose last = poses.track(name).poses.last;
    expect(last.position.x, closeTo(unit.position.x, 0.002));
    expect(last.position.z, closeTo(unit.position.z, 0.002));
    expect(demo.tape.steps, 4 * matchPoseEvery);
    expect(demo.simulation, strategySimulationVersion);
  });
}
