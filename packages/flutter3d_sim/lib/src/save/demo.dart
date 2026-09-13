import '../input/input_tape.dart';
import 'data_source_trace.dart';
import 'snapshot.dart';
import 'state_digest.dart';

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
///
/// ## `rp-01`: what a run needs to be verified, not only replayed
///
/// [levelHash] and [buildStamp] answer "is this still the run it claims to
/// be" — a tape played into a level that has since been edited walks into
/// geometry that is not there any more, and a bug reproduced on a different
/// build may be reproducing a bug that was already fixed. [checkpoints] is
/// what turns "replayed to the end" into "replayed to the bit": the same
/// [DigestTrace] `rp-00`'s parity files compare platforms with, taken while
/// this run was recorded, so that a replay's own trace can be checked
/// against it rather than merely watched. All three are required, the same
/// strictness [tape] already had — a run nobody can verify is a run that
/// silently degrades to a video. [platform] and [recordedBy] are the
/// genuinely optional half: worth keeping when known, meaningless to invent
/// when not.
final class Demo {
  const Demo({
    required this.level,
    required this.levelHash,
    required this.start,
    required this.tape,
    required this.buildStamp,
    required this.checkpoints,
    this.platform,
    this.recordedBy,
    this.dataSources,
  });

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// The extension a run is written under — `.f3drun`, wherever it becomes an
  /// actual file: attached to a bug report, downloaded from the cloud, or
  /// dropped on an editor window.
  static const String fileExtension = '.f3drun';

  /// The asset path of the level the run was played in.
  ///
  /// Stored and checked for the reason `SaveFile` gives: a tape played into
  /// the wrong level walks the player into a wall, and the positions that
  /// follow are real numbers that mean nothing there.
  final String level;

  /// [Level.digestHex] of the level this was recorded against.
  ///
  /// Checked rather than assumed the moment a level might have changed
  /// underneath a tape — `rp-03`'s whole reason for existing. A path staying
  /// the same says nothing about the content behind it; this does.
  final String levelHash;

  /// The state the tape starts from, dice included.
  ///
  /// A snapshot rather than a seed alone: a demo may begin mid-run, after a
  /// save was restored, and the state it begins from is whatever the level was
  /// in at that moment — not a fresh level with a fresh generator.
  final Snapshot start;

  /// What the player did, one entry per fixed step.
  final InputTape tape;

  /// Which build wrote this file, free text.
  ///
  /// `sim` has no opinion on what a build number looks like on any platform
  /// it runs on — a package version, a git commit, a CI run id — the caller's
  /// own name for itself is whatever goes here.
  final String buildStamp;

  /// A digest every so many steps, taken while this run was recorded.
  final DigestTrace checkpoints;

  /// Which platform recorded this, free text — `'macos'`, `'chrome'`,
  /// `'android'` — or null when the caller does not know or does not say.
  final String? platform;

  /// Who recorded it — an account name, a player id — or null for anonymous.
  final String? recordedBy;

  /// `edu-05`: every `edu_data_source` this run read, one entry per fixed
  /// step it was read at — null for a run that bound none, the same
  /// genuinely-optional shape [platform]/[recordedBy] already have. Additive
  /// like they are: an older reader ignoring a field it never knew is a run
  /// with no recorded bindings, not a run misread.
  final DataSourceTrace? dataSources;

  /// How many fixed steps the run lasted.
  int get steps => tape.steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'level': level,
    'levelHash': levelHash,
    'run': start.toJson(),
    'tape': tape.toJson(),
    'buildStamp': buildStamp,
    'checkpoints': checkpoints.toJson(),
    if (platform != null) 'platform': platform,
    if (recordedBy != null) 'recordedBy': recordedBy,
    if (dataSources != null) 'dataSources': dataSources!.toJson(),
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
        'reads $formatVersion) — update flutter3d to open it',
      );
    }
    final level = json['level'];
    if (level is! String || level.isEmpty) {
      throw const DemoFormatException('the demo names no level');
    }
    final levelHash = json['levelHash'];
    if (levelHash is! String || levelHash.isEmpty) {
      throw const DemoFormatException(
        'the demo names no level hash, so it cannot say whether the level '
        'has changed since it was recorded',
      );
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
    final buildStamp = json['buildStamp'];
    if (buildStamp is! String || buildStamp.isEmpty) {
      throw const DemoFormatException('the demo names no build stamp');
    }
    final checkpoints = json['checkpoints'];
    if (checkpoints is! Map<String, Object?>) {
      throw const DemoFormatException(
        'the demo has no checkpoints, so a replay of it cannot be verified',
      );
    }
    final Snapshot start;
    try {
      start = Snapshot.fromJson(run);
    } on SnapshotFormatException catch (error) {
      throw DemoFormatException('the starting state: ${error.message}');
    }
    final DigestTrace trace;
    try {
      trace = DigestTrace.fromJson(checkpoints);
    } on DigestTraceFormatException catch (error) {
      throw DemoFormatException('the checkpoints: ${error.message}');
    }
    final platform = json['platform'];
    final recordedBy = json['recordedBy'];
    final rawDataSources = json['dataSources'];
    DataSourceTrace? dataSources;
    if (rawDataSources is Map<String, Object?>) {
      try {
        dataSources = DataSourceTrace.fromJson(rawDataSources);
      } on DataSourceTraceFormatException catch (error) {
        throw DemoFormatException('the data sources: ${error.message}');
      }
    }
    return Demo(
      level: level,
      levelHash: levelHash,
      start: start,
      tape: InputTape.fromJson(tape),
      buildStamp: buildStamp,
      checkpoints: trace,
      platform: platform is String ? platform : null,
      recordedBy: recordedBy is String ? recordedBy : null,
      dataSources: dataSources,
    );
  }
}

/// Thrown when a demo cannot be read at all.
final class DemoFormatException implements Exception {
  const DemoFormatException(this.message);

  final String message;

  @override
  String toString() => 'DemoFormatException: $message';
}
