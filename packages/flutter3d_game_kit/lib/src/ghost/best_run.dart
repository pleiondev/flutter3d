import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_app/flutter3d_app.dart'
    show Storage, StorageException;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// The best run somebody has made here, kept between launches: the ghost to
/// race, and the time to beat.
///
/// **One document per place.** A run of one course means nothing on another,
/// and a player who has a best on one and then plays somewhere else should
/// still have it when they come back, so [name] is the file it is kept in and
/// the caller makes it from where the run is.
///
/// **Recorded always, not only when it is going to be a good one.** Whether a
/// run was the best is only knowable when it ends, and by then it is too late
/// to have been writing it down; so [watch] samples every run and [finished]
/// decides.
final class BestRun {
  BestRun({
    required this.storage,
    required this.name,
    double hz = 15.0,
    this.fewestPoses = 4,
    Map<String, Object?> Function(Tape tape)? encode,
    Tape Function(Map<String, Object?> json)? decode,
  }) : _recorder = Recorder(hz: hz),
       _encode = encode ?? tapeToJson,
       _decode = decode ?? tapeFromJson;

  final Storage storage;

  /// The file the best run is kept in.
  final String name;

  /// A run with fewer samples than this is not kept: a run with two samples
  /// in it went through a wall, and a ghost of it slides across the map.
  final int fewestPoses;

  final Recorder _recorder;
  final Map<String, Object?> Function(Tape tape) _encode;
  final Tape Function(Map<String, Object?> json) _decode;

  /// The run to race against, or null the first time anybody plays here.
  Tape? best;

  /// The time to beat, in seconds, or null before anybody has finished.
  ///
  /// **The tape's own time, not a number kept beside it.** One document, so
  /// the ghost a player is racing and the time they are chasing cannot come
  /// apart.
  double? get record => best?.seconds;

  /// Samples the run being played, [seconds] into it.
  void watch(
    double seconds, {
    required Vector3 position,
    required double yaw,
    Vector3? up,
  }) => _recorder.tick(seconds, position: position, yaw: yaw, up: up);

  /// A run has ended after [seconds]. Keeps it if it beat the record, and
  /// starts the next. Returns whether it was kept, which is worth saying out
  /// loud to a player; the write finishes on its own — see [saved].
  ///
  /// **Against the record, not against this session.** A session begins with
  /// no runs in it, so the first run of every launch would be the best by
  /// definition, and a warm-up would overwrite a record somebody spent an
  /// evening on.
  bool finished(double seconds) {
    final tape = _recorder.finish(seconds);
    _recorder.reset();
    final standing = record;
    if (standing != null && seconds >= standing) return false;
    if (tape.poses.length < fewestPoses) return false;
    best = tape;
    _write(tape);
    return true;
  }

  /// Reads whatever is kept. Never throws: a best run that will not read is
  /// a run to beat again, which is a much smaller loss than a game that will
  /// not start. The unreadable document is removed.
  Future<void> load() async {
    final text = await storage.read(name);
    if (text == null) return;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return;
      best = _decode(json);
    } catch (error) {
      debugPrint('ghost: could not read $name, starting fresh ($error)');
      await storage.remove(name);
    }
  }

  /// The write [finished] started, for a caller that has to know it landed.
  Future<void> get saved => _saved;
  Future<void> _saved = Future<void>.value();

  void _write(Tape tape) {
    _saved = () async {
      try {
        await storage.write(name, jsonEncode(_encode(tape)));
      } on StorageException catch (error) {
        debugPrint('ghost: could not write $name (${error.message})');
      }
    }();
  }
}

/// The version of the best-run document [tapeToJson] writes, and the newest
/// [tapeFromJson] reads.
///
/// Version 1 is the body every best run has had, `seconds` and `frames`:
/// before 1.0 under a bare `{"version": 1}`, since then in the shared
/// envelope. The body did not change, so the envelope did not move it.
const int ghostTapeFormatVersion = 1;

/// A best run in the registry: `f3d.ghostTape`.
///
/// **Not `f3d.ghost`.** The racing genre's lap (`ghostFormat` in
/// `flutter3d_game_racing`) is a different body, `lapTime` and frames of a
/// car; this is any game's tape of `Pose`s, `seconds` and `frames`. One id
/// for two bodies would let one reader open the other's file and read it
/// wrong, so each keeps its own.
const FormatSpec ghostTapeFormat = FormatSpec(
  id: 'f3d.ghostTape',
  version: ghostTapeFormatVersion,
  suffixes: <String>['.best.json'],
  fixture: 'test/fixtures/v<N>/run.best.json',
);

/// A tape as [BestRun] keeps it when the game names no format of its own:
/// the envelope ([ghostTapeFormat]), then `seconds` and `frames`.
Map<String, Object?> tapeToJson(Tape tape) => <String, Object?>{
  ...ghostTapeFormat.envelope(),
  'seconds': tape.seconds,
  'frames': <Map<String, Object?>>[
    for (final pose in tape.poses) pose.toJson(),
  ],
};

/// Reads back what [tapeToJson] wrote, and the bare `{"version": 1}` shape
/// every best run had before the envelope.
///
/// Throws a [DocumentFormatException] for another format's document or a
/// version newer than [ghostTapeFormatVersion].
Tape tapeFromJson(Map<String, Object?> json) {
  final run = ghostTapeFormat.open(json, refuse: DocumentFormatException.new);
  return Tape(
    seconds: (run['seconds']! as num).toDouble(),
    poses: <Pose>[
      for (final frame in run['frames']! as List<Object?>)
        Pose.fromJson(frame! as Map<String, Object?>),
    ],
  );
}
