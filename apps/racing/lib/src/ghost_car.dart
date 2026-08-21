import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:vector_math/vector_math.dart';

import 'looks.dart';

/// The best lap somebody has driven here, kept between launches.
///
/// **Two hundred and ninety lines of ghost were written, tested and never
/// used.** `GhostRecorder`, `GhostTape` and `GhostPlayer` have been in the
/// racing package since it existed, with a test file of their own, and the game
/// called none of them: there was nothing to record a lap into, nothing to keep
/// it in and nothing to draw it as. This is those three things.
///
/// One tape per track, because a lap of one circuit means nothing on another —
/// and because a player who has a best lap on the ring and then drives somewhere
/// else should still have it when they come back.
final class GhostKeeper {
  GhostKeeper({required this.storage, required this.track});

  final Storage storage;

  /// Which circuit this is a lap of. Part of the filename for the reason above.
  final String track;

  String get _name => 'ghost-${track.split('/').last.replaceAll('.json', '')}.json';

  final GhostRecorder _recorder = GhostRecorder();

  /// The lap being driven, sampled as it goes.
  ///
  /// Recorded always, not only when it is going to be a good one: whether a lap
  /// was the best is only knowable when it ends, and by then it is too late to
  /// have been writing it down.
  void watch(double lapTime, VehicleController car) =>
      _recorder.tick(lapTime, car);

  /// The lap to beat here, in seconds, or null before anybody has driven one.
  ///
  /// **The tape's own time, not a number kept beside it.** One document, so the
  /// ghost a player is racing and the time they are chasing cannot come apart —
  /// a record that says 1:58 with a two-minute car on the track would make a
  /// liar of one of the two, and there would be no telling which.
  double? get record => best?.lapTime;

  /// A lap has ended. Keeps it if it beat the record, and starts the next.
  ///
  /// Returns whether it was kept, which is worth saying out loud to a player.
  ///
  /// **Against the record, not against this session.** It used to ask the
  /// simulation whether the lap was the best *so far*, and a race begins with
  /// no laps in it — so the first lap of every launch was the best by
  /// definition, and the out-lap somebody drove while getting used to the car
  /// overwrote a record they had spent an evening on. The ghost they were about
  /// to race went with it.
  bool finished(double lapTime) {
    final tape = _recorder.finish(lapTime);
    _recorder.reset();
    final standing = record;
    if (standing != null && lapTime >= standing) return false;
    // A lap with two samples in it is a lap somebody drove through a wall, and
    // a ghost of it would be a car sliding across the infield.
    if (tape.poses.length < 4) return false;
    best = tape;
    _write(tape);
    return true;
  }

  /// One step of a race, from the keeper's side: close a lap if one ended,
  /// then sample the one being driven. Returns whether the lap that ended is
  /// the new record.
  ///
  /// The finishing step arrives with `lapTime` already back at nought — the
  /// simulation resets it as it counts the lap — so the lap is closed with
  /// [RacerProgress.lastLap] and the sample that follows belongs to the new
  /// one, taken at the line rather than a sixtieth of a second past it.
  ///
  /// **Sampling first is not the disaster it looks like**, and this was worth
  /// finding out rather than asserting: a frame stamped nought appended to a
  /// four-second tape would end the recording before its own beginning, and the
  /// playback would draw nothing ever again — except that [Recorder] drops it,
  /// because its next sample is not due for another fifteenth. The order here
  /// is the honest one, not a guard.
  ///
  /// It lives here rather than in the game's step for the reason this whole
  /// file exists: a ghost that nothing calls is a ghost nobody sees, and a
  /// method can be tested where four lines inside a widget cannot.
  bool stepped(RacerProgress player, VehicleController car) {
    final record =
        player.lapCompletedThisStep && finished(player.lastLap);
    watch(player.lapTime, car);
    return record;
  }

  /// The lap to race against, or null the first time anybody drives here.
  GhostTape? best;

  /// Reads whatever is on disk. Never throws — a ghost that will not read is a
  /// lap to beat again, which is a much smaller loss than a game that will not
  /// start.
  void load() {
    final text = storage.read(_name);
    if (text == null) return;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return;
      best = ghostTapeFromJson(json);
    } catch (error) {
      debugPrint('ghost: could not read $_name, starting fresh ($error)');
      storage.remove(_name);
    }
  }

  void _write(GhostTape tape) {
    try {
      storage.write(_name, jsonEncode(tape.toJson()));
    } catch (error) {
      debugPrint('ghost: could not write $_name ($error)');
    }
  }
}

/// The car a ghost is drawn as.
///
/// **Not in the collision world, not stepped, and it cannot be hit.** A ghost
/// that could be collided with would be a car from a previous lap blocking the
/// one being driven, which is the one thing it must never do — the engine's
/// `Playback` says the same in its own words, and this is the half of it that
/// is made of geometry.
final class GhostCar {
  GhostCar(this.node);

  final SceneNode node;

  final Pose _at = Pose();

  /// Puts the ghost where the recorded lap was at [lapTime], or hides it.
  ///
  /// Hidden rather than left where it was: a ghost that stops at the point the
  /// recording ran out reads as a car parked on the racing line.
  void showAt(double lapTime, GhostTape tape, double lift) {
    if (!Playback(tape).sampleAt(lapTime, _at)) {
      node.visible = false;
      return;
    }
    node.visible = true;
    // Lifted along the ghost's own up rather than the world's, for the same
    // reason the cars are: on a cambered corner the two differ by most of a
    // metre.
    node
      ..setPosition(
        _at.position.x + _at.up.x * lift,
        _at.position.y + _at.up.y * lift,
        _at.position.z + _at.up.z * lift,
      )
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _at.yaw));
  }

  /// A box, translucent, in the colour nothing else on the track is.
  static GhostCar build(GraphicsDevice device, Scene scene) {
    final node = carBox(device, Looks.ghost(), name: 'ghost')..visible = false;
    scene.add(node);
    return GhostCar(node);
  }
}
