import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // Storage
import 'package:flutter3d_game_kit/ghost.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';

import 'looks.dart';

/// The best lap somebody has driven here, kept between launches.
///
/// **Two hundred and ninety lines of ghost were written, tested and never
/// used.** `GhostRecorder`, `GhostTape` and `GhostPlayer` have been in the
/// racing package since it existed, and the game called none of them. The
/// keeping — against the record rather than the session, never throwing on a
/// file that will not read — is the ghost addon's [BestRun]; what is here is
/// this game's: one tape per circuit, the lap document the racing package
/// writes, and where a car keeps its place, heading and up.
final class GhostKeeper {
  GhostKeeper({required Storage storage, required this.track})
    : _best = BestRun(
        storage: storage,
        name: 'ghost-${track.split('/').last.replaceAll('.json', '')}.json',
        encode: (GhostTape tape) => tape.toJson(),
        decode: ghostTapeFromJson,
      );

  /// Which circuit this is a lap of. Part of the filename: a lap of one
  /// circuit means nothing on another.
  final String track;

  final BestRun _best;

  /// The lap being driven, sampled as it goes. The middle column of the car's
  /// basis is its own up, which makes a ghost on a banked corner lean with
  /// the road.
  void watch(double lapTime, VehicleController car) => _best.watch(
    lapTime,
    position: car.position,
    yaw: car.headingYaw,
    up: car.visualBasis.getColumn(1),
  );

  /// The lap to beat here, in seconds, or null before anybody has driven one.
  double? get record => _best.record;

  /// A lap has ended. Keeps it if it beat the record, and starts the next.
  /// Returns whether it was kept.
  bool finished(double lapTime) => _best.finished(lapTime);

  /// One step of a race, from the keeper's side: close a lap if one ended,
  /// then sample the one being driven. Returns whether the lap that ended is
  /// the new record.
  ///
  /// The finishing step arrives with `lapTime` already back at nought — the
  /// simulation resets it as it counts the lap — so the lap is closed with
  /// [RacerProgress.lastLap] and the sample that follows belongs to the new
  /// one, taken at the line rather than a sixtieth of a second past it. A
  /// frame stamped nought after a four-second tape is dropped by `Recorder`,
  /// whose next sample is not due for another fifteenth.
  bool stepped(RacerProgress player, VehicleController car, bool lapped) {
    final record = lapped && finished(player.lastLap);
    watch(player.lapTime, car);
    return record;
  }

  /// The lap to race against, or null the first time anybody drives here.
  GhostTape? get best => _best.best;

  /// Reads whatever is on disk. Never throws.
  Future<void> load() => _best.load();
}

/// The ghost car: the same car the field drives, translucent, in the colour
/// nothing else on the track is — or the box the cars fall back to when
/// [model], the asset the grid was built from, could not be read.
///
/// **The shape has to be the car's.** A ghost is read at a glance and at
/// speed, and what makes it legible as *the lap you drove* is that it is the
/// thing you are driving.
Ghost carGhost(GraphicsDevice device, Scene scene, {ModelAsset? model}) =>
    Ghost.build(
      scene,
      look: Looks.ghost(),
      model: model,
      fallback: () {
        final box = carBox(device, Looks.ghost(), name: 'ghost');
        scene.add(box);
        return box;
      },
    );
