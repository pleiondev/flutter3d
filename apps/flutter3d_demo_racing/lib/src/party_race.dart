import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_race.dart';

/// A race of up to [cars] machines, each driving the car its party slot
/// names, kept in step by [PartyRollback] — `NetRace` for more than two.
///
/// **Every slot ghosts until its machine's frames come**, as `NetRace`'s
/// two do and for its reason: the first steps of a run have no frames from
/// anybody, a machine that has not joined sends none at all, and every
/// machine has to agree what such a car did. A car with no frame drives on
/// at the same gentle throttle everywhere.
final class PartyRace {
  PartyRace({
    required RacingSimulation sim,
    required this.wire,
    required this.cars,
    required this.localInput,
    int inputDelay = 3,
    int maxRollbackFrames = 20,
    void Function(
      int step,
      Snapshot after,
      Map<int, Map<String, Object?>> frames,
    )?
    onSettled,
    void Function(int from, Map<String, Object?> message)? onMessage,
  }) : assert(cars >= 2, 'a party is at least two'),
       // ignore: prefer_initializing_formals
       _sim = sim {
    session = PartyRollback<Snapshot>(
      wire: wire,
      players: cars,
      captureLocalFrame: () => captureDriverFrame(localInput),
      applyAndStep: _applyAndStep,
      save: _sim.save,
      restore: _sim.restore,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      onSettled: onSettled,
      onMessage: onMessage,
    );
  }

  final RacingSimulation _sim;
  final PartyWire wire;

  /// How many cars the race has — the party's size.
  final int cars;
  final InputState localInput;
  late final PartyRollback<Snapshot> session;

  /// The car this machine drives.
  int get localCarIndex => wire.slot;

  /// The slots a frame has come from, so far.
  final Set<int> heard = <int>{};

  void _applyAndStep(Map<int, Map<String, Object?>> frames) {
    for (var car = 0; car < cars; car++) {
      final frame = frames[car] ?? const <String, Object?>{};
      if (frame.isNotEmpty && car != localCarIndex) heard.add(car);
      final out = _sim.inputs[car];
      if (frame.isEmpty) {
        out
          ..throttle = 0.3
          ..brake = 0.0
          ..handbrake = false
          ..steer = 0.0;
      } else {
        applyDriverFrame(frame, out);
      }
    }
    _sim.step(1.0 / 60.0);
  }

  void advance() => session.advance();
}
