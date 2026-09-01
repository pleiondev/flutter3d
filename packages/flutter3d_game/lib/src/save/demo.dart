import '../input/input_tape.dart';
import 'snapshot.dart';

/// A run, as a file somebody can send: where it started and what they did.
///
/// **A save plus a tape, and that arithmetic is the design.** A save is a level
/// and a [Snapshot] — where the player got to. A demo is the same two things
/// and an [InputTape] — where they started and everything they did after. Fed
/// to the same simulation the tape produces the same run, exactly, which is
/// what ARCHITECTURE.md §9.3 promises and `input_tape_test.dart` measures.
///
/// One document rather than two mechanisms, for the reason `snapshot.dart`
/// gives for itself: a replay, the input to a determinism test and the file
/// attached to a bug report are the same bytes in three uses, and keeping
/// three of those right costs three times what keeping one right costs.
///
/// **What it is for**, in the order the games will use it:
///
/// * a bug that happens once in a thousand steps, reproduced from the file the
///   player attached rather than from their description of it;
/// * a test that plays a whole level and asserts where it ended, written by
///   playing the level once;
/// * a replay, at a few bytes a step rather than a pose per body per step.
///
/// **It is not a recording of positions.** The racing game's ghost is that,
/// and is right to be — it has to survive the physics changing underneath it.
/// This must not: a demo that still reached the exit after the collision
/// changed would be a recording of nothing.
///
/// ## Versioning
///
/// The same shape as the level and the snapshot: a document from a newer
/// build is refused with a sentence rather than misread, and a missing field
/// is refused rather than defaulted, because a demo with no tape is not a
/// demo with an empty tape — it is a file that was not written all the way.
final class Demo {
  const Demo({required this.level, required this.start, required this.tape});

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// The asset path of the level the run was played in.
  ///
  /// Stored and checked for the reason `SaveFile` gives: a tape played into
  /// the wrong level walks the player into a wall, and the positions that
  /// follow are real numbers that mean nothing there.
  final String level;

  /// The state the tape starts from, dice included.
  ///
  /// A snapshot rather than a seed alone: a demo may begin mid-run, after a
  /// save was restored, and the state it begins from is whatever the level was
  /// in at that moment — not a fresh level with a fresh generator.
  final Snapshot start;

  /// What the player did, one entry per fixed step.
  final InputTape tape;

  /// How many fixed steps the run lasted.
  int get steps => tape.steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'level': level,
    'run': start.toJson(),
    'tape': tape.toJson(),
  };

  /// Reads a demo, or throws a [DemoFormatException] that says why not.
  ///
  /// Throws rather than returning null, because every reason is worth a
  /// sentence: a demo from a newer build can still be opened by the build that
  /// wrote it, and a file with no tape in it was cut short by whatever wrote
  /// it, and the player who attached it deserves to be told which.
  factory Demo.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! num) {
      throw const DemoFormatException('the document has no version in it');
    }
    if (version > formatVersion) {
      throw DemoFormatException(
        'the demo was written by a newer build (format $version, this build '
        'reads $formatVersion)',
      );
    }
    final level = json['level'];
    if (level is! String || level.isEmpty) {
      throw const DemoFormatException('the demo names no level');
    }
    final run = json['run'];
    if (run is! Map<String, Object?>) {
      throw const DemoFormatException('the demo has no starting state');
    }
    final tape = json['tape'];
    if (tape is! Map<String, Object?>) {
      throw const DemoFormatException(
        'the demo has no tape, so it was not written all the way',
      );
    }
    final Snapshot start;
    try {
      start = Snapshot.fromJson(run);
    } on SnapshotFormatException catch (error) {
      throw DemoFormatException('the starting state: ${error.message}');
    }
    return Demo(level: level, start: start, tape: InputTape.fromJson(tape));
  }
}

/// Thrown when a demo cannot be read at all.
final class DemoFormatException implements Exception {
  const DemoFormatException(this.message);

  final String message;

  @override
  String toString() => 'DemoFormatException: $message';
}
