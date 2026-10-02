import '../input/input_tape.dart';
import '../level/level.dart';
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
///
/// ## `HR3`: a level edited under the run
///
/// [levelSwaps] are the edits the editor sent into the game while this run
/// was recorded, each with the whole document and the step it took effect
/// before. Without them a run with an edit in it parts from its own replay at
/// the edit, and the checkpoints say so without saying why.
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
    this.levelSwaps = const <DemoLevelSwap>[],
  });

  /// Bumped when an existing field changes meaning.
  ///
  /// **2 is written only by a run with [levelSwaps] in it.** A build that
  /// reads 1 would play such a file through the first level to the end and
  /// report a divergence nobody can explain; refusing it with "a newer build"
  /// is the honest answer. A run with no edit in it means exactly what it
  /// meant before, so it is still written as 1 and older builds still open
  /// it.
  static const int formatVersion = 2;

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

  /// The levels put under the run while it was recorded, in step order, no
  /// two at the same step. Empty for a run played in one level throughout.
  ///
  /// [level] and [levelHash] still name the level the run started in: that
  /// is the one a replay loads, and these are swapped in as the tape reaches
  /// them.
  final List<DemoLevelSwap> levelSwaps;

  /// How many fixed steps the run lasted.
  int get steps => tape.steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': levelSwaps.isEmpty ? 1 : formatVersion,
    'level': level,
    'levelHash': levelHash,
    'run': start.toJson(),
    'tape': tape.toJson(),
    'buildStamp': buildStamp,
    'checkpoints': checkpoints.toJson(),
    if (platform != null) 'platform': platform,
    if (recordedBy != null) 'recordedBy': recordedBy,
    if (dataSources != null) 'dataSources': dataSources!.toJson(),
    if (levelSwaps.isNotEmpty)
      'levelSwaps': <Map<String, Object?>>[
        for (final swap in levelSwaps) swap.toJson(),
      ],
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
    final readTape = InputTape.fromJson(tape);
    return Demo(
      level: level,
      levelHash: levelHash,
      start: start,
      tape: readTape,
      buildStamp: buildStamp,
      checkpoints: trace,
      platform: platform is String ? platform : null,
      recordedBy: recordedBy is String ? recordedBy : null,
      dataSources: dataSources,
      levelSwaps: _readSwaps(json['levelSwaps'], steps: readTape.steps),
    );
  }

  static List<DemoLevelSwap> _readSwaps(Object? raw, {required int steps}) {
    if (raw == null) return const <DemoLevelSwap>[];
    if (raw is! List) {
      throw const DemoFormatException('the level swaps are not a list');
    }
    final swaps = <DemoLevelSwap>[
      for (final entry in raw) DemoLevelSwap._fromJson(entry, steps: steps),
    ];
    for (var i = 1; i < swaps.length; i++) {
      if (swaps[i].step <= swaps[i - 1].step) {
        throw DemoFormatException(
          'the level swap at step ${swaps[i].step} comes after the one at '
          'step ${swaps[i - 1].step}; swaps are written in step order, one '
          'per step',
        );
      }
    }
    return List<DemoLevelSwap>.unmodifiable(swaps);
  }
}

/// One level put under a recorded run: [level] took effect before step
/// [step] of the tape, that is, after [step] of its frames had been played.
///
/// **The whole document, not only its digest.** The level a game was edited
/// into exists in the editor that sent it and nowhere a replay can look it
/// up — not in the game's assets, which still hold the level as shipped. A
/// digest alone would make the file unplayable everywhere but the machine
/// that recorded it, on the afternoon it was recorded.
final class DemoLevelSwap {
  const DemoLevelSwap({required this.step, required this.level});

  final int step;
  final Level level;

  /// [Level.digestHex] of [level], what the editor and the timeline call it.
  String get levelHash => level.digestHex;

  Map<String, Object?> toJson() => <String, Object?>{
    'step': step,
    'levelHash': levelHash,
    'document': level.toJson(),
  };

  /// **The digest is checked against the document**, as
  /// `ext.flutter3d.level.apply` checks it: a document that no longer
  /// digests to what was written beside it is not the level the run was
  /// played in.
  factory DemoLevelSwap._fromJson(Object? json, {required int steps}) {
    if (json is! Map<String, Object?>) {
      throw const DemoFormatException('a level swap is not a document');
    }
    final step = json['step'];
    if (step is! int || step < 0 || step > steps) {
      throw DemoFormatException(
        'a level swap names step $step, and the tape has steps 0 to $steps',
      );
    }
    final hash = json['levelHash'];
    final document = json['document'];
    if (hash is! String || document is! Map<String, Object?>) {
      throw DemoFormatException(
        'the level swap at step $step has no level hash or no document',
      );
    }
    final Level level;
    try {
      level = Level.fromJson(document);
    } on LevelFormatException catch (error) {
      throw DemoFormatException(
        'the level swapped in at step $step: ${error.message}',
      );
    }
    if (level.digestHex != hash) {
      throw DemoFormatException(
        'the level swapped in at step $step digests to ${level.digestHex}, '
        'not $hash; the document changed after it was written',
      );
    }
    return DemoLevelSwap(step: step, level: level);
  }
}

/// Thrown when a demo cannot be read at all.
final class DemoFormatException implements Exception {
  const DemoFormatException(this.message);

  final String message;

  @override
  String toString() => 'DemoFormatException: $message';
}
